import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../ui_widgets.dart'; 
import '../workout_session_screen.dart'; 
import '../services/database_service.dart'; // Не забудь этот импорт!

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  // Метод для показа диалога подтверждения
  void _confirmDelete(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Удалить запись?", style: TextStyle(color: Colors.white)),
        content: const Text("Эту тренировку нельзя будет восстановить.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            child: const Text("Отмена", style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text("Удалить", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx); // Закрываем окно
              await DatabaseService().deleteHistoryItem(docId); // Удаляем
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text("Нет доступа"));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("История"), 
        backgroundColor: Colors.transparent, 
        automaticallyImplyLeading: false
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
            return const Center(child: Text("История пуста 🌑", style: TextStyle(color: Colors.grey)));
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final name = data['workoutName'] ?? "Тренировка";
              final tonnage = data['tonnage'] ?? 0;
              final timestamp = data['completedAt'] as Timestamp?;
              final dateStr = timestamp != null 
                  ? DateFormat('dd.MM HH:mm').format(timestamp.toDate()) 
                  : "";

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PremiumGlassCard(
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(dateStr, style: const TextStyle(color: Colors.grey)),
                      iconColor: const Color(0xFFCCFF00),
                      collapsedIconColor: Colors.white,
                      
                      // --- ПРАВАЯ ЧАСТЬ: ТОННАЖ + РЕДАКТИРОВАТЬ + УДАЛИТЬ ---
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${(tonnage / 1000).toStringAsFixed(1)} т", 
                            style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)
                          ),
                          const SizedBox(width: 8),
                          // Кнопка Edit
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white54, size: 20),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => WorkoutSessionScreen(
                                    workoutTitle: name,
                                    existingDocId: doc.id,
                                    existingData: data,
                                  ),
                                ),
                              );
                            },
                          ),
                          // Кнопка Delete
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _confirmDelete(context, doc.id),
                          ),
                        ],
                      ),
                      
                      children: (data['exercises'] as List? ?? []).map<Widget>((ex) {
                        return ListTile(
                          dense: true,
                          title: Text(ex['name'], style: const TextStyle(color: Colors.white70)),
                          trailing: Text(
                            "${(ex['sets'] as List).length} подх.", 
                            style: const TextStyle(color: Color(0xFFCCFF00))
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