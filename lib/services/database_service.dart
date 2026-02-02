import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Хелпер для получения UID. Если юзера нет — кидаем ошибку.
  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception("Пользователь не авторизован!");
    }
    return user.uid;
  }

  // ==========================================
  //                ТРЕНИРОВКИ
  // ==========================================

 /// 1. СОЗДАТЬ: Сохранить новую программу
  // Добавили аргумент targets
  Future<void> saveUserWorkout(String name, List<String> exerciseNames, Map<String, String> targets) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .add({
        'name': name,
        'exercises': exerciseNames,
        'targets': targets, // <--- СОХРАНЯЕМ В БАЗУ
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error saving workout: $e");
      rethrow;
    }
  }

  // ... (getUserWorkouts оставляем как есть, он просто тянет снапшот) ...

  /// 2. ЧИТАТЬ: Получить список программ (Stream)
  Stream<QuerySnapshot> getUserWorkouts() {
    try {
      return _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .orderBy('createdAt', descending: true)
          .snapshots();
    } catch (e) {
      print("Error getting workouts: $e");
      return const Stream.empty();
    }
  }

/// 3. ОБНОВИТЬ: Изменить программу
  // Добавили аргумент targets
  Future<void> updateWorkout(String docId, String newName, List<String> newExercises, Map<String, String> targets) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .doc(docId)
          .update({
        'name': newName,
        'exercises': newExercises,
        'targets': targets, // <--- ОБНОВЛЯЕМ В БАЗЕ
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error updating workout: $e");
      rethrow;
    }
  }

// ... остальные методы без изменений
  /// 4. УДАЛИТЬ: Удалить программу
  Future<void> deleteWorkout(String docId) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .doc(docId)
          .delete();
    } catch (e) {
      print("Error deleting workout: $e");
      rethrow;
    }
  }

  /// 5. ИСТОРИЯ: Сохранить выполненную тренировку
  Future<void> saveWorkoutSession(String workoutName, int tonnage, int duration) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('history')
          .add({
        'workoutName': workoutName,
        'tonnage': tonnage,
        'duration': duration, // в минутах
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error saving session: $e");
      rethrow;
    }
  }

  // ==========================================
  //           БИБЛИОТЕКА УПРАЖНЕНИЙ
  // ==========================================

  /// 1. Получить поток упражнений
  Stream<QuerySnapshot> getCustomExercises() {
    try {
      return _db
          .collection('users')
          .doc(_uid)
          .collection('custom_exercises')
          .orderBy('title') // Сортируем по алфавиту
          .snapshots();
    } catch (e) {
      print("Error getting exercises: $e");
      return const Stream.empty();
    }
  }

  /// 2. Добавить упражнение
  Future<void> addCustomExercise(String title, String muscleGroup) async {
    await _db.collection('users').doc(_uid).collection('custom_exercises').add({
      'title': title,
      'muscleGroup': muscleGroup,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// 3. Обновить упражнение
  Future<void> updateExercise(String docId, String newName, String newMuscleGroup) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('custom_exercises')
        .doc(docId)
        .update({
      'title': newName,
      'muscleGroup': newMuscleGroup,
    });
  }

  /// 4. Удалить упражнение
  Future<void> deleteExercise(String docId) async {
    await _db
        .collection('users')
        .doc(_uid)
        .collection('custom_exercises')
        .doc(docId)
        .delete();
  }
}