// Файл: lib/services/chat_service.dart
//
// Надёжный чат между пользователями (P2P и чат со специалистом).
//
// Что было не так раньше и что исправлено:
//  1. Список чатов УДАЛЯЛ документ чата, если профиль собеседника не удалось
//     загрузить (офлайн, VPN, медленная сеть, запрет правил). Из-за этого у
//     пользователей «пропадали» диалоги и сообщения «не доходили».
//  2. Поиск скачивал ВСЮ коллекцию users (включая данные о здоровье) на каждое
//     нажатие клавиши — медленно, дорого и небезопасно. Теперь — префиксный
//     поиск по коллекции public_profiles с лимитом.
//  3. Отправка не имела статусов и обработки ошибок. Теперь у сообщения есть
//     статус (отправляется/отправлено/прочитано), а если соединение Firestore
//     «залипло» (типично для VPN и роуминга), сообщение доставляется через
//     HTTPS-функцию sendChatMessage с тем же ID — без дублей.
//  4. Получение: если поток Firestore долго отдаёт только кэш, экран подтягивает
//     свежие сообщения через HTTPS-функцию fetchChatMessages.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

enum ChatDeliveryState { sending, sent, read, failed }

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final String? imageUrl;
  final DateTime time;
  final bool pending;
  final bool edited;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.time,
    this.imageUrl,
    this.pending = false,
    this.edited = false,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final dynamic ts = data['timestamp'];
    final dynamic clientTs = data['clientTs'];
    DateTime time;
    if (ts is Timestamp) {
      time = ts.toDate();
    } else if (clientTs is Timestamp) {
      time = clientTs.toDate();
    } else {
      time = DateTime.now();
    }
    final String? img = data['imageUrl'] is String ? data['imageUrl'] as String : null;
    return ChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      imageUrl: (img != null && img.isNotEmpty) ? img : null,
      time: time,
      pending: doc.metadata.hasPendingWrites,
      edited: data['edited'] == true,
    );
  }

  factory ChatMessage.fromServer(Map<dynamic, dynamic> m) {
    final int millis = (m['ts'] is num) ? (m['ts'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final String? img = m['imageUrl'] is String ? m['imageUrl'] as String : null;
    return ChatMessage(
      id: (m['id'] ?? '').toString(),
      senderId: (m['senderId'] ?? '').toString(),
      text: (m['text'] ?? '').toString(),
      imageUrl: (img != null && img.isNotEmpty) ? img : null,
      time: DateTime.fromMillisecondsSinceEpoch(millis),
      edited: m['edited'] == true,
    );
  }
}

class PublicProfile {
  final String uid;
  final String name;
  final String nickname;
  final String photoUrl;

  const PublicProfile({required this.uid, required this.name, this.nickname = '', this.photoUrl = ''});

  factory PublicProfile.fromMap(String uid, Map<String, dynamic> data) {
    final String first = (data['name'] ?? '').toString().trim();
    final String last = (data['lastName'] ?? '').toString().trim();
    final String full = [first, last].where((e) => e.isNotEmpty).join(' ');
    final String photo = (data['photoUrl'] ?? '').toString();
    return PublicProfile(
      uid: uid,
      name: full.isEmpty ? 'Пользователь' : full,
      nickname: (data['nickname'] ?? '').toString(),
      photoUrl: photo.startsWith('http') ? photo : '',
    );
  }
}

class P2PChatService {
  P2PChatService._();
  static final P2PChatService _instance = P2PChatService._();
  factory P2PChatService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Map<String, PublicProfile> _profileCache = {};
  Map<String, dynamic>? _myInfoCache;

  String get uid => _auth.currentUser?.uid ?? '';

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  CollectionReference<Map<String, dynamic>> _messages(String collection, String chatId) =>
      _db.collection(collection).doc(chatId).collection('messages');

  // -------------------------------------------------------------------------
  // Потоки
  // -------------------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId, {String collection = 'chats', int limit = 100}) {
    return _messages(collection, chatId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> chatDocStream(String chatId, {String collection = 'chats'}) {
    return _db.collection(collection).doc(chatId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myChatsStream() {
    return _db.collection('chats').where('users', arrayContains: uid).snapshots(includeMetadataChanges: true);
  }

  // -------------------------------------------------------------------------
  // Профили
  // -------------------------------------------------------------------------

  PublicProfile? cachedProfile(String otherUid) => _profileCache[otherUid];

  Future<PublicProfile?> profile(String otherUid) async {
    if (otherUid.isEmpty) return null;
    final cached = _profileCache[otherUid];
    if (cached != null) return cached;

    Future<PublicProfile?> tryRead(DocumentReference<Map<String, dynamic>> ref) async {
      try {
        DocumentSnapshot<Map<String, dynamic>> snap;
        try {
          snap = await ref.get(const GetOptions(source: Source.cache));
          if (!snap.exists) throw Exception('no cache');
        } catch (_) {
          snap = await ref.get().timeout(const Duration(seconds: 8));
        }
        if (snap.exists && snap.data() != null) return PublicProfile.fromMap(otherUid, snap.data()!);
      } catch (e) {
        debugPrint('profile($otherUid): $e');
      }
      return null;
    }

    PublicProfile? p = await tryRead(_db.collection('public_profiles').doc(otherUid));
    p ??= await tryRead(_db.collection('users').doc(otherUid)); // совместимость
    if (p != null) _profileCache[otherUid] = p;
    return p;
  }

  Future<List<PublicProfile>> search(String rawQuery) async {
    String q = rawQuery.trim().toLowerCase();
    if (q.startsWith('@')) q = q.substring(1);
    if (q.length < 2) return [];

    final Map<String, PublicProfile> found = {};
    Future<void> run(Query<Map<String, dynamic>> query) async {
      try {
        final snap = await query.limit(20).get().timeout(const Duration(seconds: 10));
        for (final d in snap.docs) {
          if (d.id == uid) continue;
          final p = PublicProfile.fromMap(d.id, d.data());
          found[d.id] = p;
          _profileCache[d.id] = p;
        }
      } catch (e) {
        debugPrint('search: $e');
      }
    }

    final profiles = _db.collection('public_profiles');
    await Future.wait([
      run(profiles.where('nickname', isGreaterThanOrEqualTo: q).where('nickname', isLessThanOrEqualTo: '$q')),
      run(profiles.where('nameLower', isGreaterThanOrEqualTo: q).where('nameLower', isLessThanOrEqualTo: '$q')),
    ]);

    if (found.isEmpty) {
      // Совместимость, пока public_profiles не заполнены для всех.
      await run(_db.collection('users').where('nickname', isGreaterThanOrEqualTo: q).where('nickname', isLessThanOrEqualTo: '$q'));
    }
    return found.values.toList();
  }

  Future<Map<String, dynamic>> _myInfo() async {
    if (_myInfoCache != null) return _myInfoCache!;
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db.collection('users').doc(uid).get(const GetOptions(source: Source.cache));
      } catch (_) {
        snap = await _db.collection('users').doc(uid).get().timeout(const Duration(seconds: 5));
      }
      final p = PublicProfile.fromMap(uid, snap.data() ?? {});
      _myInfoCache = {'name': p.name, 'photoUrl': p.photoUrl};
    } catch (_) {
      _myInfoCache = {'name': 'Пользователь', 'photoUrl': ''};
    }
    return _myInfoCache!;
  }

  void resetCaches() {
    _myInfoCache = null;
    _profileCache.clear();
  }

  // -------------------------------------------------------------------------
  // Отправка
  // -------------------------------------------------------------------------

  /// Возвращает ID созданного сообщения сразу (сообщение появится в UI мгновенно),
  /// а [delivery] завершается, когда стало понятно, дошло ли оно до сервера.
  ({String messageId, Future<ChatDeliveryState> delivery}) sendMessage({
    required String otherUid,
    String text = '',
    String? imageUrl,
    String collection = 'chats',
  }) {
    final String me = uid;
    final String chatId = chatIdFor(me, otherUid);
    final DocumentReference<Map<String, dynamic>> ref = _messages(collection, chatId).doc();
    final String trimmed = text.trim();

    final Map<String, dynamic> data = {
      'senderId': me,
      'receiverId': otherUid,
      'text': trimmed,
      'type': imageUrl != null ? 'image' : 'text',
      if (imageUrl != null) 'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
      'clientTs': Timestamp.now(),
      'v': 2, // новый формат: счётчики непрочитанных и пуши ведёт сервер
    };

    final Future<void> write = ref.set(data);
    _touchChat(collection: collection, chatId: chatId, otherUid: otherUid, preview: imageUrl != null && trimmed.isEmpty ? '📷 Фото' : trimmed);

    Future<ChatDeliveryState> deliver() async {
      try {
        await write.timeout(const Duration(seconds: 7));
        return ChatDeliveryState.sent;
      } on TimeoutException {
        // Соединение Firestore «залипло» (частая история с VPN/роумингом).
        // Дублируем доставку через обычный HTTPS — с тем же ID, без дублей.
        try {
          await FirebaseFunctions.instance
              .httpsCallable('sendChatMessage', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
              .call({
            'chatId': chatId,
            'collection': collection,
            'messageId': ref.id,
            'otherUid': otherUid,
            'text': trimmed,
            'imageUrl': imageUrl,
          });
          return ChatDeliveryState.sent;
        } catch (e) {
          debugPrint('sendChatMessage fallback: $e');
          // Сообщение останется в локальной очереди Firestore и уйдёт само,
          // как только связь восстановится.
          return ChatDeliveryState.sending;
        }
      } catch (e) {
        debugPrint('sendMessage error: $e');
        return ChatDeliveryState.failed;
      }
    }

    return (messageId: ref.id, delivery: deliver());
  }

  Future<void> _touchChat({
    required String collection,
    required String chatId,
    required String otherUid,
    required String preview,
  }) async {
    final me = uid;
    final info = await _myInfo();
    _db.collection(collection).doc(chatId).set({
      'users': [me, otherUid],
      'lastMessage': preview,
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId': me,
      'participant_info': {me: info},
    }, SetOptions(merge: true)).catchError((e) => debugPrint('touchChat: $e'));
  }

  Future<String?> uploadImage({required String otherUid, required Uint8List bytes}) async {
    final chatId = chatIdFor(uid, otherUid);
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$uid.jpg';
    final ref = FirebaseStorage.instance.ref().child('chats_media').child(chatId).child(fileName);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 60));
    return ref.getDownloadURL();
  }

  // -------------------------------------------------------------------------
  // Прочтение, редактирование, удаление
  // -------------------------------------------------------------------------

  void markRead(String chatId, {String collection = 'chats'}) {
    final me = uid;
    if (me.isEmpty) return;
    _db.collection(collection).doc(chatId).set({
      'unread_$me': 0,
      'lastRead_$me': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((e) => debugPrint('markRead: $e'));
  }

  Future<void> editMessage(String chatId, String messageId, String newText, {String collection = 'chats'}) async {
    _messages(collection, chatId)
        .doc(messageId)
        .update({'text': newText.trim(), 'edited': true})
        .catchError((e) => debugPrint('editMessage: $e'));
  }

  Future<void> deleteMessage(String chatId, String messageId, {String? imageUrl, String collection = 'chats'}) async {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('deleteMessage image: $e');
      }
    }
    _messages(collection, chatId).doc(messageId).delete().catchError((e) => debugPrint('deleteMessage: $e'));
  }

  // -------------------------------------------------------------------------
  // Резервное получение через HTTPS (когда поток Firestore «молчит»)
  // -------------------------------------------------------------------------

  Future<List<ChatMessage>> fetchViaServer(String chatId, {String collection = 'chats', int limit = 60}) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('fetchChatMessages', options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
        .call({'chatId': chatId, 'collection': collection, 'limit': limit});
    final dynamic raw = result.data is Map ? (result.data as Map)['messages'] : null;
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) => ChatMessage.fromServer(m)).toList();
  }
}
