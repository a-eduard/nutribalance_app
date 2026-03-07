import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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

  // --- ВОДА И ЦИКЛ ---
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

  // --- ИИ ЧАТ И ФАЙЛЫ ---
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
    if (user != null)
      return _db
          .collection('users')
          .doc(user.uid)
          .collection('ai_chats_$botType')
          .orderBy('timestamp', descending: true)
          .snapshots();
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

  // --- ПИТАНИЕ И ДНЕВНИК ---
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
    if (data['maintenanceCalories'] != null)
      profileUpdates['maintenanceCalories'] = data['maintenanceCalories'];
    if (profileUpdates.isNotEmpty)
      await _db
          .collection('users')
          .doc(user.uid)
          .set(profileUpdates, SetOptions(merge: true));
  }

  Future<void> _updateWeeklyNutritionCache(String uid) async {
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
    for (var doc in snap.docs)
      totalCals += (doc.data()['calories'] as num?)?.toInt() ?? 0;
    int avgCals = snap.docs.isEmpty ? 0 : totalCals ~/ 7;
    await _db.collection('users').doc(uid).set({
      'weeklyAvgCals': avgCals,
    }, SetOptions(merge: true));
  }

  Future<void> logMeal(Map<String, dynamic> data) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String docId = getTodayDocId();
    List<dynamic> rawItems = data['items'] ?? [];
    if (rawItems.isEmpty && data['meal_name'] != null) {
      rawItems = [data];
    }

    int totalCals = 0, totalProt = 0, totalFat = 0, totalCarbs = 0;

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i];
      final int c = (item['calories'] as num?)?.toInt() ?? 0;
      final int p = (item['protein'] as num?)?.toInt() ?? 0;
      final int f = (item['fat'] as num?)?.toInt() ?? 0;
      final int carb = (item['carbs'] as num?)?.toInt() ?? 0;
      final double grams =
          (item['weight_g'] as num?)?.toDouble() ??
          (item['grams'] as num?)?.toDouble() ??
          100.0;
      final String name = item['meal_name'] ?? item['name'] ?? 'Блюдо';

      final String itemId = '${DateTime.now().millisecondsSinceEpoch}_$i';

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('meals')
          .doc(docId)
          .collection('items')
          .doc(itemId)
          .set({
            'name': name,
            'calories': c,
            'protein': p,
            'fat': f,
            'carbs': carb,
            'grams': grams,
            'timestamp': FieldValue.serverTimestamp(),
          });

      totalCals += c;
      totalProt += p;
      totalFat += f;
      totalCarbs += carb;
    }

    if (totalCals == 0 && totalProt == 0) return;

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('meals')
        .doc(docId)
        .set({
          'calories': FieldValue.increment(totalCals),
          'protein': FieldValue.increment(totalProt),
          'fat': FieldValue.increment(totalFat),
          'carbs': FieldValue.increment(totalCarbs),
          'date': Timestamp.fromDate(_getLogicalNow()),
        }, SetOptions(merge: true));

    await _updateWeeklyNutritionCache(user.uid);
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

  // --- КОНТЕКСТ ДЛЯ ИИ (ПРОМПТЫ) ---
  Future<String> getAIContextSummary() async {
    final user = _auth.currentUser;
    if (user == null) return "Данные пользователя недоступны.";

    try {
      final results = await Future.wait([
        _db.collection('users').doc(user.uid).get(),
        _db
            .collection('users')
            .doc(user.uid)
            .collection('nutrition_goal')
            .doc('current')
            .get(),
        _db.collection('users').doc(user.uid).collection('custom_foods').get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final goalDoc = results[1] as DocumentSnapshot;
      final foodsSnap = results[2] as QuerySnapshot;

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};

      final bool hasNutritionPlan =
          goalDoc.exists &&
          ((goalDoc.data() as Map<String, dynamic>?)?['calories'] ?? 0) > 0;
      final String planStatus = hasNutritionPlan
          ? "has_nutrition_plan == true"
          : "has_nutrition_plan == false";

      final int avgCals = (userData['weeklyAvgCals'] as num?)?.toInt() ?? 0;

      String cyclePhase = 'Не указано';
      final Timestamp? lastPeriod =
          userData['lastPeriodStartDate'] as Timestamp?;
      final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

      if (lastPeriod != null) {
        final start = DateTime(
          lastPeriod.toDate().year,
          lastPeriod.toDate().month,
          lastPeriod.toDate().day,
        );
        final today = DateTime.now();
        final now = DateTime(today.year, today.month, today.day);
        final int diff = now.difference(start).inDays;

        if (diff >= 0) {
          final int dayOfCycle = (diff % cycleLength) + 1;
          if (dayOfCycle <= 5)
            cyclePhase = 'Менструация ($dayOfCycle-й день)';
          else if (dayOfCycle <= 13)
            cyclePhase = 'Фолликулярная фаза ($dayOfCycle-й день)';
          else if (dayOfCycle <= 15)
            cyclePhase = 'Овуляция ($dayOfCycle-й день)';
          else
            cyclePhase = 'Лютеиновая фаза / ПМС ($dayOfCycle-й день)';
        }
      }

      String customFoodsContext = "";
      if (foodsSnap.docs.isNotEmpty) {
        customFoodsContext = "\n[ЛИЧНАЯ БАЗА ПРОДУКТОВ ПОЛЬЗОВАТЕЛЯ]:\n";
        for (var doc in foodsSnap.docs) {
          final f = doc.data() as Map<String, dynamic>;
          customFoodsContext +=
              "- ${f['name']}: ${f['calories']} ккал (Б:${f['protein']} Ж:${f['fat']} У:${f['carbs']})\n";
        }
      }

      return """
[СЕКРЕТНЫЙ СИСТЕМНЫЙ КОНТЕКСТ]
Статус: $planStatus
Пол: ${userData['gender'] ?? 'не указан'} | Возраст: ${userData['age'] ?? 'не указан'} | Вес: ${userData['weight'] ?? 'не указан'} кг | Цель: ${userData['goal'] ?? 'не указана'}

ИНСТРУКЦИЯ ПО ЦИКЛУ:
Фаза цикла: $cyclePhase. Адаптируй советы по питанию под эту фазу. Если 'Лютеиновая фаза / ПМС', проявляй особую заботу.

👑 ПРЕМИУМ ПРАВИЛА И СЦЕНАРИИ (ONBOARDING, GUILT-FREE, РЕЦЕПТЫ И ПОКУПКИ):

0. СЦЕНАРИЙ ЗНАКОМСТВА (ONBOARDING): 
Триггер: Если пользователь отвечает согласием на твое стартовое приветственное сообщение (например: "Да", "Расскажи", "Что ты умеешь?").
Действие: Ответь тепло и дружелюбно. Перечисли свои главные суперспособности строго этим текстом:
«Я могу заменить тебе сразу несколько приложений! Вот что мы можем делать вместе:
📸 Дневник питания без рутины: Просто сфоткай свою тарелку или напиши мне текстом «съела сырники и латте», и я сама посчитаю КБЖУ.
🌸 Синхронизация с циклом: Я учитываю твой гормональный фон. В ПМС я предложу больше сложных углеводов и шоколад, чтобы снять отеки и поднять настроение.
🥑 Магия холодильника: Сфоткай то, что осталось на полке, и я за 5 секунд придумаю из этого вкусный и полезный рецепт!
🛒 Списки покупок: Я могу составить меню на неделю и выдать готовый чек-лист для супермаркета.
🩺 Чтение анализов: Пришли мне результаты своих анализов (например, ферритин или витамин D), и я подскажу, как скорректировать рацион.

Никакого чувства вины и стресса. С чего начнем? Хочешь записать свой первый прием пищи или посмотрим, что у тебя в холодильнике? ✨»

1. БЕЗ ЧУВСТВА ВИНЫ: Если пользователь превышает лимит калорий, НИКОГДА не ругай его. Поддержи: "Мы немного вышли за норму, но это абсолютно нормально! Главное — баланс. ✨"
2. МАГИЯ ХОЛОДИЛЬНИКА: Если присылают фото сырых продуктов, предложи 1 быстрый рецепт из них (с КБЖУ). Спроси: "Приготовим это? Я запишу в дневник". Выдай JSON `log_food` если согласны.
3. СПИСОК ПОКУПОК (action_type: "shopping_list"): Если просят составить список покупок, ОБЯЗАТЕЛЬНО выдай JSON:
```json
{
  "type": "shopping_list",
  "coach_message": "Вот твой список покупок! Отмечай купленное здесь 👇",
  "categories": [
    {"name": "Овощи", "items": [{"name": "Авокадо", "amount": "2 шт"}]}
  ]
}
Данные: В среднем съедено $avgCals ккал/день.
$customFoodsContext
""";
    } catch (e) {
      return "Контекст недоступен.";
    }
  }

  // --- МЕТОДЫ-ЗАГЛУШКИ ДЛЯ ТРЕНИРОВОК ---
  // Я оставил их пустыми/базовыми, чтобы не было ошибок компиляции, если они где-то вызываются
  Future<void> saveAIWorkoutProgram(Map<String, dynamic> data) async {}
  Future<void> saveAIDietPlan(Map<String, dynamic> data) async {}

  // --- ВОССТАНОВЛЕННЫЕ МЕТОДЫ ДЛЯ ПОДПИСКИ И СТАТИСТИКИ ---

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
    await _db.collection('users').doc(user.uid).collection('meals').doc(docId).update({
      'items': FieldValue.arrayRemove([item]),
      'calories': FieldValue.increment(-(item['calories'] as int)),
      'protein': FieldValue.increment(-(item['protein'] as int)),
      'fat': FieldValue.increment(-(item['fat'] as int)),
      'carbs': FieldValue.increment(-(item['carbs'] as int)),
    });
    await _updateWeeklyNutritionCache(user.uid);
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
    await _updateWeeklyNutritionCache(user.uid);
  }
}
