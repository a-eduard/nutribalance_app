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

  // ==========================================
  //                1. ТРЕНИРОВКИ (WORKOUTS)
  // ==========================================

  Future<void> saveUserWorkout(String name, List<String> exerciseNames, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').add({
      'name': name.trim(),
      'exercises': exerciseNames,
      'targets': targets,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getUserWorkouts() {
    return _db.collection('users').doc(_uid).collection('workouts')
        .orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> updateWorkout(String docId, String newName, List<String> newExercises, Map<String, String> targets) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).update({
      'name': newName.trim(),
      'exercises': newExercises,
      'targets': targets,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteWorkout(String docId) async {
    await _db.collection('users').doc(_uid).collection('workouts').doc(docId).delete();
  }

  // ==========================================
  //           2. ИСТОРИЯ И ПРОГРЕСС
  // ==========================================

  /// Сохранение тренировки с детальной историей весов
  Future<void> saveWorkoutSession(
    String workoutName, 
    int tonnage, 
    int duration, 
    List<Map<String, dynamic>> exercisesData
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User is null");

    await _db.collection('users').doc(user.uid).collection('history').add({
      'workoutName': workoutName.trim(), 
      'tonnage': tonnage,
      'duration': duration,
      'exercises': exercisesData,
      'completedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Умный поиск последней тренировки (Auto-fill)
  Future<Map<String, dynamic>?> getLastWorkoutData(String targetName) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      // 1. Берем последние 10 ЛЮБЫХ тренировок
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('history')
          .orderBy('completedAt', descending: true)
          .limit(10)
          .get();

      // 2. Ищем совпадение имени вручную (игнорируя регистр и пробелы)
      final cleanTarget = targetName.trim().toLowerCase();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final dbName = (data['workoutName'] ?? "").toString().trim().toLowerCase();

        if (dbName == cleanTarget) {
          return data;
        }
      }
    } catch (e) {
      print("Error loading history: $e");
    }
    return null;
  }

  // ==========================================
  //           3. БИБЛИОТЕКА УПРАЖНЕНИЙ
  // ==========================================

  Stream<QuerySnapshot> getCustomExercises() {
    return _db.collection('users').doc(_uid).collection('custom_exercises')
        .orderBy('title').snapshots();
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