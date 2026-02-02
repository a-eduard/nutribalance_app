import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // ДЛЯ ПИКЕРА
import 'dart:ui'; // ДЛЯ FontFeature
import 'exercise_data.dart';
import 'workout_success_screen.dart';
import 'ui_widgets.dart';
import 'services/database_service.dart';

class WorkoutSessionScreen extends StatefulWidget {
  final Workout workout;

  const WorkoutSessionScreen({super.key, required this.workout});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Timer? _timer;
  int _secondsElapsed = 0;
  
  late DateTime _startTime;
  
  late List<Map<String, dynamic>> _sessionData;
  final Map<String, List<Map<String, dynamic>>> _historyCache = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
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

  void _finishWorkout() async {
    if (_isSaving) return; 
    setState(() => _isSaving = true);

    int totalTonnage = 0;
    int completedExercisesCount = 0;

    for (var exercise in _sessionData) {
      bool isExerciseStarted = false;
      for (var set in exercise['sets']) {
        String wStr = set['weight'].toString();
        String rStr = set['reps'].toString();
        
        if (wStr.isNotEmpty && rStr.isNotEmpty) {
          isExerciseStarted = true;
          int weight = int.tryParse(wStr) ?? 0;
          int reps = int.tryParse(rStr) ?? 0;
          totalTonnage += (weight * reps);
        }
      }
      if (isExerciseStarted) completedExercisesCount++;
    }

    int durationMinutes = DateTime.now().difference(_startTime).inMinutes;
    if (durationMinutes == 0) durationMinutes = 1;

    try {
      await DatabaseService().saveWorkoutSession(
        widget.workout.name,
        totalTonnage,
        durationMinutes
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => WorkoutSuccessScreen(
            durationMinutes: durationMinutes,
            tonnage: totalTonnage, 
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
      bottomNavigationBar: Container(
        color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.all(24),
        child: _isSaving 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
          : NeonActionButton(
              text: 'ЗАВЕРШИТЬ ТРЕНИРОВКУ',
              onTap: _finishWorkout,
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

            // ДОСТАЕМ ЦЕЛЬ ИЗ WORKOUT
            final targetGoal = widget.workout.targets[title];

            return _ExerciseCard(
              title: title,
              target: targetGoal, // ПЕРЕДАЕМ ЦЕЛЬ В UI
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
  final String? target; // <-- НОВОЕ ПОЛЕ
  final List<dynamic> setsData;
  final List<Map<String, dynamic>>? historySets;
  final VoidCallback onAddSet;
  final Function(int) onRemoveSet;

  const _ExerciseCard({
    required this.title,
    this.target,
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
          // ЗАГОЛОВОК + ЦЕЛЬ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20, color: Colors.white))),
              if (target != null && target!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCCFF00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.track_changes, size: 14, color: Color(0xFFCCFF00)),
                      const SizedBox(width: 4),
                      Text(target!, style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          
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

  // --- ЛОГИКА БАРАБАНА (PICKER) ---
  void _showWheelPicker({
    required TextEditingController controller,
    required String dataKey,
    required int min,
    required int max,
    String suffix = '',
  }) {
    FocusScope.of(context).unfocus();

    int currentValue = int.tryParse(controller.text) ?? 0;
    if (currentValue < min) currentValue = min;
    if (currentValue > max) currentValue = max;

    final FixedExtentScrollController scrollController = 
        FixedExtentScrollController(initialItem: currentValue - min);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SizedBox(
          height: 250,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text("ГОТОВО", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(pickerTextStyle: TextStyle(color: Colors.white, fontSize: 24)),
                  ),
                  child: CupertinoPicker(
                    scrollController: scrollController,
                    itemExtent: 40,
                    magnification: 1.22,
                    useMagnifier: true,
                    onSelectedItemChanged: (index) {
                      final newValue = (min + index).toString();
                      controller.text = newValue;
                      _updateData(dataKey, newValue);
                    },
                    children: List.generate(max - min + 1, (index) {
                      return Center(child: Text("${min + index}$suffix", style: const TextStyle(color: Colors.white)));
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
          Expanded(
            child: HeavyInput(
              controller: _weightController, 
              hint: widget.prevWeight ?? "-", 
              onChanged: (val) => _updateData('weight', val),
              // ПИКЕР ВЕСА
              onPickerTap: () => _showWheelPicker(
                controller: _weightController, 
                dataKey: 'weight', 
                min: 0, 
                max: 500, 
                suffix: ' кг'
              ),
            )
          ),
          const SizedBox(width: 16),
          Expanded(
            child: HeavyInput(
              controller: _repsController, 
              hint: widget.prevReps ?? "-", 
              onChanged: (val) => _updateData('reps', val),
              // ПИКЕР ПОВТОРОВ
              onPickerTap: () => _showWheelPicker(
                controller: _repsController, 
                dataKey: 'reps', 
                min: 0, 
                max: 100
              ),
            )
          ),
        ],
      ),
    );
  }
}