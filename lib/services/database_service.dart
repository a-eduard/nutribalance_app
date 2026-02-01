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

  /// 1. СОЗДАТЬ: Сохранить новую программу
  Future<void> saveUserWorkout(String name, List<String> exerciseNames) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .add({
        'name': name,
        'exercises': exerciseNames,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error saving workout: $e");
      rethrow;
    }
  }

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

  /// 3. ОБНОВИТЬ: Изменить программу (название или список упражнений)
  Future<void> updateWorkout(String docId, String newName, List<String> newExercises) async {
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('workouts')
          .doc(docId)
          .update({
        'name': newName,
        'exercises': newExercises,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error updating workout: $e");
      rethrow;
    }
  }

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
}