import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  String _getChatRoomId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return ids.join('_');
  }

  Future<Map<String, dynamic>> _getUserBasicInfo(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        final name = data['name'] ?? 'Пользователь';
        final lastName = data['lastName'] ?? '';
        return {
          'name': "$name $lastName".trim(),
          'photoUrl': data['photoUrl'] ?? '',
        };
      }
    } catch (_) {}
    return {'name': 'Пользователь', 'photoUrl': ''};
  }
  
  Future<String> getOrCreateChat(String otherUserId) async {
    final chatId = _getChatRoomId(currentUserId, otherUserId);
    final chatDoc = await _db.collection('chats').doc(chatId).get();

    if (!chatDoc.exists) {
      final myInfo = await _getUserBasicInfo(currentUserId);
      final otherInfo = await _getUserBasicInfo(otherUserId);

      await _db.collection('chats').doc(chatId).set({
        'users': [currentUserId, otherUserId], 
        'participants': [currentUserId, otherUserId], 
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$currentUserId': 0,
        'unread_$otherUserId': 0,
        'participant_info': {
          currentUserId: myInfo,
          otherUserId: otherInfo,
        }
      });
    }
    return chatId;
  }

  // FIX READ LEAK: Префиксный серверный поиск вместо скачивания всей БД
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    
    String q = query.trim().toLowerCase();
    if (q.startsWith('@')) q = q.substring(1); 
    
    final snapshot = await _db.collection('users')
        .where('nickname', isGreaterThanOrEqualTo: q)
        .where('nickname', isLessThanOrEqualTo: '$q\uf8ff')
        .limit(20) // Жесткий лимит защиты от спама чтений
        .get();
    
    return snapshot.docs
        .where((doc) => doc.id != currentUserId)
        .map((doc) => {'uid': doc.id, ...doc.data()})
        .toList();
  }

  Future<void> sendMessage(String otherUserId, String text, {File? imageFile}) async {
    final chatId = _getChatRoomId(currentUserId, otherUserId);
    
    String? imageUrl;
    String messageType = 'text';

    if (imageFile != null) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'chats/$chatId/${timestamp}_$currentUserId.jpg';
        final ref = FirebaseStorage.instance.ref().child(path);
        
        await ref.putFile(imageFile);
        imageUrl = await ref.getDownloadURL();
        messageType = 'image';
      } catch (e) {
        return; 
      }
    }
    
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'senderId': currentUserId,
      'receiverId': otherUserId,
      'text': text,
      'type': messageType,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });

    String lastMsgText = text.isEmpty && imageUrl != null ? '📷 Фотография' : text;
    final myInfo = await _getUserBasicInfo(currentUserId);

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': lastMsgText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$otherUserId': FieldValue.increment(1),
      'participant_info': {
        currentUserId: myInfo, 
      }
    }, SetOptions(merge: true));
  }

  // QA FIX: Комплексное удаление сообщения (Firestore + Storage)
  Future<void> deleteMessage(String chatId, String messageId, {String? imageUrl}) async {
    // Шаг 1: Если в сообщении была картинка, удаляем физический файл из Storage
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        debugPrint('Картинка успешно удалена из Storage');
      } catch (e) {
        // Ошибки здесь обычно возникают, если файл уже удален. Глотаем их, чтобы 
        // не прервать удаление самого документа из Firestore.
        debugPrint('Ошибка удаления картинки из Storage (возможно уже удалена): $e');
      }
    }
    
    // Шаг 2: Удаляем документ сообщения из Firestore
    try {
      await _db.collection('chats').doc(chatId).collection('messages').doc(messageId).delete();
    } catch (e) {
      debugPrint('Ошибка удаления документа сообщения: $e');
      rethrow;
    }
  }

  Future<void> resetUnreadCount(String otherUserId) async {
    final chatId = _getChatRoomId(currentUserId, otherUserId);
    await _db.collection('chats').doc(chatId).set({
      'unread_$currentUserId': 0,
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot> getUserChats() {
    return _db.collection('chats')
        .where('users', arrayContains: currentUserId)
        .snapshots();
  }
}