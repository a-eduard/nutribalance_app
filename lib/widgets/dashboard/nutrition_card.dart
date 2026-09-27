import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../screens/ai_chat_screen.dart';
import '../../services/database_service.dart';
import '../../theme/eva_colors.dart';
import '../eva_ui.dart';

class NutritionSummaryCard extends StatefulWidget {
  final String uid;
  final String docId;
  final Set<String> optimisticDeletedIds;

  /// Данные документа дня (если родитель уже подписан на него — не дублируем подписку).
  final Map<String, dynamic>? mealsData;

  const NutritionSummaryCard({
    super.key,
    required this.uid,
    required this.docId,
    required this.optimisticDeletedIds,
    this.mealsData,
  });

  @override
  State<NutritionSummaryCard> createState() => _NutritionSummaryCardState();
}

class _NutritionSummaryCardState extends State<NutritionSummaryCard> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _goalStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _mealsStream;
  String? _mealsStreamDocId;

  static const int _targetFiber = 25;

  @override
  void initState() {
    super.initState();
    _goalStream = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('nutrition_goal').doc('current').snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _meals() {
    if (_mealsStream == null || _mealsStreamDocId != widget.docId) {
      _mealsStreamDocId = widget.docId;
      _mealsStream = FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('meals').doc(widget.docId).snapshots();
    }
    return _mealsStream!;
  }

  // ---------------------------------------------------------------------------
  // «Что съесть?»
  // ---------------------------------------------------------------------------

  void _askEvaForMealPlan(int consumed, int norm, int curP, int targetP, int curF, int targetF, int curC, int targetC, int curFiber) {
    final int remaining = norm - consumed;
    if (norm <= 0) {
      _openEva('Рассчитай мою норму КБЖУ', 'Помоги рассчитать мою дневную норму калорий и БЖУ.');
      return;
    }
    if (remaining <= 0) {
      EvaSnack.show(context, 'Норма на сегодня уже выполнена ✨', type: EvaSnackType.success);
      return;
    }
    final int remP = targetP - curP, remF = targetF - curF, remC = targetC - curC, remFiber = _targetFiber - curFiber;

    if (remaining < 500) {
      _sendDietitianRequest(remaining, remP, remF, remC, remFiber, "1 лёгкий приём пищи или перекус", "Что мне съесть на $remaining ккал?");
      return;
    }

    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EvaSheetHeader(title: 'Как распределим $remaining ккал?', subtitle: 'Ева составит меню и список покупок'),
            EvaOptionTile(title: '1 плотный приём', icon: Icons.restaurant_rounded, selected: false, onTap: () {
              Navigator.pop(ctx);
              _sendDietitianRequest(remaining, remP, remF, remC, remFiber, "1 основной приём пищи", "Составь меню на $remaining ккал (1 приём)");
            }),
            EvaOptionTile(title: '2–3 приёма', icon: Icons.dinner_dining_rounded, selected: false, onTap: () {
              Navigator.pop(ctx);
              _sendDietitianRequest(remaining, remP, remF, remC, remFiber, "2 основных блюда и 1 перекус", "Составь меню на $remaining ккал (2–3 приёма)");
            }),
            EvaOptionTile(title: '4–5 приёмов', icon: Icons.bento_rounded, selected: false, onTap: () {
              Navigator.pop(ctx);
              _sendDietitianRequest(remaining, remP, remF, remC, remFiber, "3 основных блюда и 2 перекуса", "Составь меню на $remaining ккал (4–5 приёмов)");
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _sendDietitianRequest(int remaining, int remP, int remF, int remC, int remFiber, String planRule, String displayMessage) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String userName = 'пользователь';
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get(const GetOptions(source: Source.cache));
      userName = (userDoc.data()?['name'] ?? userName).toString();
    } catch (_) {}

    final String technicalPrompt = """Меня зовут $userName. Мне осталось съесть $remaining ккал. Моя цель сейчас: $planRule.

Остатки на сегодня:
- Белки: $remP г
- Жиры: $remF г
- Углеводы: $remC г
- Клетчатка: $remFiber г

Инструкция:
1. Если значение отрицательное (я перебрала норму), минимизируй этот нутриент.
2. Если прошу несколько приёмов пищи, распиши меню на все приёмы, разделив $remaining ккал между ними.
3. Закрой дефицит клетчатки (овощи, зелень).
4. Дай краткий понятный рецепт для каждого блюда.
5. Используй только простые продукты из обычного супермаркета.
6. В конце выведи общий список всех ингредиентов в формате JSON внутри тегов [SHOPPING_LIST].""";

    _openEva(displayMessage, technicalPrompt);
  }

  void _openEva(String display, String prompt) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AIChatScreen(botType: 'dietitian', initialDisplayMessage: display, initialTechnicalPrompt: prompt)),
    );
  }

  // ---------------------------------------------------------------------------
  // Редактирование нормы
  // ---------------------------------------------------------------------------

  void _showEditGoalDialog(int currentCals, int currentP, int currentF, int currentC) {
    final TextEditingController calsCtrl = TextEditingController(text: currentCals > 0 ? currentCals.toString() : '');
    final TextEditingController protCtrl = TextEditingController(text: currentP.toString());
    final TextEditingController fatCtrl = TextEditingController(text: currentF.toString());
    final TextEditingController carbsCtrl = TextEditingController(text: currentC.toString());
    bool isAutoUpdating = false;

    double pRatio = currentCals > 0 ? (currentP * 4) / currentCals : 0.3;
    double fRatio = currentCals > 0 ? (currentF * 9) / currentCals : 0.3;
    double cRatio = currentCals > 0 ? (currentC * 4) / currentCals : 0.4;

    void updateFromCals(String val) {
      if (isAutoUpdating) return;
      final int? newCals = int.tryParse(val);
      if (newCals != null && newCals > 0) {
        isAutoUpdating = true;
        protCtrl.text = ((newCals * pRatio) / 4).round().toString();
        fatCtrl.text = ((newCals * fRatio) / 9).round().toString();
        carbsCtrl.text = ((newCals * cRatio) / 4).round().toString();
        isAutoUpdating = false;
      }
    }

    void updateFromMacros(String _) {
      if (isAutoUpdating) return;
      final int p = int.tryParse(protCtrl.text) ?? 0;
      final int f = int.tryParse(fatCtrl.text) ?? 0;
      final int c = int.tryParse(carbsCtrl.text) ?? 0;
      final int total = (p * 4) + (f * 9) + (c * 4);
      isAutoUpdating = true;
      calsCtrl.text = total.toString();
      if (total > 0) {
        pRatio = (p * 4) / total;
        fRatio = (f * 9) / total;
        cRatio = (c * 4) / total;
      }
      isAutoUpdating = false;
    }

    Widget field(String label, TextEditingController ctrl, ValueChanged<String> onChanged, Color color) {
      return Expanded(
        child: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          ),
        ),
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Моя норма'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Измени калории — БЖУ пересчитаются сами. Или настрой макросы вручную.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 16),
              TextField(
                controller: calsCtrl,
                keyboardType: TextInputType.number,
                onChanged: updateFromCals,
                style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
                decoration: const InputDecoration(labelText: 'Калории', suffixText: 'ккал'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  field('Белки', protCtrl, updateFromMacros, EvaColors.protein),
                  const SizedBox(width: 8),
                  field('Жиры', fatCtrl, updateFromMacros, EvaColors.fat),
                  const SizedBox(width: 8),
                  field('Углеводы', carbsCtrl, updateFromMacros, EvaColors.carbs),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final c = int.tryParse(calsCtrl.text) ?? 0;
                if (c <= 0) return;
                DatabaseService().saveNutritionGoal({
                  'calories': c,
                  'protein': int.tryParse(protCtrl.text) ?? 0,
                  'fat': int.tryParse(fatCtrl.text) ?? 0,
                  'carbs': int.tryParse(carbsCtrl.text) ?? 0,
                });
                Navigator.pop(ctx);
                EvaSnack.show(context, 'Норма обновлена ✨', type: EvaSnackType.success);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _goalStream,
      builder: (context, goalSnapshot) {
        final goalData = goalSnapshot.data?.data();
        if (widget.mealsData != null) return _buildCard(goalData, widget.mealsData);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _meals(),
          builder: (context, mealSnapshot) => _buildCard(goalData, mealSnapshot.data?.data()),
        );
      },
    );
  }

  Widget _buildCard(Map<String, dynamic>? goalData, Map<String, dynamic>? mealsData) {
    final theme = Theme.of(context);
    final palette = context.eva;

    final int baseTarget = evaInt(goalData?['calories']);
    final int targetP = evaInt(goalData?['protein']);
    final int targetF = evaInt(goalData?['fat']);
    final int targetC = evaInt(goalData?['carbs']);

    int curCal = 0, curP = 0, curF = 0, curCarb = 0, curFiber = 0, bonus = 0;
    double healthSum = 0;
    int healthCount = 0;
    if (mealsData != null) {
      bonus = evaInt(mealsData['bonus_calories']);
      final List<dynamic> raw = mealsData['items'] is List ? mealsData['items'] : const [];
      for (final item in raw) {
        if (item is! Map) continue;
        if (widget.optimisticDeletedIds.contains(item['id'].toString())) continue;
        curCal += evaInt(item['calories']);
        curP += evaInt(item['protein']);
        curF += evaInt(item['fat']);
        curCarb += evaInt(item['carbs']);
        curFiber += evaInt(item['fiber']);
        if (item['health_score'] != null) {
          healthSum += evaDouble(item['health_score']);
          healthCount++;
        }
      }
    }
    final int target = baseTarget + bonus;
    final int remaining = target - curCal;
    final bool exceeded = target > 0 && curCal > target;
    final int health = healthCount > 0 ? (healthSum / healthCount).round() : 0;

    return EvaCard(
      onTap: () => _showEditGoalDialog(baseTarget, targetP, targetF, targetC),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EvaOverline('Питание сегодня')),
              EvaPressable(
                onTap: () => _askEvaForMealPlan(curCal, target, curP, targetP, curF, targetF, curCarb, targetC, curFiber),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(gradient: palette.hero, borderRadius: BorderRadius.circular(100)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Что съесть?', style: theme.textTheme.labelMedium?.copyWith(color: Colors.white)),
                      const SizedBox(width: 5),
                      const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              EvaProgressRing(
                progress: target > 0 ? curCal / target : 0,
                size: 118,
                stroke: 10,
                colors: exceeded ? [palette.lavender, palette.lavender] : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(EvaFormat.number(curCal), style: theme.textTheme.headlineMedium?.copyWith(height: 1)),
                    const SizedBox(height: 2),
                    Text(target > 0 ? 'из ${EvaFormat.number(target)}' : 'ккал', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target <= 0
                          ? 'Норма не задана'
                          : exceeded
                              ? 'Сверх нормы на ${EvaFormat.number(-remaining)}'
                              : 'Осталось ${EvaFormat.number(remaining)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target <= 0 ? 'Нажми, чтобы задать' : (exceeded ? 'Ничего страшного — завтра новый день ✨' : 'ккал до дневной нормы'),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (health > 0) EvaPill(text: 'Польза $health/10', icon: Icons.favorite_rounded, color: palette.sage),
                        if (bonus > 0) EvaPill(text: '+$bonus бонус', icon: Icons.celebration_rounded, color: palette.gold),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: EvaMacroBar(label: 'Белки', current: curP, target: targetP, color: EvaColors.protein)),
              const SizedBox(width: 10),
              Expanded(child: EvaMacroBar(label: 'Жиры', current: curF, target: targetF, color: EvaColors.fat)),
              const SizedBox(width: 10),
              Expanded(child: EvaMacroBar(label: 'Углеводы', current: curCarb, target: targetC, color: EvaColors.carbs)),
              const SizedBox(width: 10),
              Expanded(child: EvaMacroBar(label: 'Клетчатка', current: curFiber, target: _targetFiber, color: EvaColors.fiber)),
            ],
          ),
        ],
      ),
    );
  }
}
