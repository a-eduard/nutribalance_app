import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/database_service.dart';

class NutritionSummaryCard extends StatelessWidget {
  const NutritionSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: DatabaseService().getNutritionGoal(),
      builder: (context, goalSnapshot) {
        // === БРОНЕБОЙНАЯ ЗАЩИТА ПОТОКА ===
        if (goalSnapshot.hasError) return const SizedBox.shrink();
        
        final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
        final int targetCals = goalData?['calories'] ?? 0;
        final int targetP = goalData?['protein'] ?? 0;
        final int targetF = goalData?['fat'] ?? 0;
        final int targetC = goalData?['carbs'] ?? 0;
        final int targetFiber = 25; // Цель по клетчатке

        return StreamBuilder<DocumentSnapshot>(
          stream: DatabaseService().getTodayMealsDoc(),
          builder: (context, mealSnapshot) {
            // === БРОНЕБОЙНАЯ ЗАЩИТА ПОТОКА ===
            if (mealSnapshot.hasError) return const Center(child: Text("Ошибка загрузки данных"));

            int curC = 0, curP = 0, curF = 0, curCarb = 0, curFiber = 0;
            double totalHealthScore = 0;
            int mealsCount = 0;

            if (mealSnapshot.hasData && mealSnapshot.data!.exists) {
              final data = mealSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              curC = (data['calories'] as num?)?.toInt() ?? 0;
              curP = (data['protein'] as num?)?.toInt() ?? 0;
              curF = (data['fat'] as num?)?.toInt() ?? 0;
              curCarb = (data['carbs'] as num?)?.toInt() ?? 0;
              curFiber = (data['fiber'] as num?)?.toInt() ?? 0;
              
              // === БЕЗОПАСНЫЙ ПАРСИНГ ИНДЕКСА ПОЛЬЗЫ ===
              final List<dynamic> items = data['items'] ?? [];
              for (var item in items) {
                if (item is Map<String, dynamic>) {
                  if (item.containsKey('health_score') && item['health_score'] != null) {
                    totalHealthScore += (item['health_score'] as num).toDouble();
                    mealsCount++;
                  }
                }
              }
            }

            final int avgHealthScore = mealsCount > 0 ? (totalHealthScore / mealsCount).round() : 0;
            int leftCals = targetCals - curC;
            double progress = targetCals > 0 ? (curC / targetCals).clamp(0.0, 1.0) : 0;
            
            bool isExceeded = targetCals > 0 && curC > targetCals;
            final Color activeColor = isExceeded ? const Color(0xFFB6A6CA) : const Color(0xFFB76E79); 
            final Color textColor = const Color(0xFF2D2D2D);
            final Color subTextColor = const Color(0xFF8E8E93);
            const Color roseGold = Color(0xFFB76E79); // Фирменный цвет для концепции Guilt-Free

            return Container(
              padding: const EdgeInsets.all(24), 
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24), 
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04), 
                    blurRadius: 24, 
                    offset: const Offset(0, 8)
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ПИТАНИЕ НА СЕГОДНЯ', style: TextStyle(color: activeColor, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                      // === ВЫВОД ИНДЕКСА ПОЛЬЗЫ В СТРОГОМ ROSE GOLD ЦВЕТЕ ===
                      if (mealsCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: roseGold.withValues(alpha: 0.1), 
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.favorite, color: roseGold, size: 12),
                              const SizedBox(width: 4),
                              Text("Польза $avgHealthScore/10", style: const TextStyle(color: roseGold, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      else
                        const Icon(Icons.bar_chart, color: Color(0xFFC7C7CC), size: 20), 
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('$curC', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : textColor, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                                // === РЕДАКТИРОВАНИЕ НОРМЫ КАЛОРИЙ ===
                                GestureDetector(
                                  onTap: () {
                                    final TextEditingController ctrl = TextEditingController(text: targetCals.toString());
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        title: const Text('Изменить норму', style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w900)),
                                        content: TextField(
                                          controller: ctrl,
                                          keyboardType: TextInputType.number,
                                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(suffixText: 'ккал', focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFB76E79), width: 2))),
                                          cursorColor: const Color(0xFFB76E79),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold))),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB76E79), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                            onPressed: () async {
                                              final val = int.tryParse(ctrl.text.trim());
                                              if (val != null && val > 0) {
                                                await DatabaseService().saveNutritionGoal({'calories': val});
                                                if (ctx.mounted) Navigator.pop(ctx);
                                              }
                                            },
                                            child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          )
                                        ],
                                      ),
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      Text(' / $targetCals ккал', style: TextStyle(color: subTextColor, fontSize: 16, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 4),
                                      Icon(Icons.edit_rounded, color: subTextColor, size: 16),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(isExceeded ? 'Сверх нормы ✨' : 'Калорий употреблено', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Б: $curP / $targetP', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Ж: $curF / $targetF', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('У: $curCarb / $targetC', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('К: $curFiber / $targetFiber', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20), 
                  TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: activeColor),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, color, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: const Color(0xFFF9F9F9),
                          valueColor: AlwaysStoppedAnimation<Color>(color ?? const Color(0xFFB76E79)), 
                          minHeight: 8, 
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}