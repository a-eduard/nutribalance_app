import 'package:flutter/material.dart';
// Импортируем экран тренировки (проверь правильность пути, если файл лежит в корне lib)
import '../workout_session_screen.dart';

class AssignedWorkoutPreviewScreen extends StatefulWidget {
  final String workoutId;
  final Map<String, dynamic> workoutData;

  const AssignedWorkoutPreviewScreen({
    super.key,
    required this.workoutId,
    required this.workoutData,
  });

  @override
  State<AssignedWorkoutPreviewScreen> createState() => _AssignedWorkoutPreviewScreenState();
}

class _AssignedWorkoutPreviewScreenState extends State<AssignedWorkoutPreviewScreen> {
  void _startWorkout() {
    // 1. Конвертируем данные от тренера в формат existingData для WorkoutSessionScreen
    List<Map<String, dynamic>> sessionExercises = [];
    final exercises = widget.workoutData['exercises'] as List<dynamic>? ?? [];

    for (var ex in exercises) {
      int setsCount = int.tryParse(ex['targetSets']?.toString() ?? '1') ?? 1;
      List<Map<String, dynamic>> sets = [];
      
      for (int i = 0; i < setsCount; i++) {
        // Оставляем вес пустым, а повторения заполняем целью от тренера
        sets.add({'weight': '', 'reps': ex['targetReps'] ?? ''});
      }
      
      sessionExercises.add({
        'name': ex['name'] ?? 'Упражнение',
        'sets': sets,
        // Передаем как заметку (note), чтобы она отобразилась в текстовом поле упражнения
        'note': '🎯 Задание: ${ex['targetSets']} подходов по ${ex['targetReps']} повторений'
      });
    }

    // 2. Открываем экран тренировки
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(
          workoutTitle: widget.workoutData['name'] ?? 'Тренировка от тренера',
          // Передаем сконвертированные данные как "существующие"
          existingData: {'exercises': sessionExercises},
          // Передаем ID задания, чтобы в будущем пометить его как выполненное
          assignedWorkoutId: widget.workoutId, 
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workoutName = widget.workoutData['name'] ?? 'Тренировка';
    final exercises = widget.workoutData['exercises'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          workoutName.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final ex = exercises[index] as Map<String, dynamic>;
                final exName = ex['name'] ?? 'Упражнение';
                final sets = ex['targetSets'] ?? '0';
                final reps = ex['targetReps'] ?? '0';

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
                      Text(
                        exName, 
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.flag, color: Color(0xFFCCFF00), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            "Цель: $sets подходов по $reps повторений", 
                            style: const TextStyle(color: Colors.grey, fontSize: 14)
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // КНОПКА "НАЧАТЬ ТРЕНИРОВКУ"
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              border: Border(top: BorderSide(color: Colors.black, width: 2)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _startWorkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text("НАЧАТЬ ТРЕНИРОВКУ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}