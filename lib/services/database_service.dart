import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("Пользователь не авторизован!");
    }
    return user.uid;
  }
  // ... (внутри класса DatabaseService)

  // Сохранить план питания (merge: true, чтобы не затереть имя и другие поля)
  Future<void> saveNutritionPlan(Map<String, dynamic> nutritionData) async {
    await _db.collection('users').doc(_uid).set({
      'nutrition_plan': nutritionData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==========================================
  //                1. ТЕСТ СВЯЗИ
  // ==========================================
  Future<String> testConnection() async {
    final user = _auth.currentUser;
    if (user == null) return "ОШИБКА: Нет юзера";
    try {
      await _db.collection('users').doc(user.uid).collection('test_connection').add({
        'timestamp': FieldValue.serverTimestamp(),
        'msg': 'Test from Android'
      });
      return "УСПЕХ! Запись в базу прошла.";
    } catch (e) {
      return "ОШИБКА: $e";
    }
  }

  // ==========================================
  //           2. ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ (НОВОЕ)
  // ==========================================

  // Получить данные профиля (Stream)
  Stream<DocumentSnapshot> getUserProfile() {
    return _db.collection('users').doc(_uid).snapshots();
  }

  // Обновить данные профиля
  // Обновить данные профиля (С НОВЫМИ ПОЛЯМИ)
  Future<void> updateUserData({
    required String name,
    required String gender,
    required double weight,
    required double height,
    required int age,
    required double bodyFat,   // <-- Новое
    required String experience, // <-- Новое (например, "2 года")
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

  // ==========================================
  //           3. ИСТОРИЯ И СТАТИСТИКА
  // ==========================================

  // Получить ПОЛНУЮ историю (для графиков)
  Future<List<Map<String, dynamic>>> getUserHistory() async {
    try {
      final snapshot = await _db
          .collection('users')
          .doc(_uid)
          .collection('history')
          .orderBy('completedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print("Error fetching history: $e");
      return [];
    }
  }

  // Сохранить тренировку
  Future<void> saveWorkoutSession(String workoutName, int tonnage, int duration, List<Map<String, dynamic>> exercisesData) async {
    await _db.collection('users').doc(_uid).collection('history').add({
      'workoutName': workoutName.trim(),
      'tonnage': tonnage,
      'duration': duration,
      'exercises': exercisesData,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  // Поиск последней тренировки (Auto-fill)
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

  // ==========================================
  //           4. ТРЕНИРОВКИ (CRUD)
  // ==========================================
  
  Future<void> saveUserWorkout(String name, List<String> exerciseNames, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').add({
      'name': name.trim(), 'exercises': exerciseNames, 'targets': targets, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getUserWorkouts() {
    return _db.collection('users').doc(_uid).collection('workouts').orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> updateWorkout(String docId, String newName, List<String> newExercises, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).update({
      'name': newName.trim(), 'exercises': newExercises, 'targets': targets, 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWorkout(String docId) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).delete();
  }

  // ==========================================
  //           5. БИБЛИОТЕКА
  // ==========================================

  Stream<QuerySnapshot> getCustomExercises() {
    return _db.collection('users').doc(_uid).collection('custom_exercises').orderBy('title').snapshots();
  }

  Future<void> addCustomExercise(String title, String muscleGroup) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').add({
      'title': title, 'muscleGroup': muscleGroup, 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateExercise(String docId, String newName, String newMuscleGroup) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').doc(docId).update({
      'title': newName, 'muscleGroup': newMuscleGroup,
    });
  }

  Future<void> deleteExercise(String docId) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').doc(docId).delete();
  }
}