import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../screens/profile_settings_screen.dart'; 

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  String _getTodayDocId() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> updateUserData(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
    }
  }

  Future<void> updateDailyNutritionManual(int cals, int prot, int fat, int carbs) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    final String docId = _getTodayDocId();

    await _db.collection('users').doc(user.uid).collection('meals').doc(docId).set({
      'name': 'Ручной ввод',
      'calories': cals,
      'protein': prot,
      'fat': fat,
      'carbs': carbs,
      'date': Timestamp.now(), 
    });
    
    await _updateWeeklyNutritionCache(user.uid); 
  }

  Stream<DocumentSnapshot> getUserData() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).snapshots();
    return const Stream.empty();
  }
  
  Future<void> sendRequestToCoach(String coachId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    await _db.collection('users').doc(uid).set({'currentCoachId': coachId, 'coachRequestStatus': 'pending'}, SetOptions(merge: true));
    await _db.collection('users').doc(coachId).collection('athlete_requests').doc(uid).set({'athleteId': uid, 'status': 'pending', 'timestamp': FieldValue.serverTimestamp()});
  }

  Future<void> connectWithCoach(String coachId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set({'currentCoachId': coachId, 'coachRequestStatus': 'accepted'}, SetOptions(merge: true));
  }

  Future<void> acceptCoachRequest(String athleteId) async {
    final coachId = _auth.currentUser?.uid;
    if (coachId == null) return;
    await _db.collection('users').doc(athleteId).update({'coachRequestStatus': 'accepted'});
    await _db.collection('users').doc(coachId).collection('athlete_requests').doc(athleteId).update({'status': 'accepted'});
  }

  Future<void> rejectCoachRequest(String athleteId) async {
    final coachId = _auth.currentUser?.uid;
    if (coachId == null) return;
    await _db.collection('users').doc(athleteId).update({'currentCoachId': FieldValue.delete(), 'coachRequestStatus': FieldValue.delete()});
    await _db.collection('users').doc(coachId).collection('athlete_requests').doc(athleteId).delete();
  }

  Future<void> rateCoach(String coachId, double newRating) async {
    try {
      final coachRef = _db.collection('coaches').doc(coachId);
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(coachRef);
        if (!snapshot.exists) return;
        final data = snapshot.data() as Map<String, dynamic>;
        double currentRating = (data['rating'] ?? 5.0).toDouble();
        int totalVotes = (data['totalVotes'] ?? 1).toInt(); 
        double updatedRating = ((currentRating * totalVotes) + newRating) / (totalVotes + 1);
        transaction.update(coachRef, {'rating': double.parse(updatedRating.toStringAsFixed(1)), 'totalVotes': totalVotes + 1});
      });
    } catch (e) {
      debugPrint("Error rating coach: $e");
    }
  }

  Future<void> rateAthleteHidden(String athleteId, int score, String comment) async {
    final coachId = _auth.currentUser?.uid;
    if (coachId == null) return;
    await _db.collection('users').doc(athleteId).collection('coach_reviews_hidden').doc(coachId).set({'coachId': coachId, 'score': score, 'comment': comment, 'createdAt': FieldValue.serverTimestamp()});
  }

  Future<void> saveUserWorkout(String name, List<String> exercises, Map<String, String> targets) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('workouts').add({'name': name, 'exercises': exercises, 'targets': targets, 'source': 'custom', 'createdAt': Timestamp.now()});
    }
  }

  Stream<QuerySnapshot> getUserWorkouts() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).collection('workouts').snapshots();
    return const Stream.empty();
  }

  Future<void> updateWorkout(String docId, String name, List<String> exercises, Map<String, String> targets) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('workouts').doc(docId).update({'name': name, 'exercises': exercises, 'targets': targets});
    }
  }

  Future<void> deleteWorkout(String docId) async {
    final user = _auth.currentUser;
    if (user != null) await _db.collection('users').doc(user.uid).collection('workouts').doc(docId).delete();
  }

  Future<void> saveAIWorkoutProgram(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final oldAiWorkouts = await _db.collection('users').doc(user.uid).collection('workouts').where('source', isEqualTo: 'ai').get();
    for (var doc in oldAiWorkouts.docs) {
      await doc.reference.delete();
    }

    String baseTitle = data['program_title'] ?? data['program_name'] ?? 'ИИ Программа';
    List days = data['days'] ?? [];

    for (var day in days) {
      String dayName = day['day_name'] ?? 'Тренировка';
      List exercisesData = day['exercises'] ?? [];
      List<Map<String, dynamic>> exercisesList = []; 
      for (var exJson in exercisesData) {
        String exName = exJson['name']?.toString().trim() ?? 'Упражнение';
        String parsedNotes = "";
        final sets = exJson['sets']?.toString().trim() ?? '';
        final reps = exJson['reps']?.toString().trim() ?? '';
        final rest = exJson['rest_seconds']?.toString().trim() ?? exJson['rest']?.toString().trim() ?? '';
        final coachNote = exJson['notes']?.toString().trim() ?? exJson['coach_note']?.toString().trim() ?? '';
        if (sets.isNotEmpty || reps.isNotEmpty) parsedNotes += "🎯 Подходы: $sets, Повторения: $reps. ";
        if (rest.isNotEmpty) parsedNotes += "⏱ Отдых: ${rest}с. ";
        if (coachNote.isNotEmpty) parsedNotes += "\n💡 $coachNote";
        exercisesList.add({'name': exName, 'notes': parsedNotes.trim()});
      }
      await _db.collection('users').doc(user.uid).collection('workouts').add({'name': "$baseTitle: $dayName", 'exercises': exercisesList, 'source': 'ai', 'createdAt': Timestamp.now()});
    }
  }

  Future<void> saveAIDietPlan(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('diets').add({'title': data['title'] ?? 'План питания', 'details': data['details'] ?? '', 'items': data['data'] ?? [], 'createdAt': Timestamp.now()});
    }
  }

  Future<void> _updateWeeklyWorkoutCache(String uid) async {
    final weekAgoTs = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    final snap = await _db.collection('users').doc(uid).collection('history').where('date', isGreaterThanOrEqualTo: weekAgoTs).get();
    double totalTonnage = 0;
    for (var doc in snap.docs) {
      totalTonnage += (doc.data()['tonnage'] as num?)?.toDouble() ?? 0.0;
    }
    await _db.collection('users').doc(uid).set({'weeklyTonnage': totalTonnage}, SetOptions(merge: true));
  }

  Future<void> saveWorkoutSession(String workoutName, int tonnage, int duration, List<Map<String, dynamic>> exercises, {String? workoutId}) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').add({'workoutName': workoutName, 'workoutId': workoutId, 'tonnage': tonnage, 'duration': duration, 'date': Timestamp.now(), 'exercises': exercises});
      await _updateWeeklyWorkoutCache(user.uid); 
    }
  }

  Future<Map<String, dynamic>?> getLastHistoryForWorkout(String workoutId, String workoutName) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      if (workoutId.isNotEmpty) {
        final querySnapshot = await _db.collection('users').doc(user.uid).collection('history').where('workoutId', isEqualTo: workoutId).get();
        if (querySnapshot.docs.isNotEmpty) {
          var docs = querySnapshot.docs.map((d) => d.data()).toList();
          docs.sort((a, b) {
            Timestamp tA = a['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
            Timestamp tB = b['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
            return tB.compareTo(tA);
          });
          return docs.first; 
        }
      }

      final nameSnapshot = await _db.collection('users').doc(user.uid).collection('history').where('workoutName', isEqualTo: workoutName).get();
      if (nameSnapshot.docs.isNotEmpty) {
        var docs = nameSnapshot.docs.map((d) => d.data()).toList();
        docs.sort((a, b) {
          Timestamp tA = a['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
          Timestamp tB = b['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
          return tB.compareTo(tA);
        });
        return docs.first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Stream<QuerySnapshot> getUserHistory() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).collection('history').orderBy('date', descending: true).snapshots();
    return const Stream.empty();
  }

  Future<void> deleteHistoryItem(String docId) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').doc(docId).delete();
      await _updateWeeklyWorkoutCache(user.uid); 
    }
  }

  Future<void> updateHistoryItem(String docId, Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('history').doc(docId).update(data);
      await _updateWeeklyWorkoutCache(user.uid); 
    }
  }

  Future<void> addWeightEntry(double weight) async {
    final user = _auth.currentUser;
    if (user != null) await _db.collection('users').doc(user.uid).collection('weight_history').add({'weight': weight, 'date': FieldValue.serverTimestamp()});
  }

  Stream<QuerySnapshot> getWeightHistory() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).collection('weight_history').orderBy('date', descending: false).snapshots();
    return const Stream.empty();
  }

  Future<String?> uploadChatImage(File imageFile, String chatId) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'chats/$chatId/${timestamp}_${user.uid}.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) { return null; }
  }

  Stream<QuerySnapshot> getBotChatMessages(String botType) {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).collection('ai_chats_$botType').orderBy('timestamp', descending: true).snapshots();
    return const Stream.empty();
  }

  Future<void> saveBotChatMessage(String botType, String text, String role, {String? imageUrl}) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db.collection('users').doc(user.uid).collection('ai_chats_$botType').add({'text': text, 'role': role, 'imageUrl': imageUrl, 'timestamp': Timestamp.now()});
    }
  }

  Future<void> updateBotChatMessage(String botType, String docId, String newText) async {
    final user = _auth.currentUser;
    if (user != null) await _db.collection('users').doc(user.uid).collection('ai_chats_$botType').doc(docId).update({'text': newText, 'isEdited': true});
  }

  Future<void> clearBotChatHistory(String botType) async {
    final user = _auth.currentUser;
    if (user != null) {
      final collection = _db.collection('users').doc(user.uid).collection('ai_chats_$botType');
      final snapshots = await collection.get();
      for (var doc in snapshots.docs) await doc.reference.delete();
    }
  }

  Future<List<Map<String, String>>> getChatHistoryForAI(String botType) async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final snapshots = await _db.collection('users').doc(user.uid).collection('ai_chats_$botType').orderBy('timestamp', descending: true).limit(10).get();
    return snapshots.docs.reversed.map((doc) {
      final data = doc.data();
      return {"role": data['role'] == 'ai' ? 'assistant' : 'user', "text": data['text'].toString()};
    }).toList();
  }

  Future<void> addCustomExercise(String title, String muscleGroup) async {
    final user = _auth.currentUser;
    if (user != null) await _db.collection('users').doc(user.uid).collection('custom_exercises').add({'title': title, 'muscleGroup': muscleGroup, 'createdAt': Timestamp.now()});
  }

  Stream<QuerySnapshot> getCustomExercises() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).collection('custom_exercises').orderBy('createdAt').snapshots();
    return const Stream.empty();
  }
  
  Future<void> deleteExercise(String docId) async {
    final user = _auth.currentUser;
    if (user != null) await _db.collection('users').doc(user.uid).collection('custom_exercises').doc(docId).delete();
  }
  
  Future<void> saveNutritionGoal(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await _db.collection('users').doc(user.uid).collection('nutrition_goal').doc('current').set({
      'calories': data['calories'] ?? 0, 'protein': data['protein'] ?? 0, 'fat': data['fat'] ?? 0, 'carbs': data['carbs'] ?? 0, 'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));

    Map<String, dynamic> profileUpdates = {};
    if (data['bmr'] != null) profileUpdates['bmr'] = data['bmr'];
    if (data['maintenanceCalories'] != null) profileUpdates['maintenanceCalories'] = data['maintenanceCalories'];
    if (profileUpdates.isNotEmpty) await _db.collection('users').doc(user.uid).set(profileUpdates, SetOptions(merge: true));
  }

  Future<void> _updateWeeklyNutritionCache(String uid) async {
    final weekAgoTs = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    final snap = await _db.collection('users').doc(uid).collection('meals').where('date', isGreaterThanOrEqualTo: weekAgoTs).get();
    int totalCals = 0;
    for (var doc in snap.docs) {
      totalCals += (doc.data()['calories'] as num?)?.toInt() ?? 0;
    }
    int avgCals = snap.docs.isEmpty ? 0 : totalCals ~/ 7;
    await _db.collection('users').doc(uid).set({'weeklyAvgCals': avgCals}, SetOptions(merge: true));
  }

  Future<void> logMeal(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String docId = _getTodayDocId();

    await _db.collection('users').doc(user.uid).collection('meals').doc(docId).set({
      'name': data['meal_name'] ?? 'Обновление рациона',
      'calories': (data['calories'] as num?)?.toInt() ?? 0,
      'protein': (data['protein'] as num?)?.toInt() ?? 0,
      'fat': (data['fat'] as num?)?.toInt() ?? 0,
      'carbs': (data['carbs'] as num?)?.toInt() ?? 0,
      'date': Timestamp.now(), 
    });
    
    await _updateWeeklyNutritionCache(user.uid); 
  }

  // БЛОК 3: Метод для сохранения в отложенный драфт
  Future<void> saveMealDraft(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).collection('meal_drafts').add({
      'meal_name': data['meal_name'] ?? 'Блюдо',
      'calories': (data['calories'] as num?)?.toInt() ?? 0,
      'protein': (data['protein'] as num?)?.toInt() ?? 0,
      'fat': (data['fat'] as num?)?.toInt() ?? 0,
      'carbs': (data['carbs'] as num?)?.toInt() ?? 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> getTodayMeals() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    final logicalNow = DateTime.now().subtract(const Duration(hours: 3));
    final startOfDay = DateTime(logicalNow.year, logicalNow.month, logicalNow.day); 
    final queryStartTime = startOfDay.add(const Duration(hours: 3));
    final startTimestamp = Timestamp.fromDate(queryStartTime);

    return _db.collection('users').doc(user.uid).collection('meals').where('date', isGreaterThanOrEqualTo: startTimestamp).snapshots();
  }

  Stream<DocumentSnapshot> getNutritionGoal() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db.collection('users').doc(user.uid).collection('nutrition_goal').doc('current').snapshots();
  }

  Future<void> saveCustomFood(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).collection('custom_foods').add({
      'name': data['name'] ?? 'Свой продукт',
      'calories': data['calories'] ?? 0,
      'protein': data['protein'] ?? 0,
      'fat': data['fat'] ?? 0,
      'carbs': data['carbs'] ?? 0,
      'createdAt': Timestamp.now(),
    });
  }

  Future<String> getAIContextSummary() async {
    final user = _auth.currentUser;
    if (user == null) return "Данные пользователя недоступны.";

    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      // БЛОК 3: Проверяем наличие плана питания и передаем статус ИИ
      final goalDoc = await _db.collection('users').doc(user.uid).collection('nutrition_goal').doc('current').get();
      final bool hasNutritionPlan = goalDoc.exists && (goalDoc.data()?['calories'] ?? 0) > 0;
      final String planStatus = hasNutritionPlan ? "has_nutrition_plan == true" : "has_nutrition_plan == false";

      final int avgCals = (userData['weeklyAvgCals'] as num?)?.toInt() ?? 0;
      final double totalTonnage = (userData['weeklyTonnage'] as num?)?.toDouble() ?? 0.0;

      final foodsSnap = await _db.collection('users').doc(user.uid).collection('custom_foods').get();
      String customFoodsContext = "";
      if (foodsSnap.docs.isNotEmpty) {
        customFoodsContext = "\n[ЛИЧНАЯ БАЗА ПРОДУКТОВ ПОЛЬЗОВАТЕЛЯ]:\n";
        for (var doc in foodsSnap.docs) {
          final f = doc.data();
          customFoodsContext += "- ${f['name']}: ${f['calories']} ккал (Б:${f['protein']} Ж:${f['fat']} У:${f['carbs']})\n";
        }
        customFoodsContext += "ВАЖНО: Если пользователь упоминает продукт из этого списка, СТРОГО используй эти значения КБЖУ!\n";
      }

      return """
[СЕКРЕТНЫЙ СИСТЕМНЫЙ КОНТЕКСТ]
Статус пользователя: $planStatus
Физические параметры:
- Пол: ${userData['gender'] ?? 'не указан'}
- Возраст: ${userData['age'] ?? 'не указан'}
- Вес: ${userData['weight'] ?? 'не указан'} кг
- Рост: ${userData['height'] ?? 'не указан'} см
- Цель: ${userData['goal'] ?? 'не указана'}
Данные из дневника:
- В среднем съедено: $avgCals ккал/день
- Поднятый тоннаж: ${(totalTonnage / 1000).toStringAsFixed(1)} тонн
$customFoodsContext
""";
    } catch (e) { return "Контекст недоступен."; }
  }

  Future<String> applyPromoCode(String code) async {
    final user = _auth.currentUser;
    if (user == null) return "Ошибка авторизации";

    try {
      final snapshot = await _db.collection('promocodes').where('code', isEqualTo: code.trim()).limit(1).get();
      if (snapshot.docs.isEmpty) return "Промокод не найден";

      final promoData = snapshot.docs.first.data();
      final String type = promoData['type'] ?? 'trial';

      if (type == 'discount_50') return "discount_50";

      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;

      DateTime currentProUntil = DateTime.now();
      if (userData != null && userData['proUntil'] != null) {
        final Timestamp ts = userData['proUntil'];
        if (ts.toDate().isAfter(DateTime.now())) currentProUntil = ts.toDate();
      }

      DateTime newProUntil;
      if (type == 'lifetime') {
        newProUntil = DateTime(2099, 1, 1); 
      } else {
        final int freeDays = promoData['freeDays'] ?? 3;
        if (freeDays <= 0) return "Недействительный промокод";
        newProUntil = currentProUntil.add(Duration(days: freeDays));
      }

      await _db.collection('users').doc(user.uid).update({
        'isPro': true,
        'proUntil': Timestamp.fromDate(newProUntil),
      });

      return type == 'lifetime' ? "success_lifetime" : "success_trial";
    } catch (e) {
      return "Ошибка сервера: $e";
    }
  }
}