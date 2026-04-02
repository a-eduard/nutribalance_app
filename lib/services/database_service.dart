import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  DateTime _getLogicalNow() {
    return DateTime.now().toLocal().subtract(const Duration(hours: 3));
  }

  String getTodayDocId() {
    final logicalNow = _getLogicalNow();
    return "${logicalNow.year}-${logicalNow.month.toString().padLeft(2, '0')}-${logicalNow.day.toString().padLeft(2, '0')}";
  }

  Future<void> updateUserData(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .set(data, SetOptions(merge: true));
    }
  }

  Future<Map<String, String>> getSpecialistInfo() async {
    try {
      final doc = await _db.collection('app_settings').doc('globals').get();
      
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        return {
          'uid': data['specialist_uid'] ?? 'VlTTLh2o7GVaXUzw32sNUtQ6alD3',
          'name': data['specialist_name'] ?? 'Личный Специалист',
        };
      }
    } catch (e) {
      debugPrint("Ошибка получения данных специалиста: $e");
    }
    
    return {
      'uid': 'VlTTLh2o7GVaXUzw32sNUtQ6alD3', 
      'name': 'Личный Специалист'
    };
  }

  Future<bool> isAppInReview() async {
    try {
      final doc = await _db.collection('app_config').doc('settings').get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['isAppInReview'] == true;
      }
    } catch (e) {
      debugPrint("Ошибка получения статуса модерации: $e");
    }
    return false;
  }

  Future<String?> createYookassaPayment({
    required double amount,
    required String description,
    required String paymentType, 
    int? durationDays,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;
      
      final String idempotencyKey = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}';

      final result = await FirebaseFunctions.instance.httpsCallable('createPayment').call({
        'amount': amount,
        'description': description,
        'paymentType': paymentType,
        'durationDays': durationDays,
        'idempotencyKey': idempotencyKey, 
      });
      return result.data['confirmationUrl'] as String?;
    } catch (e) {
      debugPrint('Ошибка создания платежа: $e');
      return null;
    }
  }

  Future<bool> isNicknameUnique(String nickname) async {
    if (nickname.isEmpty) return true;
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final snapshot = await _db
          .collection('users')
          .where('nickname', isEqualTo: nickname)
          .get();
      if (snapshot.docs.isEmpty) return true;
      for (var doc in snapshot.docs) {
        if (doc.id != user.uid) return false;
      }
      return true;
    } catch (e) {
      debugPrint("Ошибка проверки уникальности ника: $e");
      return false;
    }
  }
  
  Future<void> savePeriodData({required DateTime start, int cycleLength = 28, int periodDuration = 5}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    await _db.collection('users').doc(user.uid).set({
      'lastPeriodStartDate': Timestamp.fromDate(start),
      'cycleLength': cycleLength,
      'periodDuration': periodDuration,
    }, SetOptions(merge: true));
  }
  
  Future<void> updateWaterGlasses(int count) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = getTodayDocId();
    await _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(docId)
        .set({
          'water_glasses': count,
          'date': Timestamp.fromDate(_getLogicalNow()),
        }, SetOptions(merge: true));
  }

  Future<void> updatePeriodStartDate(DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).set({
      'lastPeriodStartDate': Timestamp.fromDate(date),
    }, SetOptions(merge: true));
  }

  Stream<DocumentSnapshot> getUserData() {
    final user = _auth.currentUser;
    if (user != null) return _db.collection('users').doc(user.uid).snapshots();
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
    } catch (e) {
      return null;
    }
  }

  Stream<QuerySnapshot> getBotChatMessages(String botType) {
    final user = _auth.currentUser;
    if (user != null) {
      return _db
          .collection('users')
          .doc(user.uid)
          .collection('ai_chats_$botType')
          .orderBy('timestamp', descending: true)
          .snapshots();
    }
    return const Stream.empty();
  }

  Future<void> saveBotChatMessage(
    String botType,
    String text,
    String role, {
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user != null) {
      await _db
          .collection('users')
          .doc(user.uid)
          .collection('ai_chats_$botType')
          .add({
            'text': text,
            'role': role,
            'imageUrl': imageUrl,
            'timestamp': FieldValue.serverTimestamp(),
            'isActionCompleted': false,
          });
    }
  }

  Future<void> markBotMessageAsActionCompleted(
    String botType,
    String docId,
  ) async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _db
            .collection('users')
            .doc(user.uid)
            .collection('ai_chats_$botType')
            .doc(docId)
            .update({'isActionCompleted': true});
      } catch (e) {
        debugPrint("Ошибка обновления статуса сообщения: $e");
      }
    }
  }

  Future<List<Map<String, String>>> getChatHistoryForAI(String botType) async {
    final user = _auth.currentUser;
    if (user == null) return [];
    final snapshots = await _db
        .collection('users')
        .doc(user.uid)
        .collection('ai_chats_$botType')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .get();
    return snapshots.docs.reversed.map((doc) {
      final data = doc.data();
      return {
        "role": data['role'] == 'ai' ? 'assistant' : 'user',
        "text": data['text'].toString(),
      };
    }).toList();
  }

  Future<void> saveNutritionGoal(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('nutrition_goal')
        .doc('current')
        .set({
          'calories': data['calories'] ?? 0,
          'protein': data['protein'] ?? 0,
          'fat': data['fat'] ?? 0,
          'carbs': data['carbs'] ?? 0,
          'updatedAt': Timestamp.now(),
        }, SetOptions(merge: true));

    Map<String, dynamic> profileUpdates = {};
    if (data['bmr'] != null) profileUpdates['bmr'] = data['bmr'];
    if (data['maintenanceCalories'] != null) {
      profileUpdates['maintenanceCalories'] = data['maintenanceCalories'];
    }
    if (profileUpdates.isNotEmpty) {
      await _db
          .collection('users')
          .doc(user.uid)
          .set(profileUpdates, SetOptions(merge: true));
    }
  }

  Future<void> _updateWeeklyNutritionCache(String uid) async {
    try {
      final weekAgoTs = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 7)),
      );
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('meals')
          .where('date', isGreaterThanOrEqualTo: weekAgoTs)
          .get();
      int totalCals = 0;
      for (var doc in snap.docs) {
        totalCals += (doc.data()['calories'] as num?)?.toInt() ?? 0;
      }
      int avgCals = snap.docs.isEmpty ? 0 : totalCals ~/ 7;
      await _db.collection('users').doc(uid).set({
        'weeklyAvgCals': avgCals,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Фоновая ошибка кэширования: $e");
    }
  }

  // Добавили необязательный параметр extraImageUrl, чтобы передавать фото из чата, если его нет в JSON
  Future<void> logMeal(Map<String, dynamic> data, {String? extraImageUrl}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String docId = getTodayDocId();
    List<dynamic> rawItems = data['items'] ?? [];
    
    if (rawItems.isEmpty && (data['meal_name'] != null || data['name'] != null)) {
      rawItems = [data];
    }

    int _safeInt(dynamic val) {
      if (val is num) return val.toInt();
      if (val is String) return double.tryParse(val.replaceAll(RegExp(r'[^0-9.]'), ''))?.toInt() ?? 0;
      return 0;
    }

    double _safeDouble(dynamic val, [double def = 100.0]) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val.replaceAll(RegExp(r'[^0-9.]'), '')) ?? def;
      return def;
    }

    int totalCals = 0, totalProt = 0, totalFat = 0, totalCarbs = 0, totalFiber = 0;
    List<Map<String, dynamic>> ingredients = [];

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      
      final int c = _safeInt(item['calories']);
      final int p = _safeInt(item['protein']);
      final int f = _safeInt(item['fat']);
      final int carb = _safeInt(item['carbs']);
      final int fib = _safeInt(item['fiber']); // <-- Клетчатка
      final double grams = _safeDouble(item['weight_g'] ?? item['grams'], 100.0);
      
      // Строгий приоритет названия: берем meal_name, если он есть
      final String name = item['meal_name'] ?? item['name'] ?? item['product_name'] ?? 'Ингредиент';

      int healthScore = _safeInt(item['health_score']);
      if (healthScore == 0) healthScore = 5;

      ingredients.add({
        'id': '${DateTime.now().millisecondsSinceEpoch}_$i', 
        'name': name,
        'calories': c,
        'protein': p,
        'fat': f,
        'carbs': carb,
        'fiber': fib, // <-- Сохраняем клетчатку
        'weight_g': grams,
        'health_score': healthScore, 
      });

      totalCals += c;
      totalProt += p;
      totalFat += f;
      totalCarbs += carb;
      totalFiber += fib; // <-- Плюсуем общую клетчатку
    }

    if (ingredients.isEmpty) {
      debugPrint("Ошибка: ИИ вернул пустой список ингредиентов");
      return;
    }

    double avgHealthScore = 0;
    for (var ing in ingredients) {
      avgHealthScore += (ing['health_score'] as int);
    }
    avgHealthScore = ingredients.isNotEmpty ? avgHealthScore / ingredients.length : 5.0;

    final String mealId = DateTime.now().millisecondsSinceEpoch.toString();
    final mealEntry = {
      'id': mealId,
      // УМНЫЙ ФОЛБЭК: Если ИИ забыл общее название, берем имя из первого ингредиента
      'name': data['meal_name'] ?? data['name'] ?? (ingredients.isNotEmpty ? ingredients.first['name'] : 'Прием пищи'),
      // УМНЫЙ ФОЛБЭК КАРТИНКИ: Приоритет URL из JSON, если нет - берем переданный из чата extraImageUrl
      'imageUrl': data['imageUrl'] ?? extraImageUrl, 
      'calories': totalCals,
      'protein': totalProt,
      'fat': totalFat,
      'carbs': totalCarbs,
      'fiber': totalFiber, // <-- Сохраняем общую клетчатку в блюдо
      'health_score': avgHealthScore.round(), 
      'timestamp': Timestamp.now(),
      'is_grouped': true, 
      'ingredients': ingredients,
    };

    // Set с merge: true гарантированно создаст документ для новичка, если его еще нет
    await _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(docId)
        .set({
          'items': FieldValue.arrayUnion([mealEntry]), 
          'calories': FieldValue.increment(totalCals),
          'protein': FieldValue.increment(totalProt),
          'fat': FieldValue.increment(totalFat),
          'carbs': FieldValue.increment(totalCarbs),
          'fiber': FieldValue.increment(totalFiber), // <-- Инкремент клетчатки
          'date': Timestamp.fromDate(_getLogicalNow()),
        }, SetOptions(merge: true));

    _updateWeeklyNutritionCache(user.uid);
  }

  Future<void> updateIngredientWeight(String mealId, Map<String, dynamic> oldIngredient, int newWeightG) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = getTodayDocId();
    final docRef = _db.collection('users').doc(user.uid).collection('meals').doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      List<dynamic> items = snapshot.data()?['items'] ?? [];
      final mealIndex = items.indexWhere((m) => m['id'] == mealId);
      if (mealIndex == -1) return;

      Map<String, dynamic> meal = Map<String, dynamic>.from(items[mealIndex]);
      List<dynamic> ingredients = List.from(meal['ingredients'] ?? []);
      final ingIndex = ingredients.indexWhere((i) => i['id'] == oldIngredient['id']);
      if (ingIndex == -1) return;

      double oldWeight = (oldIngredient['weight_g'] as num?)?.toDouble() ?? 100.0;
      if (oldWeight <= 0) oldWeight = 100.0; 
      final double ratio = newWeightG / oldWeight;

      final int newC = ((oldIngredient['calories'] as num) * ratio).round();
      final int newP = ((oldIngredient['protein'] as num) * ratio).round();
      final int newF = ((oldIngredient['fat'] as num) * ratio).round();
      final int newCarb = ((oldIngredient['carbs'] as num) * ratio).round();
      final int newFib = (((oldIngredient['fiber'] as num?) ?? 0) * ratio).round(); // <-- Безопасный пересчет клетчатки
      
      final int hScore = oldIngredient['health_score'] ?? 5;

      final int diffC = newC - (oldIngredient['calories'] as int);
      final int diffP = newP - (oldIngredient['protein'] as int);
      final int diffF = newF - (oldIngredient['fat'] as int);
      final int diffCarb = newCarb - (oldIngredient['carbs'] as int);
      final int diffFib = newFib - ((oldIngredient['fiber'] ?? 0) as int); // <-- Разница клетчатки

      ingredients[ingIndex] = {
        ...oldIngredient,
        'weight_g': newWeightG,
        'calories': newC,
        'protein': newP,
        'fat': newF,
        'carbs': newCarb,
        'fiber': newFib, // <-- Сохраняем новую клетчатку
        'health_score': hScore,
      };

      meal['ingredients'] = ingredients;
      meal['calories'] = (meal['calories'] as int) + diffC;
      meal['protein'] = (meal['protein'] as int) + diffP;
      meal['fat'] = (meal['fat'] as int) + diffF;
      meal['carbs'] = (meal['carbs'] as int) + diffCarb;
      meal['fiber'] = ((meal['fiber'] ?? 0) as int) + diffFib; // <-- Обновляем клетчатку блюда

      items[mealIndex] = meal;

      int totalCals = 0, totalProt = 0, totalFat = 0, totalCarbs = 0, totalFiber = 0;
      for (var i in items) {
        totalCals += (i['calories'] as num?)?.toInt() ?? 0;
        totalProt += (i['protein'] as num?)?.toInt() ?? 0;
        totalFat += (i['fat'] as num?)?.toInt() ?? 0;
        totalCarbs += (i['carbs'] as num?)?.toInt() ?? 0;
        totalFiber += (i['fiber'] as num?)?.toInt() ?? 0;
      }

      transaction.update(docRef, {
        'items': items, 
        'calories': totalCals, 
        'protein': totalProt, 
        'fat': totalFat, 
        'carbs': totalCarbs,
        'fiber': totalFiber, // <-- Обновляем общий документ
      });
    });
    
    _updateWeeklyNutritionCache(user.uid);
  }

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

  Stream<DocumentSnapshot> getTodayMealsDoc() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    final String docId = getTodayDocId();
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(docId)
        .snapshots();
  }

  Stream<DocumentSnapshot> getNutritionGoal() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('nutrition_goal')
        .doc('current')
        .snapshots();
  }

  Future<void> saveCustomFood(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).collection('custom_foods').add({
      'name': data['product_name'] ?? data['name'] ?? 'Свой продукт',
      'calories': data['calories_100g'] ?? data['calories'] ?? 0,
      'protein': data['protein_100g'] ?? data['protein'] ?? 0,
      'fat': data['fat_100g'] ?? data['fat'] ?? 0,
      'carbs': data['carbs_100g'] ?? data['carbs'] ?? 0,
      'createdAt': Timestamp.now(),
    });
  }

  Future<String> getAIContextSummary() async {
    final user = _auth.currentUser;
    if (user == null) return "Данные пользователя недоступны.";

    try {
      final String todayDocId = getTodayDocId();

      final results = await Future.wait([
        _db.collection('users').doc(user.uid).get(),
        _db.collection('users').doc(user.uid).collection('nutrition_goal').doc('current').get(),
        _db.collection('users').doc(user.uid).collection('custom_foods').get(),
        _db.collection('users').doc(user.uid).collection('cycle_logs').doc(todayDocId).get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final goalDoc = results[1] as DocumentSnapshot;
      final foodsSnap = results[2] as QuerySnapshot;
      final harmonyDoc = results[3] as DocumentSnapshot; 

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      final bool hasNutritionPlan = goalDoc.exists && ((goalDoc.data() as Map<String, dynamic>?)?['calories'] ?? 0) > 0;
      final String planStatus = hasNutritionPlan ? "has_nutrition_plan == true" : "has_nutrition_plan == false";

      final int avgCals = (userData['weeklyAvgCals'] as num?)?.toInt() ?? 0;

      String cyclePhase = 'Не указано';
      
      final bool isPregnant = userData['isPregnant'] ?? false;
      final Timestamp? pregStart = userData['pregnancyStartDate'] as Timestamp?;
      String pregnancyContext = "";

      if (isPregnant) {
        int weeks = 0;
        if (pregStart != null) {
          weeks = DateTime.now().difference(pregStart.toDate()).inDays ~/ 7;
          if (weeks > 42) weeks = 42;
        }
        pregnancyContext = "ПОЛЬЗОВАТЕЛЬ БЕРЕМЕННА (Срок: $weeks недель). Категорически запрещены жесткие диеты для похудения. Давай советы, адаптированные для беременных. Тон: максимально бережный и заботливый.";
        cyclePhase = "Беременность ($weeks недель)";
      } else {
        final Timestamp? lastPeriod = userData['lastPeriodStartDate'] as Timestamp?;
        final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

        if (lastPeriod != null) {
          final start = DateTime(lastPeriod.toDate().year, lastPeriod.toDate().month, lastPeriod.toDate().day);
          final now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          final int diff = now.difference(start).inDays;

          if (diff >= 0) {
            final int dayOfCycle = (diff % cycleLength) + 1;
            if (dayOfCycle <= 5) cyclePhase = 'Менструация ($dayOfCycle-й день)';
            else if (dayOfCycle <= 13) cyclePhase = 'Фолликулярная фаза ($dayOfCycle-й день)';
            else if (dayOfCycle <= 15) cyclePhase = 'Овуляция ($dayOfCycle-й день)';
            else cyclePhase = 'Лютеиновая фаза / ПМС ($dayOfCycle-й день)';
          }
        }
      }

      String harmonyContextText = "Сегодня данные в раздел Гармония не вносились.";
      if (harmonyDoc.exists) {
        final hData = harmonyDoc.data() as Map<String, dynamic>? ?? {};
        final symptomsList = List<String>.from(hData['symptoms'] ?? []);
        final String symptoms = symptomsList.isEmpty ? 'Нет' : symptomsList.join(', ');
        final String mood = hData['mood'] ?? 'Не отмечено';
        final String sleep = hData['sleep'] ?? 'Не отмечено';
        
        harmonyContextText = """
СЕГОДНЯШНЕЕ САМОЧУВСТВИЕ (из раздела Гармония):
- Симптомы: $symptoms
- Настроение: $mood
- Сон: $sleep
""";
      }
      
      final Map<String, dynamic> qData = userData['questionnaire'] ?? {};
      String questionnaireContext = "";
      if (qData.isNotEmpty) {
        questionnaireContext = "\n[ПОДРОБНАЯ АНКЕТА ПОЛЬЗОВАТЕЛЯ (Изучи внимательно)]:\n";
        qData.forEach((key, value) {
          if (value is List) {
            questionnaireContext += "- $key: ${value.join(', ')}\n";
          } else {
            questionnaireContext += "- $key: $value\n";
          }
        });
      }

      String customFoodsContext = "";
      if (foodsSnap.docs.isNotEmpty) {
        customFoodsContext = "\n[ЛИЧНАЯ БАЗА ПРОДУКТОВ ПОЛЬЗОВАТЕЛЯ]:\n";
        for (var doc in foodsSnap.docs) {
          final f = doc.data() as Map<String, dynamic>;
          customFoodsContext += "- ${f['name']}: ${f['calories']} ккал (Б:${f['protein']} Ж:${f['fat']} У:${f['carbs']})\n";
        }
      }

      return """
[СЕКРЕТНЫЙ СИСТЕМНЫЙ КОНТЕКСТ]
Статус: $planStatus
$pregnancyContext
Пол: ${userData['gender'] ?? 'не указан'} | Возраст: ${userData['age'] ?? 'не указан'} | Рост: ${userData['height'] ?? 'не указан'} см | Вес: ${userData['weight'] ?? 'не указан'} кг | Цель: ${userData['goals'] ?? userData['goal'] ?? 'не указана'}
$questionnaireContext

ИНСТРУКЦИЯ ПО ЦИКЛУ:
Фаза цикла: $cyclePhase. Адаптируй советы по питанию под эту фазу. Если 'Лютеиновая фаза / ПМС', проявляй особую заботу.

$harmonyContextText
ВНИМАНИЕ: Ты ВИДИШЬ раздел Гармония (он передан тебе в тексте выше). НИКОГДА не говори пользователю "Я не вижу раздел Гармония". Если пользователь просит проанализировать его показатели, используй данные из блока "СЕГОДНЯШНЕЕ САМОЧУВСТВИЕ" и дай заботливую обратную связь.

Данные по калориям: В среднем за неделю съедено $avgCals ккал/день.
$customFoodsContext
""";
    } catch (e) {
      return "Контекст недоступен.";
    }
  }

  Future<void> saveAIWorkoutProgram(Map<String, dynamic> data) async {}
  Future<void> saveAIDietPlan(Map<String, dynamic> data) async {}

  Future<Map<String, dynamic>?> checkPromoCode(String rawCode) async {
    final String cleanCode = rawCode.trim().toUpperCase();
    if (cleanCode.isEmpty) return null;
    try {
      final snapshot = await _db.collection('promocodes').where('code', isEqualTo: cleanCode).limit(1).get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data() as Map<String, dynamic>;
        if (data['isActive'] == true) return data;
      }
      return null;
    } catch (e) { return null; }
  }

  Future<void> activateTrial(int days) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final newProUntil = DateTime.now().add(Duration(days: days));
    await _db.collection('users').doc(user.uid).update({'isPro': true, 'proUntil': Timestamp.fromDate(newProUntil)});
  }

  Future<void> deleteMealItem(Map<String, dynamic> item) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = getTodayDocId();
    final docRef = _db.collection('users').doc(user.uid).collection('meals').doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      List<dynamic> items = snapshot.data()?['items'] ?? [];
      final originalLength = items.length;
      
      // Ищем строго по ID, чтобы избежать проблем с Timestamp
      items.removeWhere((i) => i['id'] == item['id']);

      if (items.length == originalLength) return; // Блюдо не найдено

      // Пересчитываем итоги с нуля для надежности
      int totalCals = 0, totalProt = 0, totalFat = 0, totalCarbs = 0, totalFiber = 0;
      for (var i in items) {
        totalCals += (i['calories'] as num?)?.toInt() ?? 0;
        totalProt += (i['protein'] as num?)?.toInt() ?? 0;
        totalFat += (i['fat'] as num?)?.toInt() ?? 0;
        totalCarbs += (i['carbs'] as num?)?.toInt() ?? 0;
        totalFiber += (i['fiber'] as num?)?.toInt() ?? 0;
      }

      transaction.update(docRef, {
        'items': items,
        'calories': totalCals,
        'protein': totalProt,
        'fat': totalFat,
        'carbs': totalCarbs,
        'fiber': totalFiber,
      });
    });

    _updateWeeklyNutritionCache(user.uid);
  }

  Future<void> updateMealItemWeight(Map<String, dynamic> oldItem, int newWeightG) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = getTodayDocId();
    final docRef = _db.collection('users').doc(user.uid).collection('meals').doc(docId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      List<dynamic> items = snapshot.data()?['items'] ?? [];
      final itemIndex = items.indexWhere((i) => i['id'] == oldItem['id']);
      if (itemIndex == -1) return;

      double oldWeight = (oldItem['weight_g'] as num?)?.toDouble() ?? 100.0;
      if (oldWeight <= 0) oldWeight = 100.0; 
      final double ratio = newWeightG / oldWeight;

      final newItem = {
        ...oldItem,
        'weight_g': newWeightG,
        'calories': ((oldItem['calories'] as num) * ratio).round(),
        'protein': ((oldItem['protein'] as num) * ratio).round(),
        'fat': ((oldItem['fat'] as num) * ratio).round(),
        'carbs': ((oldItem['carbs'] as num) * ratio).round(),
      };

      items[itemIndex] = newItem;

      int totalCals = 0, totalProt = 0, totalFat = 0, totalCarbs = 0;
      for (var i in items) {
        totalCals += (i['calories'] as num).toInt();
        totalProt += (i['protein'] as num).toInt();
        totalFat += (i['fat'] as num).toInt();
        totalCarbs += (i['carbs'] as num).toInt();
      }

      transaction.update(docRef, {
        'items': items, 'calories': totalCals, 'protein': totalProt, 'fat': totalFat, 'carbs': totalCarbs,
      });
    });
    
    // ФИКС СПРИНТА 3: Убран await
    _updateWeeklyNutritionCache(user.uid);
  }

  Future<void> saveShoppingList(Map<String, dynamic> jsonData) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final categories = jsonData['categories'] ?? [];
    List<dynamic> parsedCategories = [];
    for (var cat in categories) {
      List<dynamic> items = cat['items'] ?? [];
      List<dynamic> parsedItems = items.map((item) => {
        'name': item['name'] ?? '',
        'amount': item['amount'] ?? '',
        'isChecked': false,
      }).toList();
      parsedCategories.add({'name': cat['name'] ?? 'Категория', 'items': parsedItems});
    }
    await _db.collection('users').doc(user.uid).collection('shopping_list').doc('current').set({'categories': parsedCategories, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> clearCheckedShoppingItems() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _db.collection('users').doc(user.uid).collection('shopping_list').doc('current');
    
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      List<dynamic> categories = snapshot.data()?['categories'] ?? [];
      List<dynamic> updatedCategories = [];
      for (var cat in categories) {
        List<dynamic> items = cat['items'] ?? [];
        List<dynamic> remainingItems = items.where((item) => item['isChecked'] != true).toList();
        if (remainingItems.isNotEmpty) {
          updatedCategories.add({'name': cat['name'], 'items': remainingItems});
        }
      }
      transaction.update(docRef, {'categories': updatedCategories});
    });
  }

  Future<void> toggleShoppingListItem(String categoryName, String itemName, bool isChecked) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _db.collection('users').doc(user.uid).collection('shopping_list').doc('current');
    
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      List<dynamic> categories = snapshot.data()?['categories'] ?? [];
      for (var cat in categories) {
        if (cat['name'] == categoryName) {
          List<dynamic> items = cat['items'] ?? [];
          for (var item in items) {
            if (item['name'] == itemName) {
              item['isChecked'] = isChecked;
            }
          }
        }
      }
      transaction.update(docRef, {'categories': categories});
    });
  }

  Future<void> syncCatalogShoppingList(Set<String> selectedNames, Map<String, String> productCategories) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _db.collection('users').doc(user.uid).collection('shopping_list').doc('current');

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      List<dynamic> existingCategories = snapshot.exists ? (snapshot.data()?['categories'] ?? []) : [];

      Map<String, Map<String, dynamic>> oldItemData = {};
      for (var cat in existingCategories) {
        for (var item in (cat['items'] ?? [])) {
          oldItemData[item['name']] = {'isChecked': item['isChecked'] ?? false, 'amount': item['amount'] ?? ''};
        }
      }

      Map<String, List<Map<String, dynamic>>> newCategoriesMap = {};
      for (String name in selectedNames) {
        String catName = productCategories[name] ?? 'Разное';
        if (!newCategoriesMap.containsKey(catName)) newCategoriesMap[catName] = [];
        newCategoriesMap[catName]!.add({'name': name, 'amount': oldItemData[name]?['amount'] ?? '', 'isChecked': oldItemData[name]?['isChecked'] ?? false});
      }

      List<Map<String, dynamic>> finalCategories = [];
      newCategoriesMap.forEach((key, value) { finalCategories.add({'name': key, 'items': value}); });

      transaction.set(docRef, {'categories': finalCategories, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  Future<void> addIngredientsToShoppingList(List<dynamic> newItems) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final docRef = _db.collection('users').doc(user.uid).collection('shopping_list').doc('current');

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      List<dynamic> categories = snapshot.exists ? (snapshot.data()?['categories'] ?? []) : [];

      for (var newItem in newItems) {
        String catName = newItem['category'] ?? 'Из рецептов';
        String itemName = newItem['name'] ?? 'Продукт';
        String amount = newItem['amount'] ?? '';

        int catIndex = categories.indexWhere((c) => c['name'] == catName);
        if (catIndex == -1) {
          categories.add({'name': catName, 'items': [{'name': itemName, 'amount': amount, 'isChecked': false}]});
        } else {
          List<dynamic> items = categories[catIndex]['items'];
          if (!items.any((i) => i['name'].toString().toLowerCase() == itemName.toLowerCase())) {
            items.add({'name': itemName, 'amount': amount, 'isChecked': false});
          }
        }
      }

      transaction.set(docRef, {'categories': categories, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    });
  }

  Future<void> saveDailySymptoms(DateTime date, List<String> symptoms) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    await _db.collection('users').doc(user.uid).collection('cycle_logs').doc(docId).set({'symptoms': symptoms, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }
  
  Future<void> deleteBotChatMessage(String botType, String docId, String? imageUrl) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(imageUrl);
          await ref.delete();
          debugPrint("Картинка успешно удалена из Storage");
        } catch (e) {
          debugPrint("Ошибка удаления картинки из Storage: $e");
        }
      }

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('ai_chats_$botType')
          .doc(docId)
          .delete();
      
      debugPrint("Документ сообщения успешно удален");
    } catch (e) {
      debugPrint("Ошибка удаления сообщения: $e");
      rethrow;
    }
  }

  Future<void> updateActivityAndRecalculate(String activityLevel) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final double weight = (data['weight'] as num?)?.toDouble() ?? 65.0;
      final double height = (data['height'] as num?)?.toDouble() ?? 165.0;
      final int age = (data['age'] as num?)?.toInt() ?? 25;
      final String gender = data['gender'] ?? 'female';
      final String goal = data['goal'] ?? 'Похудеть';

      double bmr = (10 * weight) + (6.25 * height) - (5 * age);
      bmr = gender == 'male' ? bmr + 5 : bmr - 161;

      double multiplier = 1.2; 
      if (activityLevel.contains('Умеренная')) multiplier = 1.375;
      else if (activityLevel.contains('Высокая')) multiplier = 1.55;
      else if (activityLevel.contains('Очень высокая')) multiplier = 1.725;

      int maintenance = (bmr * multiplier).round();
      int targetCals = maintenance;

      if (goal == 'Похудеть') targetCals = (maintenance * 0.85).round(); 
      else if (goal == 'Набрать массу') targetCals = (maintenance * 1.15).round(); 

      int protein = (weight * 1.8).round();
      int fat = (weight * 1.0).round();
      int carbs = ((targetCals - (protein * 4) - (fat * 9)) / 4).round();

      await _db.collection('users').doc(user.uid).update({
        'activityLevel': activityLevel,
        'bmr': bmr.round(),
        'maintenanceCalories': maintenance,
      });

      await saveNutritionGoal({
        'calories': targetCals,
        'protein': protein,
        'fat': fat,
        'carbs': carbs > 0 ? carbs : 0,
      });

    } catch (e) {
      debugPrint("Ошибка пересчета КБЖУ: $e");
    }
  }
  
  Future<void> addCheatMealBonus(int bonusCalories) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final String docId = getTodayDocId();
    
    await _db.collection('users').doc(user.uid).collection('meals').doc(docId).set({
      'bonus_calories': FieldValue.increment(bonusCalories),
      'date': Timestamp.fromDate(_getLogicalNow()),
    }, SetOptions(merge: true));
  }
  
  Future<void> updateBotChatMessage(String botType, String docId, String newText) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _db
        .collection('users')
        .doc(user.uid)
        .collection('ai_chats_$botType')
        .doc(docId)
        .update({'text': newText});
  }

  Future<void> deleteP2PMessage(String chatId, String docId, String? imageUrl) async {
    try {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final ref = FirebaseStorage.instance.refFromURL(imageUrl);
          await ref.delete();
        } catch (e) {
          debugPrint("Ошибка удаления фото P2P из Storage: $e");
        }
      }
      await _db.collection('chats').doc(chatId).collection('messages').doc(docId).delete();
    } catch (e) {
      debugPrint("Ошибка удаления P2P сообщения: $e");
      rethrow;
    }
  }

  Future<void> updateP2PMessage(String chatId, String docId, String newText) async {
    await _db.collection('chats').doc(chatId).collection('messages').doc(docId).update({'text': newText});
  }
}