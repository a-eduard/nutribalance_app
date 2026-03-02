import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/database_service.dart';
import '../../screens/nutrition_stats_screen.dart';

class NutritionSummaryCard extends StatelessWidget {
  const NutritionSummaryCard({super.key});

  void _showEditSheet(BuildContext context, int c, int p, int f, int carb) {
    final calCtrl = TextEditingController(text: c.toString());
    final proCtrl = TextEditingController(text: p.toString());
    final fatCtrl = TextEditingController(text: f.toString());
    final carbCtrl = TextEditingController(text: carb.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // БЛОК 5: Заменен яркий фон на темный (0xFF1C1C1E)
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // БЛОК 5: Текст заголовка теперь лаймовый для контраста
            const Text("РЕДАКТИРОВАТЬ ЗА ДЕНЬ", style: TextStyle(color: Color(0xFF9CD600), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildField(calCtrl, "Ккал", Icons.local_fire_department)),
                const SizedBox(width: 12),
                Expanded(child: _buildField(proCtrl, "Белки", Icons.egg_alt)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildField(fatCtrl, "Жиры", Icons.opacity)),
                const SizedBox(width: 12),
                Expanded(child: _buildField(carbCtrl, "Углеводы", Icons.bakery_dining)),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9CD600), 
                  foregroundColor: Colors.black, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () async {
                  await DatabaseService().updateDailyNutritionManual(
                    int.tryParse(calCtrl.text) ?? 0,
                    int.tryParse(proCtrl.text) ?? 0,
                    int.tryParse(fatCtrl.text) ?? 0,
                    int.tryParse(carbCtrl.text) ?? 0,
                  );
                  Navigator.pop(ctx);
                },
                child: const Text("СОХРАНИТЬ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 12),
        prefixIcon: Icon(icon, color: const Color(0xFF9CD600), size: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: Colors.white10)
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), 
          borderSide: const BorderSide(color: Color(0xFF9CD600))
        ),
        filled: true,
        fillColor: Colors.black26,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: DatabaseService().getNutritionGoal(),
      builder: (context, goalSnapshot) {
        final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
        final int targetCals = goalData?['calories'] ?? 0;
        if (targetCals == 0) return const SizedBox.shrink();

        final int targetP = goalData?['protein'] ?? 0;
        final int targetF = goalData?['fat'] ?? 0;
        final int targetC = goalData?['carbs'] ?? 0;

        return StreamBuilder<QuerySnapshot>(
          stream: DatabaseService().getTodayMeals(),
          builder: (context, mealsSnapshot) {
            int curC = 0; 
            int curP = 0; 
            int curF = 0; 
            int curCarb = 0;

            if (mealsSnapshot.hasData && mealsSnapshot.data!.docs.isNotEmpty) {
              final now = DateTime.now();
              final todayId = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
              
              final docs = mealsSnapshot.data!.docs;
              final matchingDocs = docs.where((d) => d.id == todayId).toList();
              final todayDoc = matchingDocs.isNotEmpty ? matchingDocs.first : docs.first;

              final data = todayDoc.data() as Map<String, dynamic>;
              curC = (data['calories'] as num?)?.toInt() ?? 0;
              curP = (data['protein'] as num?)?.toInt() ?? 0;
              curF = (data['fat'] as num?)?.toInt() ?? 0;
              curCarb = (data['carbs'] as num?)?.toInt() ?? 0;
            }

            int leftCals = targetCals - curC;
            double progress = targetCals > 0 ? (curC / targetCals).clamp(0.0, 1.0) : 0;
            
            Color progressColor = leftCals < 0 ? Colors.redAccent : const Color(0xFF9CD600);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3), width: 1.5),
              ),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NutritionStatsScreen())),
                onLongPress: () => _showEditSheet(context, curC, curP, curF, curCarb),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.local_fire_department, color: Color(0xFF9CD600), size: 18),
                              SizedBox(width: 6),
                              Text('ПИТАНИЕ НА СЕГОДНЯ', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                            ],
                          ),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.edit, color: Colors.grey, size: 16),
                            onPressed: () => _showEditSheet(context, curC, curP, curF, curCarb),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(leftCals >= 0 ? 'Осталось' : 'Перебор', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              Text('${leftCals.abs()} ккал', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1)),
                            ],
                          ),
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8.0, 
                              children: [
                                Text('Б: $curP/$targetP', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                Text('Ж: $curF/$targetF', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                Text('У: $curCarb/$targetC', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8), 
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                          valueColor: AlwaysStoppedAnimation<Color>(progressColor), 
                          minHeight: 6, 
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}