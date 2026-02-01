import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui'; // Нужно для FontFeature
import 'exercise_data.dart';
import 'workout_success_screen.dart';
import 'ui_widgets.dart'; // Виджеты дизайна
import 'services/database_service.dart'; // <--- СЕРВИС БАЗЫ ДАННЫХ

class WorkoutSessionScreen extends StatefulWidget {
  final Workout workout;

  const WorkoutSessionScreen({super.key, required this.workout});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Timer? _timer;
  int _secondsElapsed = 0;
  
  // 1. Время начала для расчета длительности
  late DateTime _startTime;
  
  late List<Map<String, dynamic>> _sessionData;
  final Map<String, List<Map<String, dynamic>>> _historyCache = {};
  bool _isSaving = false; // Чтобы не нажать дважды

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now(); // Фиксируем старт
    _initializeSession();
    _startTimer();
  }

  void _initializeSession() {
    _sessionData = widget.workout.exercises.map((exercise) {
      final prevSets = WorkoutDataService.getLastSetsFor(exercise.title);
      if (prevSets != null) {
        _historyCache[exercise.title] = prevSets;
      }
      return {
        "title": exercise.title,
        "sets": List.generate(3, (index) => {
          "weight": "",
          "reps": "",
          "key": UniqueKey(), 
        }),
      };
    }).toList();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsElapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // --- 2. ЛОГИКА ЗАВЕРШЕНИЯ ---
  void _finishWorkout() async {
    if (_isSaving) return; // Защита от двойного клика
    setState(() => _isSaving = true);

    // Считаем статистику
    int totalTonnage = 0;
    int completedExercisesCount = 0;

    // Проходим по всем упражнениям
    for (var exercise in _sessionData) {
      bool isExerciseStarted = false;
      
      for (var set in exercise['sets']) {
        String wStr = set['weight'].toString();
        String rStr = set['reps'].toString();
        
        // Если сет заполнен
        if (wStr.isNotEmpty && rStr.isNotEmpty) {
          isExerciseStarted = true;
          int weight = int.tryParse(wStr) ?? 0;
          int reps = int.tryParse(rStr) ?? 0;
          totalTonnage += (weight * reps);
        }
      }
      
      if (isExerciseStarted) {
        completedExercisesCount++;
      }
    }

    // Считаем время в минутах
    int durationMinutes = DateTime.now().difference(_startTime).inMinutes;
    // Если меньше 1 минуты, пишем 1, чтобы не было 0
    if (durationMinutes == 0) durationMinutes = 1;

    try {
      // Сохраняем в Firebase
      await DatabaseService().saveWorkoutSession(
        widget.workout.name,
        totalTonnage,
        durationMinutes
      );

      if (!mounted) return;

      // 3. Переход на Экран Успеха
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WorkoutSuccessScreen(
            durationMinutes: durationMinutes,
            tonnage: totalTonnage, // ИСПРАВЛЕНО: Оставили только tonnage
            exercisesCount: completedExercisesCount,
          ),
        ),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка сохранения: $e"), backgroundColor: Colors.red)
        );
        setState(() => _isSaving = false);
      }
    }
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      _sessionData[exerciseIndex]['sets'].add({
        "weight": "",
        "reps": "",
        "key": UniqueKey(),
      });
    });
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    setState(() {
      _sessionData[exerciseIndex]['sets'].removeAt(setIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
        title: Text(_formattedTime, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      // Кнопка ЗАВЕРШИТЬ внизу
      bottomNavigationBar: Container(
        color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.all(24),
        child: _isSaving 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
          : NeonActionButton(
              text: 'ЗАВЕРШИТЬ ТРЕНИРОВКУ',
              onTap: _finishWorkout, // Привязали метод
            ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          itemCount: _sessionData.length,
          itemBuilder: (context, index) {
            final exercise = _sessionData[index];
            final title = exercise['title'];
            final history = _historyCache[title];

            return _ExerciseCard(
              title: title,
              setsData: exercise['sets'],
              historySets: history,
              onAddSet: () => _addSet(index),
              onRemoveSet: (setIndex) => _removeSet(index, setIndex),
            );
          },
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final String title;
  final List<dynamic> setsData;
  final List<Map<String, dynamic>>? historySets;
  final VoidCallback onAddSet;
  final Function(int) onRemoveSet;

  const _ExerciseCard({
    required this.title,
    required this.setsData,
    this.historySets,
    required this.onAddSet,
    required this.onRemoveSet,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20, color: Colors.white)),
          const SizedBox(height: 16),
          
          Row(
            children: const [
              SizedBox(width: 30, child: Text("#", style: TextStyle(color: Colors.grey, fontSize: 12))),
              SizedBox(width: 16),
              Expanded(child: Center(child: Text("ВЕС", style: TextStyle(color: Colors.grey, fontSize: 12)))),
              SizedBox(width: 16),
              Expanded(child: Center(child: Text("ПОВТОРЫ", style: TextStyle(color: Colors.grey, fontSize: 12)))),
            ],
          ),
          const SizedBox(height: 12),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: setsData.length,
            itemBuilder: (context, index) {
              final set = setsData[index];
              String? prevWeight;
              String? prevReps;
              if (historySets != null && index < historySets!.length) {
                prevWeight = historySets![index]['weight'].toString();
                prevReps = historySets![index]['reps'].toString();
              }

              return Dismissible(
                key: set['key'],
                direction: DismissDirection.endToStart,
                onDismissed: (direction) => onRemoveSet(index),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                child: AutoSaveSetRow(
                  setNumber: index + 1,
                  setData: set,
                  prevWeight: prevWeight,
                  prevReps: prevReps,
                ),
              );
            },
          ),
          
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: onAddSet,
              icon: const Icon(Icons.add, size: 18, color: Color(0xFFCCFF00)),
              label: const Text("ДОБАВИТЬ ПОДХОД", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class AutoSaveSetRow extends StatefulWidget {
  final int setNumber;
  final Map<String, dynamic> setData;
  final String? prevWeight;
  final String? prevReps;

  const AutoSaveSetRow({
    super.key,
    required this.setNumber,
    required this.setData,
    this.prevWeight,
    this.prevReps,
  });

  @override
  State<AutoSaveSetRow> createState() => _AutoSaveSetRowState();
}

class _AutoSaveSetRowState extends State<AutoSaveSetRow> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;
  bool _isFilled = false;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: widget.setData['weight']);
    _repsController = TextEditingController(text: widget.setData['reps']);
    _checkIfFilled();
  }

  void _checkIfFilled() {
    final filled = _weightController.text.isNotEmpty && _repsController.text.isNotEmpty;
    if (filled != _isFilled) setState(() => _isFilled = filled);
  }

  void _updateData(String key, String value) {
    widget.setData[key] = value;
    _checkIfFilled();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              "${widget.setNumber}",
              style: TextStyle(
                color: _isFilled ? const Color(0xFFCCFF00) : const Color(0xFF8E8E93),
                fontWeight: FontWeight.bold,
                fontSize: 16
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: HeavyInput(controller: _weightController, hint: widget.prevWeight ?? "-", onChanged: (val) => _updateData('weight', val))),
          const SizedBox(width: 16),
          Expanded(child: HeavyInput(controller: _repsController, hint: widget.prevReps ?? "-", onChanged: (val) => _updateData('reps', val))),
        ],
      ),
    );
  }
}