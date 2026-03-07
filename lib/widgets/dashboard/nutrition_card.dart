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
        final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
        final int targetCals = goalData?['calories'] ?? 0;
        final int targetP = goalData?['protein'] ?? 0;
        final int targetF = goalData?['fat'] ?? 0;
        final int targetC = goalData?['carbs'] ?? 0;

        return StreamBuilder<DocumentSnapshot>(
          stream: DatabaseService().getTodayMealsDoc(),
          builder: (context, mealSnapshot) {
            int curC = 0, curP = 0, curF = 0, curCarb = 0;
            if (mealSnapshot.hasData && mealSnapshot.data!.exists) {
              final data = mealSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              curC = (data['calories'] as num?)?.toInt() ?? 0;
              curP = (data['protein'] as num?)?.toInt() ?? 0;
              curF = (data['fat'] as num?)?.toInt() ?? 0;
              curCarb = (data['carbs'] as num?)?.toInt() ?? 0;
            }

            int leftCals = targetCals - curC;
            double progress = targetCals > 0 ? (curC / targetCals).clamp(0.0, 1.0) : 0;
            
            // GUILT-FREE ЛОГИКА
            bool isExceeded = targetCals > 0 && curC > targetCals;
            final Color accent = isExceeded ? const Color(0xFFB6A6CA) : const Color(0xFFB76E79); // Лавандовый вместо красного
            final Color textColor = const Color(0xFF2D2D2D);

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ПИТАНИЕ НА СЕГОДНЯ', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                      const Icon(Icons.bar_chart, color: Colors.grey, size: 18), 
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Меняем текст, если норма превышена
                          Text(isExceeded ? 'Норма выполнена ✨' : 'Осталось', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(isExceeded ? 'Баланс' : '${leftCals.abs()} ккал', style: TextStyle(color: textColor, fontSize: isExceeded ? 24 : 28, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Б: $curP / $targetP', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Ж: $curF / $targetF', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('У: $curCarb / $targetC', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16), 
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFF0F0F0),
                      valueColor: AlwaysStoppedAnimation<Color>(accent), // Становится лавандовым
                      minHeight: 8, 
                    ),
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