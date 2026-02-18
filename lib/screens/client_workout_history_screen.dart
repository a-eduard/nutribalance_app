import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/volume_chart.dart'; // Убедись, что путь к графику верный

class ClientWorkoutHistoryScreen extends StatelessWidget {
  final String clientId;
  final String clientName;

  const ClientWorkoutHistoryScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("ИСТОРИЯ ТРЕНИРОВОК", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            return const Center(
              child: Text("Клиент еще не провел ни одной тренировки.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
            );
          }

          final docs = snapshot.data!.docs;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // График объема (если он у тебя есть)
                VolumeChart(historyDocs: docs),
                const SizedBox(height: 32),

                const Text("ВЫПОЛНЕННЫЕ ПРОГРАММЫ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 16),
                
                ...docs.map((doc) {
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
                        ...exercises.map((ex) {
                          final exName = ex['name']?.toString() ?? 'Упр.';
                          final sets = ex['sets'] as List<dynamic>? ?? [];
                          final setsStr = sets.map((s) => "${s['weight'] ?? 0}кг x ${s['reps'] ?? 0}").join(', ');

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Text("• ${exName.tr()}: $setsStr", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          );
                        }),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}