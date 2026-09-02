import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/database_service.dart';
import '../../screens/ai_chat_screen.dart';

class NutritionSummaryCard extends StatefulWidget {
  final String uid;
  final String docId;
  final Set<String> optimisticDeletedIds;

  const NutritionSummaryCard({
    super.key,
    required this.uid,
    required this.docId,
    required this.optimisticDeletedIds,
  });

  @override
  State<NutritionSummaryCard> createState() => _NutritionSummaryCardState();
}

class _NutritionSummaryCardState extends State<NutritionSummaryCard> {

  Future<void> _askEvaForMealPlan(BuildContext context, int consumed, int norm, int curP, int targetP, int curF, int targetF, int curC, int targetC, int curFiber, int targetFiber) async {
    int remaining = norm - consumed;
    int remP = targetP - curP;
    int remF = targetF - curF;
    int remC = targetC - curC;
    int remFiber = targetFiber - curFiber;
    final theme = Theme.of(context);

    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Твоя норма уже выполнена! ✨"), backgroundColor: theme.colorScheme.primary));
      return;
    }

    if (remaining < 500) {
      _sendDietitianRequest(context, remaining, remP, remF, remC, remFiber, "1 легкий прием пищи или перекус", "Что мне съесть на $remaining ккал?");
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Как распределим $remaining ккал? 🥗", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 20),
                _buildMealOption(ctx, "1 плотный прием", "1 основной прием пищи", remaining, remP, remF, remC, remFiber),
                const SizedBox(height: 12),
                _buildMealOption(ctx, "2-3 приема", "2 основных блюда и 1 перекус", remaining, remP, remF, remC, remFiber),
                const SizedBox(height: 12),
                _buildMealOption(ctx, "4-5 приемов", "3 основных блюда и 2 перекуса", remaining, remP, remF, remC, remFiber),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildMealOption(BuildContext context, String title, String promptRule, int remaining, int remP, int remF, int remC, int remFiber) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: theme.scaffoldBackgroundColor, foregroundColor: theme.colorScheme.onSurface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2)))),
        onPressed: () {
          Navigator.pop(context);
          _sendDietitianRequest(context, remaining, remP, remF, remC, remFiber, promptRule, "Составь меню на $remaining ккал ($title)");
        },
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Future<void> _sendDietitianRequest(BuildContext context, int remaining, int remP, int remF, int remC, int remFiber, String planRule, String displayMessage) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userName = userDoc.data()?['name'] ?? 'пользователь';

    String technicalPrompt = """Привет! Меня зовут $userName. Обращайся ко мне по этому имени. 
Мне осталось съесть $remaining ккал. Моя цель сейчас: $planRule.

Анализ моего рациона на сегодня (ОСТАТКИ):
- Белки: осталось добрать $remP г
- Жиры: осталось добрать $remF г
- Углеводы: осталось добрать $remC г
- Клетчатка: осталось добрать $remFiber г

ИНСТРУКЦИЯ ДЛЯ ТЕБЯ:
1. Изучи остатки. Если значение отрицательное (я перебрала норму), минимизируй этот нутриент.
2. Если я прошу несколько приемов пищи (например, 4-5), ОБЯЗАТЕЛЬНО распиши меню на все эти приемы, разбив $remaining ккал между ними.
3. Закрой дефицит клетчатки (овощи, зелень).
4. Дай краткий, но понятный рецепт для КАЖДОГО блюда из предложенного меню.
5. ПРОДУКТЫ: Используй ТОЛЬКО простые, доступные ингредиенты из обычных супермаркетов. Заменяй экзотику на гречку, картофель, морковь, капусту, обычную зелень, курицу, яйца и т.д.
6. В самом конце выведи общий список ВСЕХ ингредиентов для всех блюд в едином формате JSON внутри тегов [SHOPPING_LIST].""";

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AIChatScreen(botType: 'dietitian', initialDisplayMessage: displayMessage, initialTechnicalPrompt: technicalPrompt)));
    }
  }

  void _showEditGoalDialog(int currentCals, int currentP, int currentF, int currentC) {
    final TextEditingController calsCtrl = TextEditingController(text: currentCals.toString());
    final TextEditingController protCtrl = TextEditingController(text: currentP.toString());
    final TextEditingController fatCtrl = TextEditingController(text: currentF.toString());
    final TextEditingController carbsCtrl = TextEditingController(text: currentC.toString());
    bool isAutoUpdating = false;
    bool isSaving = false;
    final theme = Theme.of(context);

    double pRatio = currentCals > 0 ? (currentP * 4) / currentCals : 0.3;
    double fRatio = currentCals > 0 ? (currentF * 9) / currentCals : 0.3;
    double cRatio = currentCals > 0 ? (currentC * 4) / currentCals : 0.4;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          void updateFromCals(String val) {
            if (isAutoUpdating) return;
            int? newCals = int.tryParse(val);
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
            int p = int.tryParse(protCtrl.text) ?? 0;
            int f = int.tryParse(fatCtrl.text) ?? 0;
            int c = int.tryParse(carbsCtrl.text) ?? 0;
            isAutoUpdating = true;
            calsCtrl.text = ((p * 4) + (f * 9) + (c * 4)).toString();
            int newCals = int.tryParse(calsCtrl.text) ?? 1;
            pRatio = (p * 4) / newCals;
            fRatio = (f * 9) / newCals;
            cRatio = (c * 4) / newCals;
            isAutoUpdating = false;
          }

          Widget buildField(String label, TextEditingController ctrl, Function(String) onChanged, Color color) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextField(
                  controller: ctrl, keyboardType: TextInputType.number, onChanged: onChanged,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2))),
                  cursorColor: color,
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: theme.colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Ваша норма', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Измените калории, и БЖУ пересчитаются сами. Или настройте макросы вручную.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                TextField(
                  controller: calsCtrl, keyboardType: TextInputType.number, onChanged: updateFromCals,
                  style: TextStyle(color: theme.colorScheme.primary, fontSize: 32, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(labelText: 'Калории', labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)), suffixText: 'ккал', suffixStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    buildField('Белки (г)', protCtrl, updateFromMacros, theme.colorScheme.secondary),
                    buildField('Жиры (г)', fatCtrl, updateFromMacros, const Color(0xFFE5C158)),
                    buildField('Углеводы (г)', carbsCtrl, updateFromMacros, const Color(0xFF89CFF0)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: isSaving ? null : () async {
                  final c = int.tryParse(calsCtrl.text) ?? 0;
                  final p = int.tryParse(protCtrl.text) ?? 0;
                  final f = int.tryParse(fatCtrl.text) ?? 0;
                  final cb = int.tryParse(carbsCtrl.text) ?? 0;
                  if (c > 0) {
                    setStateDialog(() => isSaving = true);
                    try {
                      await DatabaseService().saveNutritionGoal({'calories': c, 'protein': p, 'fat': f, 'carbs': cb});
                      if (context.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setStateDialog(() => isSaving = false);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent));
                    }
                  }
                },
                child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMacroBar(String label, int current, int target, Color activeColor, ThemeData theme) {
    double progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: activeColor),
            duration: const Duration(milliseconds: 500),
            builder: (context, color, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(value: progress, backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1), valueColor: AlwaysStoppedAnimation<Color>(color ?? theme.colorScheme.primary), minHeight: 8),
              );
            },
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '$current', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w800)),
                TextSpan(text: '/$target г', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('nutrition_goal').doc('current').snapshots(includeMetadataChanges: true),
      builder: (context, goalSnapshot) {
        if (goalSnapshot.hasError) return const SizedBox.shrink();
        final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
        int targetCals = goalData?['calories'] ?? 0;
        final int targetP = goalData?['protein'] ?? 0;
        final int targetF = goalData?['fat'] ?? 0;
        final int targetC = goalData?['carbs'] ?? 0;
        final int targetFiber = 25;

        return StreamBuilder<DocumentSnapshot>(
          key: ValueKey('dash_${widget.docId}'),
          stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('meals').doc(widget.docId).snapshots(includeMetadataChanges: true),
          builder: (context, mealSnapshot) {
            if (mealSnapshot.hasError) return const Center(child: Text("Ошибка загрузки данных"));

            int curC = 0, curP = 0, curF = 0, curCarb = 0, bonusCals = 0, curFiber = 0;
            double totalHealthScore = 0;
            int mealsCount = 0;

            if (mealSnapshot.hasData && mealSnapshot.data!.exists) {
              final data = mealSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              bonusCals = (data['bonus_calories'] as num?)?.toInt() ?? 0;
              curC = bonusCals;
              final List<dynamic> rawItems = data['items'] ?? [];
              final List<dynamic> activeItems = rawItems.where((item) => !widget.optimisticDeletedIds.contains(item['id'].toString())).toList();

              for (var item in activeItems) {
                if (item is Map<String, dynamic>) {
                  curC += (item['calories'] as num?)?.toInt() ?? 0;
                  curP += (item['protein'] as num?)?.toInt() ?? 0;
                  curF += (item['fat'] as num?)?.toInt() ?? 0;
                  curCarb += (item['carbs'] as num?)?.toInt() ?? 0;
                  curFiber += (item['fiber'] as num?)?.toInt() ?? 0;
                  if (item.containsKey('health_score') && item['health_score'] != null) {
                    totalHealthScore += (item['health_score'] as num).toDouble();
                    mealsCount++;
                  }
                }
              }
            }

            final int avgHealthScore = mealsCount > 0 ? (totalHealthScore / mealsCount).round() : 0;
            targetCals += bonusCals;
            bool isExceeded = targetCals > 0 && curC > targetCals;
            final Color activeColor = isExceeded ? const Color(0xFFB6A6CA) : theme.colorScheme.primary;

            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                final int baseTargetCals = goalData?['calories'] ?? 0;
                _showEditGoalDialog(baseTargetCals, targetP, targetF, targetC);
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('КАЛОРИИ ЗА СЕГОДНЯ', style: TextStyle(color: activeColor, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)))),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (bonusCals > 0) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)), child: Text("+$bonusCals бонус", style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold))),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _askEvaForMealPlan(context, curC, targetCals, curP, targetP, curF, targetF, curCarb, targetC, curFiber, targetFiber);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))]),
                                  child: const Row(children: [Text("Что съесть?", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)), SizedBox(width: 6), Icon(Icons.auto_awesome, color: Colors.white, size: 16)]),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('$curC', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : theme.colorScheme.onSurface, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    final int baseTargetCals = goalData?['calories'] ?? 0;
                                    _showEditGoalDialog(baseTargetCals, targetP, targetF, targetC);
                                  },
                                  child: Row(children: [Text(' / $targetCals ккал', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 18, fontWeight: FontWeight.w600)), const SizedBox(width: 4), Icon(Icons.edit_rounded, color: theme.colorScheme.onSurfaceVariant, size: 16)]),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (mealsCount > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.favorite, color: theme.colorScheme.primary, size: 12), const SizedBox(width: 4), Text("Польза $avgHealthScore/10", style: TextStyle(color: theme.colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold))])) else const Padding(padding: EdgeInsets.only(bottom: 6.0), child: Icon(Icons.bar_chart, color: Color(0xFFE5E5EA), size: 24)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(isExceeded ? 'Сверх нормы ✨' : 'Калорий употреблено', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildMacroBar("Белки", curP, targetP, theme.colorScheme.secondary, theme), const SizedBox(width: 8),
                        _buildMacroBar("Жиры", curF, targetF, const Color(0xFFE5C158), theme), const SizedBox(width: 8),
                        _buildMacroBar("Углеводы", curCarb, targetC, const Color(0xFF89CFF0), theme), const SizedBox(width: 8),
                        _buildMacroBar("Клетчатка", curFiber, targetFiber, Colors.green[300] ?? Colors.green, theme),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}