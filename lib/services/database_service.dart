import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  // ======================================================
  // 1. ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ И ТРЕНЕР
  // ======================================================

  Future<void> updateUserData(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
    }
  }

  Stream<DocumentSnapshot> getUserData() {
    final user = _auth.currentUser;
    if (user != null) {
      return _db.collection('users').doc(user.uid).snapshots();
    }
    return const Stream.empty();
  }

  // НОВЫЙ МЕТОД: Привязка тренера к пользователю
  Future<void> connectWithCoach(String coachId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({
      'currentCoachId': coachId,
    }, SetOptions(merge: true));
  }

  // ======================================================
  // 2. ПРОГРАММЫ ТРЕНИРОВОК (Workouts)
  // ======================================================

  Future<void> saveUserWorkout(String name, List<String> exercises, Map<String, String> targets) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('workouts').add({
        'name': name,
        'exercises': exercises,
        'targets': targets, 
        'createdAt': Timestamp.now(),
      });
    }
  }

  Stream<QuerySnapshot> getUserWorkouts() {
    final user = _auth.currentUser;
    if (user != null) {
      return _db
          .collection('users')
          .doc(user.uid)
          .collection('workouts')
          .orderBy('createdAt', descending: true)
          .snapshots();
    }
    return const Stream.empty();
  }

  Future<void> updateWorkout(String docId, String name, List<String> exercises, Map<String, String> targets) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('workouts').doc(docId).update({
        'name': name,
        'exercises': exercises,
        'targets': targets,
      });
    }
  }

  Future<void> deleteWorkout(String docId) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('workouts').doc(docId).delete();
    }
  }

  // ======================================================
  // 3. ИСТОРИЯ ТРЕНИРОВОК (History)
  // ======================================================

  Future<void> saveWorkoutSession(
      String workoutName, 
      int tonnage, 
      int duration, 
      List<Map<String, dynamic>> exercises, 
      {String? workoutId}) async {
    
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').add({
        'workoutName': workoutName,
        'workoutId': workoutId,
        'tonnage': tonnage,
        'duration': duration,
        'date': Timestamp.now(),
        'exercises': exercises,
      });
    }
  }

  Future<Map<String, dynamic>?> getLastHistoryForWorkout(String workoutId, String workoutName) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final querySnapshot = await _db.collection('users').doc(user.uid).collection('history').get();
      if (querySnapshot.docs.isEmpty) return null;

      List<Map<String, dynamic>> allHistory = querySnapshot.docs.map((d) => d.data()).toList();

      var filtered = allHistory.where((item) {
        final idMatch = item['workoutId'] == workoutId;
        final nameMatch = item['workoutName'] == workoutName;
        return (workoutId.isNotEmpty && idMatch) || nameMatch;
      }).toList();

      if (filtered.isEmpty) return null;

      filtered.sort((a, b) {
        Timestamp tA = a['date'];
        Timestamp tB = b['date'];
        return tB.compareTo(tA);
      });

      return filtered.first;
    } catch (e) {
      print("Error loading history: $e");
      return null;
    }
  }

  Stream<QuerySnapshot> getUserHistory() {
    final user = _auth.currentUser;
    if (user != null) {
      return _db.collection('users').doc(user.uid).collection('history').orderBy('date', descending: true).snapshots();
    }
    return const Stream.empty();
  }

  Future<void> deleteHistoryItem(String docId) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').doc(docId).delete();
    }
  }

  Future<void> updateHistoryItem(String docId, Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').doc(docId).update(data);
    }
  }

  // ======================================================
  // 4. AI ЧАТ (Chat & Nutrition)
  // ======================================================

  Stream<QuerySnapshot> getChatMessages() {
    final user = _auth.currentUser;
    if (user != null) {
      return _db.collection('users').doc(user.uid).collection('ai_chat').orderBy('timestamp', descending: true).snapshots();
    }
    return const Stream.empty();
  }

  Future<void> saveChatMessage(String text, String sender) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('ai_chat').add({
        'text': text, 'sender': sender, 'timestamp': Timestamp.now(),
      });
    }
  }

  Future<void> clearChatHistory() async {
    final user = _auth.currentUser;
    if (user != null) {
      final collection = _db.collection('users').doc(user.uid).collection('ai_chat');
      final snapshots = await collection.get();
      for (var doc in snapshots.docs) {
        await doc.reference.delete();
      }
    }
  }

  Future<void> saveNutritionPlan(Map<String, dynamic> plan) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('nutrition_plans').add({
        'plan': plan,
        'createdAt': Timestamp.now(),
      });
      await updateUserData({'currentNutritionPlan': plan});
    }
  }

  // ======================================================
  // 5. БИБЛИОТЕКА УПРАЖНЕНИЙ (Custom Exercises)
  // ======================================================

  Future<void> addCustomExercise(String title, String muscleGroup) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('custom_exercises').add({
        'title': title,
        'muscleGroup': muscleGroup,
        'createdAt': Timestamp.now(),
      });
    }
  }

  Stream<QuerySnapshot> getCustomExercises() {
    final user = _auth.currentUser;
    if (user != null) {
      return _db.collection('users').doc(user.uid).collection('custom_exercises').orderBy('createdAt').snapshots();
    }
    return const Stream.empty();
  }
  
  Future<void> deleteExercise(String docId) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('custom_exercises').doc(docId).delete();
    }
  }
}