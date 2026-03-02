import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  String _getChatRoomId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return ids.join('_');
  }

  Future<String> getOrCreateChat(String otherUserId) async {
    final chatId = _getChatRoomId(currentUserId, otherUserId);
    final chatDoc = await _db.collection('chats').doc(chatId).get();

    if (!chatDoc.exists) {
      await _db.collection('chats').doc(chatId).set({
        'users': [currentUserId, otherUserId], 
        'participants': [currentUserId, otherUserId], 
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_$currentUserId': 0,
        'unread_$otherUserId': 0,
      });
    }
    return chatId;
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    
    final snapshot = await _db.collection('users').get();
    
    return snapshot.docs.where((doc) {
      if (doc.id == currentUserId) return false; 
      
      final data = doc.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final lastName = (data['lastName'] ?? '').toString().toLowerCase();
      final nickname = (data['nickname'] ?? '').toString().toLowerCase();
      
      return name.contains(q) || lastName.contains(q) || nickname.contains(q);
    }).map((doc) => {'uid': doc.id, ...doc.data()}).toList();
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
    
    await _db.collection('chats').doc(chatId).set({
      'lastMessage': lastMsgText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unread_$otherUserId': FieldValue.increment(1),
    }, SetOptions(merge: true));
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