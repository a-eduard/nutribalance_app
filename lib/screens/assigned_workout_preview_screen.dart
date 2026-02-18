import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../workout_session_screen.dart';

class AssignedWorkoutPreviewScreen extends StatelessWidget {
  final String workoutId;
  final Map<String, dynamic>? workoutData;

  const AssignedWorkoutPreviewScreen({
    super.key,
    required this.workoutId,
    required this.workoutData,
  });

  @override
  Widget build(BuildContext context) {
    // ЛОГ ДЛЯ ОТЛАДКИ (поможет увидеть структуру в консоли)
    debugPrint('--- ДАННЫЕ ТРЕНИРОВКИ: ${workoutData.toString()} ---');

    // ШАГ 1: БЕЗОПАСНАЯ ПРОВЕРКА НА СТАРТЕ
    if (workoutData == null || workoutData!['exercises'] == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: const Color(0xFF1C1C1E)),
        body: const Center(
          child: Text(
            'Ошибка загрузки или программа пуста...',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final String workoutName = workoutData!['name']?.toString() ?? 'Без названия';
    final List<dynamic> rawExercises = workoutData!['exercises'] as List<dynamic>? ?? [];
    final Map<String, dynamic> targets = workoutData!['targets'] as Map<String, dynamic>? ?? {};

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(workoutName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rawExercises.length,
              itemBuilder: (context, index) {
                // ШАГ 2: БЕЗОПАСНЫЙ ДОСТУП ВНУТРИ СПИСКА
                final String exKey = rawExercises[index]?.toString() ?? 'unknown_exercise';
                
                String comment = "";
                if (targets.containsKey(exKey)) {
                  final parts = targets[exKey].toString().split('|');
                  if (parts.length > 1) {
                    comment = parts[1];
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exKey.tr(), // Перевод ключа (напр. ex_bench_press)
                        style: const TextStyle(
                          color: Colors.white, 
                          fontSize: 16, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          comment,
                          style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 14),
                        ),
                      ]
                    ],
                  ),
                );
              },
            ),
          ),
          
          // КНОПКА ЗАПУСКА
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  // Преобразуем dynamic в String для стабильности
                  List<String> initialEx = rawExercises.map((e) => e.toString()).toList();
                  
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WorkoutSessionScreen(
                        workoutTitle: workoutName,
                        initialExercises: initialEx,
                        assignedWorkoutId: workoutId,
                      ),
                    ),
                  );
                },
                child: const Text('НАЧАТЬ ТРЕНИРОВКУ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}