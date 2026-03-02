import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkoutStatsScreen extends StatefulWidget {
  const WorkoutStatsScreen({super.key});

  @override
  State<WorkoutStatsScreen> createState() => _WorkoutStatsScreenState();
}

class _WorkoutStatsScreenState extends State<WorkoutStatsScreen> {
  String _selectedPeriod = 'Неделя'; 

  // Локальная заглушка. Позже заменим на реальный вызов API Gemini с кэшированием!
  String _getAITrainerMotivation(double tonnage, int workoutsCount) {
    if (workoutsCount == 0) return "Время размяться! Жду тебя на тренировке. 💪";
    if (tonnage > 100) return "Ты просто машина! $workoutsCount тренировок и огромный объем. Так держать! 🔥";
    if (tonnage > 50) return "Отличный темп! Мышцы растут, когда ты работаешь. Продолжаем! 🚀";
    return "Хорошее начало! Главное — регулярность. Жми дальше! 🏋️‍♂️";
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Статистика тренировок', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
              double totalVolumeKg = (userData['totalVolumeKg'] ?? 0.0).toDouble();
              double totalTons = totalVolumeKg / 1000;

              int currentLevel = 0;
              if (totalTons < 100) { currentLevel = 0; } 
              else if (totalTons < 250) { currentLevel = 1; } 
              else if (totalTons < 450) { currentLevel = 2; } 
              else if (totalTons < 700) { currentLevel = 3; } 
              else if (totalTons < 1000) { currentLevel = 4; } 
              else { currentLevel = 5; }

              int daysToSubtract = 7;
              if (_selectedPeriod == 'Месяц') daysToSubtract = 30;
              if (_selectedPeriod == 'Год') daysToSubtract = 365;

              final startDate = DateTime.now().subtract(Duration(days: daysToSubtract));
              final startTs = Timestamp.fromDate(startDate);

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('history')
                    .where('date', isGreaterThanOrEqualTo: startTs).snapshots(),
                builder: (context, historySnap) {
                  double periodVolumeKg = 0;
                  int workoutsCount = 0;

                  if (historySnap.hasData) {
                    workoutsCount = historySnap.data!.docs.length;
                    for (var doc in historySnap.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      periodVolumeKg += (data['tonnage'] ?? 0).toDouble();
                    }
                  }
                  double periodTons = periodVolumeKg / 1000;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                        child: ToggleButtons(
                          isSelected: [_selectedPeriod == 'Неделя', _selectedPeriod == 'Месяц', _selectedPeriod == 'Год'],
                          onPressed: (index) {
                            setState(() {
                              if (index == 0) _selectedPeriod = 'Неделя';
                              if (index == 1) _selectedPeriod = 'Месяц';
                              if (index == 2) _selectedPeriod = 'Год';
                            });
                          },
                          color: Colors.grey,
                          selectedColor: Colors.black,
                          fillColor: const Color(0xFF9CD600),
                          borderRadius: BorderRadius.circular(12),
                          constraints: BoxConstraints(minHeight: 40, minWidth: (MediaQuery.of(context).size.width - 36) / 3),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          children: const [Text('7 ДНЕЙ'), Text('30 ДНЕЙ'), Text('ГОД')],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Блок статистики
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF9CD600).withOpacity(0.3))),
                        child: Column(
                          children: [
                            _buildStatRow('Текущий Рейтинг', 'Уровень $currentLevel', valueColor: const Color(0xFF9CD600), isBold: true),
                            const Divider(color: Colors.white10, height: 24),
                            _buildStatRow('Количество тренировок', '$workoutsCount'),
                            const Divider(color: Colors.white10, height: 24),
                            _buildStatRow('Тоннаж за период', '${periodTons.toStringAsFixed(1)} тонн', valueColor: Colors.white, isBold: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Мотивация ИИ
                      const Text('Анализ от ИИ-Тренера', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFF9CD600).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.auto_awesome, color: Color(0xFF9CD600), size: 24),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_getAITrainerMotivation(periodTons, workoutsCount), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 14, fontStyle: FontStyle.italic, height: 1.4))),
                          ],
                        ),
                      ),
                    ],
                  );
                }
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color valueColor = Colors.white, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(value, style: TextStyle(color: valueColor, fontSize: isBold ? 18 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}