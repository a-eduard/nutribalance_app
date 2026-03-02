import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import 'ai_chat_screen.dart'; 

class NutritionStatsScreen extends StatefulWidget {
  const NutritionStatsScreen({super.key});

  @override
  State<NutritionStatsScreen> createState() => _NutritionStatsScreenState();
}

class _NutritionStatsScreenState extends State<NutritionStatsScreen> {
  String _selectedPeriod = 'День'; 
  
  String _getAIDietitianInsight(int maintenance, int consumed, int diff) {
    if (consumed == 0) return "Привет! Запиши свой первый прием пищи, и я посчитаю твой дефицит. 🍏";
    if (maintenance == 0) return "Попроси меня рассчитать твою норму калорий, чтобы я смог анализировать твой дефицит! 🤖";
    if (diff > 0) return "Супер! Твой дефицит составил $diff ккал от нормы поддержания. Жир горит, ты на верном пути! 🔥";
    if (diff == 0) return "Идеальный баланс! Ты питаешься ровно на поддержание веса. ⚖️";
    return "Внимание! Профицит ${diff.abs()} ккал. Если ты на массе — отличная работа! Если сушишься, стоит урезать угли. 💪";
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Детали питания', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, userSnap) {
              final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
              final int userBmr = (userData['bmr'] as num?)?.toInt() ?? 0;
              final int userMaintenance = (userData['maintenanceCalories'] as num?)?.toInt() ?? 0;
              final bool hasMaintenance = userMaintenance > 0;

              return StreamBuilder<DocumentSnapshot>(
                stream: DatabaseService().getNutritionGoal(),
                builder: (context, goalSnapshot) {
                  final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
                  final int dailyTargetCals = goalData?['calories'] ?? 0;
                  
                  int daysMultiplier = 1;
                  if (_selectedPeriod == 'Неделя') daysMultiplier = 7;
                  if (_selectedPeriod == 'Месяц') daysMultiplier = 30;

                  final int targetCalsTotal = dailyTargetCals * daysMultiplier;
                  final int bmrTotal = userBmr * daysMultiplier;
                  final int maintenanceTotal = userMaintenance * daysMultiplier;

                  final logicalNow = DateTime.now().subtract(const Duration(hours: 3));
                  DateTime startDate = DateTime(logicalNow.year, logicalNow.month, logicalNow.day);
                  if (_selectedPeriod == 'Неделя') startDate = startDate.subtract(const Duration(days: 6));
                  if (_selectedPeriod == 'Месяц') startDate = startDate.subtract(const Duration(days: 29));
                  
                  final startTs = Timestamp.fromDate(startDate.add(const Duration(hours: 3)));

                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals')
                        .where('date', isGreaterThanOrEqualTo: startTs).snapshots(),
                    builder: (context, mealsSnapshot) {
                      int currentCals = 0; 
                      if (mealsSnapshot.hasData) {
                        for (var doc in mealsSnapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          currentCals += (data['calories'] as num?)?.toInt() ?? 0;
                        }
                      }

                      int diff = 0;
                      String diffLabel = 'Осталось';
                      Color diffColor = Colors.grey;

                      if (hasMaintenance) {
                        diff = maintenanceTotal - currentCals;
                        if (diff > 0) {
                          diffLabel = 'Текущий Дефицит';
                          diffColor = const Color(0xFF9CD600);
                        } else if (diff < 0) {
                          diffLabel = 'Текущий Профицит';
                          diffColor = Colors.redAccent;
                        } else {
                          diffLabel = 'Идеальный баланс';
                          diffColor = const Color(0xFF9CD600);
                        }
                      } else {
                        diff = targetCalsTotal - currentCals;
                        if (diff < 0) diffColor = Colors.redAccent;
                      }

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                              child: ToggleButtons(
                                isSelected: [_selectedPeriod == 'День', _selectedPeriod == 'Неделя', _selectedPeriod == 'Месяц'],
                                onPressed: (index) {
                                  setState(() {
                                    if (index == 0) _selectedPeriod = 'День';
                                    if (index == 1) _selectedPeriod = 'Неделя';
                                    if (index == 2) _selectedPeriod = 'Месяц';
                                  });
                                },
                                color: Colors.grey,
                                selectedColor: Colors.black,
                                fillColor: const Color(0xFF9CD600),
                                borderRadius: BorderRadius.circular(12),
                                constraints: BoxConstraints(minHeight: 40, minWidth: (MediaQuery.of(context).size.width - 36) / 3),
                                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                children: const [Text('ДЕНЬ'), Text('7 ДНЕЙ'), Text('30 ДНЕЙ')],
                              ),
                            ),
                            const SizedBox(height: 24),

                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF9CD600).withOpacity(0.3))),
                              child: Column(
                                children: [
                                  _buildStatRow('Базовый обмен (BMR)', userBmr > 0 ? '$bmrTotal ккал' : 'Не рассчитан'),
                                  const Divider(color: Colors.white10, height: 24),
                                  _buildStatRow('Поддержание веса', hasMaintenance ? '$maintenanceTotal ккал' : 'Не рассчитано'),
                                  const Divider(color: Colors.white10, height: 24),
                                  _buildStatRow('Цель из профиля', targetCalsTotal > 0 ? '$targetCalsTotal ккал' : 'Не задана'),
                                  const Divider(color: Colors.white10, height: 24),
                                  _buildStatRow('Употреблено калорий', '$currentCals ккал', valueColor: Colors.white),
                                  const Divider(color: Colors.white10, height: 24),
                                  _buildStatRow(
                                    diffLabel, 
                                    diff == 0 && hasMaintenance ? '0 ккал' : '${diff.abs()} ккал', 
                                    valueColor: diffColor,
                                    isBold: true
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            const Text('Сводка от ИИ-Нутрициолога', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF9CD600).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.auto_awesome, color: Color(0xFF9CD600), size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(_getAIDietitianInsight(maintenanceTotal, currentCals, diff), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 14, fontStyle: FontStyle.italic, height: 1.4))),
                                ],
                              ),
                            ),

                            if (!hasMaintenance)
                              Padding(
                                padding: const EdgeInsets.only(top: 24.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    // ИСПРАВЛЕНИЕ: onPressed вместо onTap
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF9CD600).withOpacity(0.1),
                                      side: const BorderSide(color: Color(0xFF9CD600)),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    icon: const Icon(Icons.auto_awesome, color: Color(0xFF9CD600)),
                                    label: const Text("Рассчитать норму с ИИ", style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 16)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                }
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color valueColor = Colors.grey, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value, style: TextStyle(color: valueColor, fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}