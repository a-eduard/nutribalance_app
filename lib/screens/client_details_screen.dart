import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'p2p_chat_screen.dart';
import 'assign_workout_screen.dart';
import '../widgets/volume_chart.dart'; // График тренировочного объема

class ClientDetailsScreen extends StatelessWidget {
  final String clientId;
  final String clientName;

  const ClientDetailsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          clientName.toUpperCase(), 
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // ================= БЛОК А: ИНФО О КЛИЕНТЕ =================
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(clientId).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      
                      return Column(
                        children: [
                          Center(
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF1C1C1E),
                                border: Border.all(color: const Color(0xFFCCFF00), width: 2),
                              ),
                              child: const Icon(Icons.person, size: 40, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(child: _buildInfoTile("ВЕС", "${data['weight'] ?? '—'} кг")),
                              const SizedBox(width: 12),
                              Expanded(child: _buildInfoTile("РОСТ", "${data['height'] ?? '—'} см")),
                              const SizedBox(width: 12),
                              Expanded(child: _buildInfoTile("ВОЗРАСТ", "${data['age'] ?? '—'}")),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 40),

                  // ================= БЛОК Б: ТЕКУЩИЕ ПРОГРАММЫ =================
                  const Text("НАЗНАЧЕННЫЕ ПРОГРАММЫ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(clientId)
                        .collection('assigned_workouts')
                        .orderBy('date', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Text("Нет назначенных программ", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic));
                      }
                      
                      return Column(
                        children: snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              title: Text(data['name'] ?? 'Программа', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              subtitle: Text("${(data['exercises'] as List?)?.length ?? 0} упражнений", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Color(0xFFCCFF00)),
                                    onPressed: () {
                                      Navigator.push(context, MaterialPageRoute(
                                        builder: (_) => AssignWorkoutScreen(
                                          clientId: clientId, 
                                          clientName: clientName, 
                                          existingWorkoutId: doc.id, 
                                          existingWorkoutData: data
                                        )
                                      ));
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () {
                                      FirebaseFirestore.instance.collection('users').doc(clientId).collection('assigned_workouts').doc(doc.id).delete();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 40),

                  // ================= БЛОК В: СТАТИСТИКА + ГРАФИК + ИСТОРИЯ =================
                  const Text("СТАТИСТИКА И ИСТОРИЯ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  
                  // ОДИН StreamBuilder для истории, графика и метрик (оптимизация чтений)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(clientId)
                        .collection('history')
                        .orderBy('date', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            "Клиент еще не провел ни одной тренировки.",
                            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      // Расчет метрик
                      final docs = snapshot.data!.docs;
                      final int totalWorkouts = docs.length;
                      
                      final lastWorkoutData = docs.first.data() as Map<String, dynamic>;
                      final Timestamp? timestamp = lastWorkoutData['date'] as Timestamp?;
                      final DateTime lastWorkoutDate = timestamp?.toDate() ?? DateTime.now();
                      
                      final int daysAgo = DateTime.now().difference(lastWorkoutDate).inDays;
                      final bool isInactive = daysAgo > 7;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. КАРТОЧКИ МЕТРИК
                          Row(
                            children: [
                              // КАРТОЧКА: Всего тренировок
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1E),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.fitness_center, color: Color(0xFFCCFF00), size: 28),
                                      const SizedBox(height: 12),
                                      Text(
                                        totalWorkouts.toString(),
                                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        "Всего тренировок",
                                        style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // КАРТОЧКА: Последняя активность
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C1C1E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: isInactive ? Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5) : null,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.timer, 
                                        color: isInactive ? Colors.redAccent : const Color(0xFFCCFF00), 
                                        size: 28
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        daysAgo == 0 ? 'Сегодня' : '$daysAgo дней назад',
                                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        "Был на тренировке",
                                        style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // 2. ГРАФИК ОБЪЕМА
                          VolumeChart(historyDocs: docs),
                          const SizedBox(height: 24),

                          // 3. СПИСОК ИСТОРИИ (показываем последние 10 тренировок)
                          const Text("ПОСЛЕДНИЕ ТРЕНИРОВКИ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          ...docs.take(10).map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final date = data['date'] as Timestamp?;
                            final dateStr = date != null ? "${date.toDate().day.toString().padLeft(2,'0')}.${date.toDate().month.toString().padLeft(2,'0')}.${date.toDate().year}" : "Дата неизвестна";
                            final exercises = data['exercises'] as List<dynamic>? ?? [];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(data['workoutName'] ?? 'Тренировка', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                                      Text(dateStr, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Вывод реальных весов и повторов
                                  ...exercises.map((ex) {
                                    final exName = ex['name'] ?? 'Упр.';
                                    final sets = ex['sets'] as List<dynamic>? ?? [];
                                    
                                    final setsStr = sets.map((s) {
                                      final w = s['weight']?.toString() ?? '0';
                                      final r = s['reps']?.toString() ?? '0';
                                      return "${w}кг x $r";
                                    }).join(', ');

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: Text("• $exName: $setsStr", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    );
                                  }),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 40), // Отступ для прокрутки в самом низу
                ],
              ),
            ),
          ),
          
          // ================= КНОПКИ ДЕЙСТВИЙ (ЗАКРЕПЛЕНЫ ВНИЗУ) =================
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Color(0xFF1C1C1E), width: 2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: clientId, otherUserName: clientName))),
                    icon: const Icon(Icons.chat_bubble, color: Colors.black, size: 20),
                    label: const Text("НАПИСАТЬ В ЧАТ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCCFF00), 
                      foregroundColor: Colors.black, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignWorkoutScreen(clientId: clientId, clientName: clientName))),
                    icon: const Icon(Icons.add_task, color: Color(0xFFCCFF00), size: 20),
                    label: const Text("НАЗНАЧИТЬ ПРОГРАММУ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.0)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C1C1E), 
                      foregroundColor: const Color(0xFFCCFF00), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFCCFF00), width: 1.5)),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Вспомогательный виджет для Блока А
  Widget _buildInfoTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}