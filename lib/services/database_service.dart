import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Хелпер для получения ID текущего юзера
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("Пользователь не авторизован!");
    }
    return user.uid;
  }

  // =========================================================
  // 1. ИСТОРИЯ ТРЕНИРОВОК (History)
  // =========================================================

  // Получить всю историю (возвращаем список Map с ID документов)
  Future<List<Map<String, dynamic>>> getUserHistory() async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(_uid)
          .collection('history')
          .orderBy('completedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // Важно: добавляем ID документа для удаления/правки
        return data;
      }).toList();
    } catch (e) {
      print("Error fetching history: $e");
      return [];
    }
  }

  // Сохранить НОВУЮ выполненную тренировку
  Future<void> saveWorkoutSession(String workoutName, int tonnage, int duration, List<Map<String, dynamic>> exercisesData) async {
    await _db.collection('users').doc(_uid).collection('history').add({
      'workoutName': workoutName.trim(),
      'tonnage': tonnage,
      'duration': duration,
      'exercises': exercisesData,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  // Обновить СУЩЕСТВУЮЩУЮ запись в истории (Редактирование)
  Future<void> updateHistoryItem(String docId, Map<String, dynamic> data) async {
    final dataToUpdate = Map<String, dynamic>.from(data);
    dataToUpdate['updatedAt'] = FieldValue.serverTimestamp();
    
    await _db
        .collection('users')
        .doc(_uid)
        .collection('history')
        .doc(docId)
        .update(dataToUpdate);
  }

  // Удалить запись из истории (Корзина)
  Future<void> deleteHistoryItem(String docId) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('history')
        .doc(docId)
        .delete();
  }

  // Поиск последней тренировки (для автозаполнения весов)
  Future<Map<String, dynamic>?> getLastWorkoutData(String targetName) async {
    try {
      final snapshot = await _db.collection('users').doc(_uid).collection('history')
          .orderBy('completedAt', descending: true).limit(10).get();

      final cleanTarget = targetName.trim().toLowerCase();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final dbName = (data['workoutName'] ?? "").toString().trim().toLowerCase();
        if (dbName == cleanTarget) return data;
      }
    } catch (e) { print("Error loading history: $e"); }
    return null;
  }

  // =========================================================
  // 2. ПРОФИЛЬ И ПИТАНИЕ
  // =========================================================

  // Обновить данные атлета
  Future<void> updateUserData({
    required String name,
    required String gender,
    required double weight,
    required double height,
    required int age,
    required double bodyFat,
    required String experience,
  }) async {
    await _db.collection('users').doc(_uid).update({
      'name': name,
      'gender': gender,
      'weight': weight,
      'height': height,
      'age': age,
      'bodyFat': bodyFat,
      'experience': experience,
    });
  }

  // Сохранить план питания от ИИ
  Future<void> saveNutritionPlan(Map<String, dynamic> nutritionData) async {
    await _db.collection('users').doc(_uid).set({
      'nutrition_plan': nutritionData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =========================================================
  // 3. ШАБЛОНЫ ТРЕНИРОВОК (My Workouts)
  // =========================================================
  
  // Получить список шаблонов (Stream)
  Stream<QuerySnapshot> getUserWorkouts() {
    return _db.collection('users').doc(_uid).collection('workouts')
        .orderBy('createdAt', descending: true).snapshots();
  }

  // Создать новый шаблон
  Future<void> saveUserWorkout(String name, List<String> exerciseNames, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').add({
      'name': name.trim(), 
      'exercises': exerciseNames, 
      'targets': targets, 
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Удалить шаблон
  Future<void> deleteWorkout(String docId) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).delete();
  }

  // Обновить шаблон
  Future<void> updateWorkout(String docId, String newName, List<String> newExercises, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).update({
      'name': newName.trim(), 
      'exercises': newExercises, 
      'targets': targets, 
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =========================================================
  // 4. БИБЛИОТЕКА УПРАЖНЕНИЙ (Custom Exercises)
  // =========================================================

  // Получить список упражнений
  Stream<QuerySnapshot> getCustomExercises() {
    return _db.collection('users').doc(_uid).collection('custom_exercises')
        .orderBy('title').snapshots();
  }

  // Добавить свое упражнение
  Future<void> addCustomExercise(String title, String muscleGroup) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').add({
      'title': title, 
      'muscleGroup': muscleGroup, 
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Удалить упражнение
  Future<void> deleteExercise(String docId) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').doc(docId).delete();
  }
  
  // Обновить упражнение
  Future<void> updateExercise(String docId, String title, String muscleGroup) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').doc(docId).update({
      'title': title,
      'muscleGroup': muscleGroup
    });
  }

  // =========================================================
  // 5. AI ЧАТ (Сохранение переписки)
  // =========================================================

  // Сохранить сообщение
  Future<void> saveChatMessage(String message, String role) async {
    await _db.collection('users').doc(_uid).collection('ai_chat').add({
      'text': message,
      'role': role, // 'user' или 'ai'
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Получить переписку (Stream)
  Stream<QuerySnapshot> getChatMessages() {
    return _db
        .collection('users')
        .doc(_uid)
        .collection('ai_chat')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  // Очистить историю чата
  Future<void> clearChatHistory() async {
    final batch = _db.batch();
    final snapshot = await _db.collection('users').doc(_uid).collection('ai_chat').get();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}