import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'assign_workout_screen.dart';

class CoachClientProgramsScreen extends StatelessWidget {
  final String clientId;
  final String clientName;

  const CoachClientProgramsScreen({
    super.key, 
    required this.clientId, 
    required this.clientName
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text("Программы: $clientName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .collection('assigned_workouts')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 60, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  Text("Вы еще не отправляли программы", style: TextStyle(color: Colors.grey[400])),
                ],
              ),
            );
          }

          final programs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: programs.length,
            itemBuilder: (context, index) {
              final doc = programs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final String name = data['name'] ?? 'Без названия';
              final Timestamp? date = data['date'];
              final String dateStr = date != null ? "${date.toDate().day.toString().padLeft(2,'0')}.${date.toDate().month.toString().padLeft(2,'0')}.${date.toDate().year}" : "";
              final List exercises = data['exercises'] ?? [];

              return GestureDetector(
                onTap: () {
                  // Позволяем тренеру отредактировать отправленную программу
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AssignWorkoutScreen(
                    clientId: clientId,
                    clientName: clientName,
                    existingWorkoutId: doc.id,
                    existingWorkoutData: data,
                  )));
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9CD600).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fitness_center, color: Color(0xFF9CD600), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("${exercises.length} упражнений • $dateStr", style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit, color: Colors.grey, size: 20),
                    ],
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }
}