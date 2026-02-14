import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Coach {
  final String id;
  final String name;
  final String bio;
  final String specialization;
  final String price;
  final String photoUrl;
  final double rating;
  final int ratingCount; // НОВОЕ ПОЛЕ

  Coach({
    required this.id,
    required this.name,
    required this.bio,
    required this.specialization,
    required this.price,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount, // НОВОЕ ПОЛЕ
  });

  factory Coach.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    
    return Coach(
      id: doc.id,
      name: data['name'] ?? 'Имя не указано',
      bio: data['bio'] ?? '',
      specialization: data['specialization'] ?? '',
      price: data['price']?.toString() ?? 'Цена не указана',
      photoUrl: data['photoUrl'] ?? '',
      rating: (data['rating'] ?? 5.0).toDouble(),
      ratingCount: (data['ratingCount'] ?? 0).toInt(), // БЕЗОПАСНЫЙ ПАРСИНГ
    );
  }
}

class CoachService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. Получить список всех тренеров (С ОБРАБОТКОЙ ОШИБОК)
  Stream<List<Coach>> getCoaches() {
    return _db.collection('coaches').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        try {
          return Coach.fromFirestore(doc);
        } catch (e) {
          // Если документ сломан, выводим ошибку в консоль, но не ломаем весь список
          print('🔥 Ошибка парсинга тренера ${doc.id}: $e');
          return null;
        }
      })
      // Отфильтровываем сломанные документы (null), чтобы UI получил только рабочих тренеров
      .whereType<Coach>()
      .toList();
    });
  }

  // 2. Сгенерировать уникальный ID чата для двух пользователей
  String getChatId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort(); // Сортируем по алфавиту, чтобы ID всегда был одинаковым для этой пары
    return ids.join('_');
  }

  // 3. Отправить сообщение
  Future<void> sendMessage(String otherUserId, String text) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || text.trim().isEmpty) return;

    final String chatId = getChatId(currentUser.uid, otherUserId);

    // Добавляем сообщение в подколлекцию
    await _db.collection('chats').doc(chatId).collection('messages').add({
      'senderId': currentUser.uid,
      'text': text.trim(),
      'timestamp': Timestamp.now(),
    });
    
    // Обновляем метаданные самого чата (для списка диалогов в будущем)
    await _db.collection('chats').doc(chatId).set({
      'users': [currentUser.uid, otherUserId],
      'lastMessage': text.trim(),
      'lastUpdated': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  // 4. Получить поток сообщений
  Stream<QuerySnapshot> getChatMessages(String otherUserId) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return const Stream.empty();

    final String chatId = getChatId(currentUser.uid, otherUserId);

    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}