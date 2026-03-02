import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/database_service.dart';
import '../../screens/workout_stats_screen.dart'; 

class WorkoutProgressCard extends StatelessWidget {
  const WorkoutProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
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

        return StreamBuilder<QuerySnapshot>(
          stream: DatabaseService().getUserHistory(),
          builder: (context, historySnap) {
            double weeklyVolumeKg = 0;
            if (historySnap.hasData) {
              final weekAgo = DateTime.now().subtract(const Duration(days: 7));
              for (var doc in historySnap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final Timestamp? dateTs = data['date'];
                if (dateTs != null && dateTs.toDate().isAfter(weekAgo)) {
                  weeklyVolumeKg += (data['tonnage'] ?? 0).toDouble();
                }
              }
            }
            double weeklyTons = weeklyVolumeKg / 1000;

            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutStatsScreen())),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12), // Уменьшили внешний отступ
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12), // Уменьшили внутренний
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.bar_chart, color: Color(0xFF9CD600), size: 18), // Чуть меньше иконка
                            SizedBox(width: 6),
                            Text('ПРОГРЕСС ТРЕНИРОВОК', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                          ],
                        ),
                        Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 12),
                      ],
                    ),
                    const SizedBox(height: 10), // Было 16, стало компактнее
                    Row(
                      children: [
                        Expanded(child: _buildStatItem("Общий объем", "${totalTons.toStringAsFixed(1)} т", Icons.fitness_center)),
                        Container(width: 1, height: 35, color: Colors.white10),
                        Expanded(child: _buildStatItem("За 7 дней", "${weeklyTons.toStringAsFixed(1)} т", Icons.trending_up)),
                        Container(width: 1, height: 35, color: Colors.white10),
                        Expanded(child: _buildStatItem("Ваш рейтинг", "Рейтинг: $currentLevel", Icons.emoji_events)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), textAlign: TextAlign.center),
      ],
    );
  }
}