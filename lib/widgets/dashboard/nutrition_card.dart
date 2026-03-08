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
            
            bool isExceeded = targetCals > 0 && curC > targetCals;
            final Color accent = isExceeded ? const Color(0xFFB6A6CA) : const Color(0xFFB76E79); 
            final Color textColor = const Color(0xFF2D2D2D);
            final Color subTextColor = const Color(0xFF8E8E93);

            return Container(
              padding: const EdgeInsets.all(24), // Увеличили воздух
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24), // Мягкие углы
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)) // Премиум тень
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ПИТАНИЕ НА СЕГОДНЯ', style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                      const Icon(Icons.bar_chart, color: Color(0xFFC7C7CC), size: 20), 
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isExceeded ? 'Норма выполнена ✨' : 'Осталось', style: TextStyle(color: subTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                          Text(isExceeded ? 'Баланс' : '${leftCals.abs()} ккал', style: TextStyle(color: textColor, fontSize: isExceeded ? 26 : 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Б: $curP / $targetP', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('Ж: $curF / $targetF', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('У: $curCarb / $targetC', style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20), 
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFF2F2F7),
                      valueColor: AlwaysStoppedAnimation<Color>(accent), 
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