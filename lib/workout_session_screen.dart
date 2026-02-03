import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
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
  late Map<String, String> _currentTargets; 
  Map<String, String> _lastSessionStats = {}; 

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _currentTargets = Map.from(widget.workout.targets);
    
    _initializeSession();
    // Запускаем автозаполнение
    _loadAndAutofill(); 
    _startTimer();
  }

  void _initializeSession() {
    _sessionData = widget.workout.exercises.map((exercise) {
      return {
        "title": exercise.title,
        "sets": List.generate(1, (index) => {
          "weight": "",
          "reps": "",
          "key": UniqueKey(), 
        }),
      };
    }).toList();
  }

  // --- АВТОЗАПОЛНЕНИЕ ---
  Future<void> _loadAndAutofill() async {
    // Небольшая задержка для плавности UI
    await Future.delayed(const Duration(milliseconds: 300));
    
    final historyDoc = await DatabaseService().getLastWorkoutData(widget.workout.name);
    
    if (historyDoc != null && historyDoc['exercises'] != null && mounted) {
      final List<dynamic> historyExercises = historyDoc['exercises'];
      bool anyDataFilled = false;

      setState(() {
        for (var i = 0; i < _sessionData.length; i++) {
          final currentTitle = _sessionData[i]['title'].toString().trim();
          
          final historyItem = historyExercises.firstWhere(
            (e) => e['name'].toString().trim().toLowerCase() == currentTitle.toLowerCase(),
            orElse: () => null,
          );

          if (historyItem != null && historyItem['sets'] != null) {
            final List<dynamic> oldSets = historyItem['sets'];
            List<Map<String, dynamic>> newSetsForUI = [];
            List<String> stats = [];

            for (var s in oldSets) {
              String w = s['weight'].toString();
              String r = s['reps'].toString();
              
              newSetsForUI.add({
                "weight": w,
                "reps": r,
                "key": UniqueKey(),
              });
              stats.add("${w}x$r");
            }

            if (newSetsForUI.isNotEmpty) {
              _sessionData[i]['sets'] = newSetsForUI;
              _lastSessionStats[currentTitle] = stats.join(", ");
              anyDataFilled = true;
            }
          }
        }
      });
      
      if (anyDataFilled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Данные из прошлой тренировки загружены"), backgroundColor: Color(0xFF1C1C1E), duration: Duration(seconds: 2))
        );
      }
    }
  }

  // --- СОХРАНЕНИЕ ---
  void _finishWorkout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Ошибка"), content: const Text("Вы не авторизованы."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]));
      return;
    }

    int totalTonnage = 0;
    int completedExercisesCount = 0;
    List<Map<String, dynamic>> exercisesDataToSave = [];

    for (var exercise in _sessionData) {
      bool isExerciseStarted = false;
      List<Map<String, dynamic>> setsToSave = [];

      for (var set in exercise['sets']) {
        String wStr = set['weight'].toString();
        String rStr = set['reps'].toString();
        
        if (wStr.isEmpty) wStr = "0";
        if (rStr.isEmpty) rStr = "0";

        int weight = int.tryParse(wStr) ?? 0;
        int reps = int.tryParse(rStr) ?? 0;
        
        totalTonnage += (weight * reps);

        setsToSave.add({'weight': wStr, 'reps': rStr});
        isExerciseStarted = true;
      }
      
      if (isExerciseStarted) {
        completedExercisesCount++;
        exercisesDataToSave.add({
          'name': exercise['title'],
          'sets': setsToSave,
        });
      }
    }

    int durationMinutes = DateTime.now().difference(_startTime).inMinutes;
    if (durationMinutes == 0) durationMinutes = 1;

    // Индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))),
    );

    try {
      await DatabaseService().saveWorkoutSession(
        widget.workout.name,
        totalTonnage,
        durationMinutes,
        exercisesDataToSave,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorkoutSuccessScreen(
              durationMinutes: durationMinutes,
              tonnage: totalTonnage, 
              exercisesCount: completedExercisesCount,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Ошибка"), content: Text("$e"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]));
      }
    }
  }

  void _addSet(int exerciseIndex) {
    setState(() {
      _sessionData[exerciseIndex]['sets'].add({"weight": "", "reps": "", "key": UniqueKey()});
    });
  }

  void _removeSet(int exerciseIndex, int setIndex) {
    setState(() {
      _sessionData[exerciseIndex]['sets'].removeAt(setIndex);
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _secondsElapsed++);
    });
  }

  String get _formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void _editTarget(String exerciseName) {
    String currentText = _currentTargets[exerciseName] ?? "";
    TextEditingController controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("План", style: TextStyle(color: Colors.white)),
        content: TextField(controller: controller, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Например: 4x12", hintStyle: TextStyle(color: Colors.grey))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { setState(() => _currentTargets[exerciseName] = controller.text); Navigator.pop(context); }, child: const Text("ОК", style: TextStyle(color: Color(0xFFCCFF00)))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Проверка статуса для индикатора
    final isAuth = FirebaseAuth.instance.currentUser != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
        title: Text(_formattedTime, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Индикатор статуса (зеленая точка)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.circle, color: isAuth ? Colors.green : Colors.red, size: 10),
          )
        ],
      ),
      bottomNavigationBar: Container(
        color: const Color(0xFF0F0F0F),
        padding: const EdgeInsets.all(24),
        child: NeonActionButton(text: 'ЗАВЕРШИТЬ ТРЕНИРОВКУ', onTap: _finishWorkout),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          itemCount: _sessionData.length,
          itemBuilder: (context, index) {
            final exercise = _sessionData[index];
            final title = exercise['title'];
            final lastStats = _lastSessionStats[title];
            final targetGoal = _currentTargets[title];

            return _ExerciseCard(
              title: title,
              target: targetGoal,
              lastStats: lastStats,
              onTargetTap: () => _editTarget(title), 
              setsData: exercise['sets'],
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
  final String? target;
  final String? lastStats;
  final VoidCallback onTargetTap;
  final List<dynamic> setsData;
  final VoidCallback onAddSet;
  final Function(int) onRemoveSet;

  const _ExerciseCard({required this.title, this.target, this.lastStats, required this.onTargetTap, required this.setsData, required this.onAddSet, required this.onRemoveSet});

  @override
  Widget build(BuildContext context) {
    return PremiumGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20, color: Colors.white))),
              if (target != null && target!.isNotEmpty)
                GestureDetector(onTap: onTargetTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFCCFF00).withOpacity(0.15), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.4))), child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.edit, size: 14, color: Color(0xFFCCFF00)), const SizedBox(width: 6), Text(target!, style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.w600, fontSize: 13))]),),)
              else 
                GestureDetector(onTap: onTargetTap, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle), child: const Icon(Icons.add, size: 16, color: Colors.grey),),),
            ],
          ),
          if (lastStats != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Row(children: [const Icon(Icons.history, color: Colors.grey, size: 14), const SizedBox(width: 6), Expanded(child: Text("Прошлый раз: $lastStats", style: const TextStyle(color: Colors.grey, fontSize: 13), overflow: TextOverflow.ellipsis))])),
          const SizedBox(height: 16),
          Row(children: const [SizedBox(width: 30, child: Text("#", style: TextStyle(color: Colors.grey, fontSize: 12))), SizedBox(width: 16), Expanded(child: Center(child: Text("ВЕС", style: TextStyle(color: Colors.grey, fontSize: 12)))), SizedBox(width: 16), Expanded(child: Center(child: Text("ПОВТОРЫ", style: TextStyle(color: Colors.grey, fontSize: 12))))]),
          const SizedBox(height: 12),
          ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: setsData.length, itemBuilder: (context, index) { final set = setsData[index]; return Dismissible(key: set['key'], direction: DismissDirection.endToStart, onDismissed: (direction) => onRemoveSet(index), background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.red)), child: AutoSaveSetRow(setNumber: index + 1, setData: set)); }),
          const SizedBox(height: 12),
          Center(child: TextButton.icon(onPressed: onAddSet, icon: const Icon(Icons.add, size: 18, color: Color(0xFFCCFF00)), label: const Text("ДОБАВИТЬ ПОДХОД", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}

class AutoSaveSetRow extends StatefulWidget {
  final int setNumber;
  final Map<String, dynamic> setData;
  const AutoSaveSetRow({super.key, required this.setNumber, required this.setData});
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

  void _showWheelPicker({required TextEditingController controller, required String dataKey, required int min, required int max, String suffix = ''}) {
    FocusScope.of(context).unfocus();
    int currentValue = int.tryParse(controller.text) ?? 0;
    if (currentValue < min) currentValue = min;
    if (currentValue > max) currentValue = max;
    final FixedExtentScrollController scrollController = FixedExtentScrollController(initialItem: currentValue - min);
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1C1C1E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (context) { return SizedBox(height: 250, child: Column(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [GestureDetector(onTap: () => Navigator.pop(context), child: const Text("ГОТОВО", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)))])), Expanded(child: CupertinoTheme(data: const CupertinoThemeData(textTheme: CupertinoTextThemeData(pickerTextStyle: TextStyle(color: Colors.white, fontSize: 24))), child: CupertinoPicker(scrollController: scrollController, itemExtent: 40, magnification: 1.22, useMagnifier: true, onSelectedItemChanged: (index) { final newValue = (min + index).toString(); controller.text = newValue; _updateData(dataKey, newValue); }, children: List.generate(max - min + 1, (index) { return Center(child: Text("${min + index}$suffix", style: const TextStyle(color: Colors.white))); })))),]));});
  }

  @override
  Widget build(BuildContext context) {
    return Container(margin: const EdgeInsets.only(bottom: 12), child: Row(children: [SizedBox(width: 30, child: Text("${widget.setNumber}", style: TextStyle(color: _isFilled ? const Color(0xFFCCFF00) : const Color(0xFF8E8E93), fontWeight: FontWeight.bold, fontSize: 16))), const SizedBox(width: 16), Expanded(child: HeavyInput(controller: _weightController, hint: "-", onChanged: (val) => _updateData('weight', val), onPickerTap: () => _showWheelPicker(controller: _weightController, dataKey: 'weight', min: 0, max: 500, suffix: ' кг'))), const SizedBox(width: 16), Expanded(child: HeavyInput(controller: _repsController, hint: "-", onChanged: (val) => _updateData('reps', val), onPickerTap: () => _showWheelPicker(controller: _repsController, dataKey: 'reps', min: 0, max: 100))),],));
  }
}