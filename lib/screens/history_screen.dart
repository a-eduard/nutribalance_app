import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../ui_widgets.dart'; // Для PremiumGlassCard

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text("Нет доступа"));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("История тренировок"),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false, // Убираем стрелку назад, т.к. это таб
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('history')
            .orderBy('completedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.white.withOpacity(0.1)),
                  const SizedBox(height: 16),
                  const Text("История пуста 🌑", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final name = data['workoutName'] ?? "Тренировка";
              final tonnage = data['tonnage'] ?? 0;
              final timestamp = data['completedAt'] as Timestamp?;
              final dateStr = timestamp != null 
                  ? DateFormat('dd.MM.yyyy HH:mm').format(timestamp.toDate()) 
                  : "Неизвестно";
              final exercises = data['exercises'] as List<dynamic>? ?? [];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PremiumGlassCard(
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      iconColor: const Color(0xFFCCFF00),
                      collapsedIconColor: Colors.grey,
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("${(tonnage / 1000).toStringAsFixed(1)} т", style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                          const Text("ТОННАЖ", style: TextStyle(color: Colors.grey, fontSize: 8)),
                        ],
                      ),
                      children: exercises.map<Widget>((ex) {
                        final sets = ex['sets'] as List<dynamic>? ?? [];
                        // Собираем строку типа "100x10, 100x10"
                        String setDetails = sets.map((s) => "${s['weight']}x${s['reps']}").join(", ");
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.check, size: 14, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text("${ex['name']}:", style: const TextStyle(color: Colors.white70)),
                              ),
                              Text(setDetails, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}