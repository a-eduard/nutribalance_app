import 'package:flutter/material.dart';
import 'services/database_service.dart'; // Путь к сервису
import 'ui_widgets.dart'; // Лежит рядом в корне

class WorkoutSet {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController repsController = TextEditingController();
  bool isCompleted = false;
  void dispose() { weightController.dispose(); repsController.dispose(); }
}

class SessionExercise {
  final String name;
  final List<WorkoutSet> sets;
  SessionExercise({required this.name, required this.sets});
}

class WorkoutSessionScreen extends StatefulWidget {
  final String workoutTitle;
  final List<String> initialExercises; 
  final String? existingDocId;
  final Map<String, dynamic>? existingData;

  const WorkoutSessionScreen({
    super.key,
    required this.workoutTitle,
    this.initialExercises = const [], 
    this.existingDocId,
    this.existingData,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final List<SessionExercise> _sessionExercises = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    // РЕДАКТИРОВАНИЕ
    if (widget.existingData != null) {
      final rawExercises = widget.existingData!['exercises'] as List<dynamic>;
      for (var rawEx in rawExercises) {
        final String name = rawEx['name'];
        final List<dynamic> rawSets = rawEx['sets'];
        final List<WorkoutSet> loadedSets = [];
        
        for (var s in rawSets) {
          final ws = WorkoutSet();
          ws.weightController.text = s['weight'].toString();
          ws.repsController.text = s['reps'].toString();
          ws.isCompleted = true; 
          loadedSets.add(ws);
        }
        _sessionExercises.add(SessionExercise(name: name, sets: loadedSets));
      }
    } 
    // НОВАЯ ТРЕНИРОВКА
    else {
      for (var name in widget.initialExercises) {
        _sessionExercises.add(SessionExercise(name: name, sets: [WorkoutSet()]));
      }
    }
  }

  @override
  void dispose() {
    for (var ex in _sessionExercises) for (var s in ex.sets) s.dispose();
    super.dispose();
  }

  void _addSet(SessionExercise exercise) => setState(() => exercise.sets.add(WorkoutSet()));
  void _removeSet(SessionExercise exercise, int index) => setState(() { if (exercise.sets.length > 1) { exercise.sets[index].dispose(); exercise.sets.removeAt(index); } });

  Future<void> _finishWorkout() async {
    setState(() => _isLoading = true);
    int totalTonnage = 0;
    List<Map<String, dynamic>> exercisesData = [];

    for (var ex in _sessionExercises) {
      List<Map<String, dynamic>> setsData = [];
      for (var s in ex.sets) {
        if (s.weightController.text.isNotEmpty && s.repsController.text.isNotEmpty) {
          int w = int.tryParse(s.weightController.text) ?? 0;
          int r = int.tryParse(s.repsController.text) ?? 0;
          totalTonnage += (w * r);
          setsData.add({'weight': w, 'reps': r});
        }
      }
      if (setsData.isNotEmpty) exercisesData.add({'name': ex.name, 'sets': setsData});
    }

    try {
      if (widget.existingDocId != null) {
        await DatabaseService().updateHistoryItem(widget.existingDocId!, {
            'workoutName': widget.workoutTitle, 'tonnage': totalTonnage, 'duration': 60, 'exercises': exercisesData,
        });
      } else {
        await DatabaseService().saveWorkoutSession(widget.workoutTitle, totalTonnage, 60, exercisesData);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(title: Text(widget.workoutTitle), backgroundColor: const Color(0xFF1C1C1E)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sessionExercises.length,
                itemBuilder: (context, index) {
                  final exercise = _sessionExercises[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(exercise.name, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 18, fontWeight: FontWeight.bold)),
                              IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFFCCFF00)), onPressed: () => _addSet(exercise))
                            ],
                          ),
                        ),
                        ...List.generate(exercise.sets.length, (i) => Row(
                          children: [
                            const SizedBox(width: 16),
                            Text("${i + 1}", style: const TextStyle(color: Colors.grey)),
                            const SizedBox(width: 16),
                            Expanded(child: TextField(controller: exercise.sets[i].weightController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "КГ", filled: true, fillColor: Colors.black))),
                            const SizedBox(width: 8),
                            Expanded(child: TextField(controller: exercise.sets[i].repsController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "ПОВТ", filled: true, fillColor: Colors.black))),
                            IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () => _removeSet(exercise, i))
                          ],
                        )).map((e) => Padding(padding: const EdgeInsets.only(bottom: 8), child: e)),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_isLoading) const CircularProgressIndicator(color: Color(0xFFCCFF00))
            else NeonActionButton(text: widget.existingDocId != null ? "ОБНОВИТЬ" : "ЗАВЕРШИТЬ", onTap: _finishWorkout, isFullWidth: true)
          ],
        ),
      ),
    );
  }
}