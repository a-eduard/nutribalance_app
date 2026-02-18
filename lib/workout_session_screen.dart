import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/database_service.dart';
import '../ui_widgets.dart';

class WorkoutSet {
  final TextEditingController weightController = TextEditingController();
  final TextEditingController repsController = TextEditingController();
  bool isCompleted = false;
  
  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}

class SessionExercise {
  final String name;
  final List<WorkoutSet> sets;
  final TextEditingController noteController = TextEditingController();

  SessionExercise({required this.name, required this.sets, String? initialNote}) {
    if (initialNote != null) {
      noteController.text = initialNote;
    }
  }

  void dispose() {
    noteController.dispose();
    for (var s in sets) {
      s.dispose();
    }
  }
}

class WorkoutSessionScreen extends StatefulWidget {
  final String workoutTitle;
  final List<String> initialExercises;
  final String? workoutId;
  final String? existingDocId;
  final Map<String, dynamic>? existingData; 
  final String? assignedWorkoutId;

  const WorkoutSessionScreen({
    super.key,
    required this.workoutTitle,
    this.initialExercises = const [],
    this.workoutId, 
    this.existingDocId,
    this.existingData,
    this.assignedWorkoutId,
  });

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final List<SessionExercise> _sessionExercises = [];
  bool _isLoading = false;
  bool _isLoadingHistory = true; 

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    for (var ex in _sessionExercises) ex.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    if (widget.existingData != null) {
      _parseExistingData(widget.existingData!);
      setState(() => _isLoadingHistory = false);
    } else {
      for (var name in widget.initialExercises) {
        _sessionExercises.add(SessionExercise(name: name, sets: [WorkoutSet()]));
      }
      if (widget.workoutId != null) {
        await _loadHistory();
      } else {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  void _parseExistingData(Map<String, dynamic> data) {
    try {
      if (data['exercises'] == null) return;
      final rawExercises = data['exercises'] as List<dynamic>;
      for (var rawEx in rawExercises) {
        final String name = rawEx['name'] ?? "Упражнение";
        final String note = rawEx['note'] ?? "";
        var loadedSets = <WorkoutSet>[];
        if (rawEx['sets'] != null) {
          final rawSets = rawEx['sets'] as List<dynamic>;
          for (var setData in rawSets) {
            var newSet = WorkoutSet();
            newSet.weightController.text = (setData['weight'] ?? "").toString();
            newSet.repsController.text = (setData['reps'] ?? "").toString();
            loadedSets.add(newSet);
          }
        }
        if (loadedSets.isEmpty) loadedSets.add(WorkoutSet());
        _sessionExercises.add(SessionExercise(name: name, sets: loadedSets, initialNote: note));
      }
    } catch (e) {
      debugPrint("Ошибка парсинга: $e");
    }
  }

  Future<void> _loadHistory() async {
    final lastData = await DatabaseService().getLastHistoryForWorkout(widget.workoutId!, widget.workoutTitle);
    if (lastData != null && mounted) {
      final oldEx = lastData['exercises'] as List<dynamic>;
      setState(() {
        for (var current in _sessionExercises) {
          final match = oldEx.firstWhere((o) => o['name'] == current.name, orElse: () => null);
          if (match != null) {
            current.noteController.text = match['note'] ?? "";
            List sets = match['sets'];
            if (sets.isNotEmpty) {
              current.sets.clear(); 
              for (var s in sets) {
                var ws = WorkoutSet();
                ws.weightController.text = s['weight'].toString();
                ws.repsController.text = s['reps'].toString();
                current.sets.add(ws);
              }
            }
          }
        }
        _isLoadingHistory = false;
      });
    } else {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _finishWorkout() async {
    setState(() => _isLoading = true);
    
    double totalTonnage = 0.0;
    List<Map<String, dynamic>> exercisesData = [];

    for (var ex in _sessionExercises) {
      List<Map<String, dynamic>> setsData = [];
      for (var s in ex.sets) {
        String wText = s.weightController.text.replaceAll(',', '.').trim();
        String rText = s.repsController.text.trim();

        double w = double.tryParse(wText) ?? 0.0;
        int r = int.tryParse(rText) ?? 0;

        if (wText.isNotEmpty || rText.isNotEmpty) {
          totalTonnage += (w * r); // Считаем объем поднятого веса
          setsData.add({'weight': w, 'reps': r});
        }
      }
      exercisesData.add({'name': ex.name, 'note': ex.noteController.text.trim(), 'sets': setsData});
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      
      if (widget.existingDocId != null && widget.assignedWorkoutId == null) {
        await DatabaseService().updateHistoryItem(
          widget.existingDocId!,
          {'workoutName': widget.workoutTitle, 'tonnage': totalTonnage.round(), 'exercises': exercisesData},
        );
      } else {
        await DatabaseService().saveWorkoutSession(
          widget.workoutTitle, totalTonnage.round(), 60, exercisesData, workoutId: widget.workoutId 
        );
      }

      if (uid != null) {
        // --- 1. ПРИБАВЛЯЕМ ОБЪЕМ К ОБЩЕМУ ТОННАЖУ В ПРОФИЛЕ ПОЛЬЗОВАТЕЛЯ ---
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'totalVolumeKg': FieldValue.increment(totalTonnage)
        }, SetOptions(merge: true));

        // --- 2. ЗАКРЫВАЕМ НАЗНАЧЕННУЮ ТРЕНИРОВКУ (ЕСЛИ БЫЛА) ---
        if (widget.assignedWorkoutId != null) {
          await FirebaseFirestore.instance
              .collection('users').doc(uid).collection('assigned_workouts').doc(widget.assignedWorkoutId)
              .update({'isCompleted': true, 'completedAt': FieldValue.serverTimestamp()});
        }
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${'error_occurred'.tr()}: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.workoutTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sessionExercises.length,
                itemBuilder: (context, index) => _buildCard(_sessionExercises[index]),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF1C1C1E),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
                : NeonActionButton(
                    text: (widget.existingDocId != null && widget.assignedWorkoutId == null) ? 'save_changes'.tr() : 'finish_workout'.tr(),
                    onTap: _finishWorkout,
                    isFullWidth: true,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(SessionExercise ex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(ex.name.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: ex.noteController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'notes_hint'.tr(),
                hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
                filled: true, fillColor: Colors.black,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 30, child: Text("#", style: TextStyle(color: Colors.grey))), 
                Expanded(child: Center(child: Text('kg'.tr(), style: const TextStyle(color: Colors.grey)))), 
                const SizedBox(width: 10),
                Expanded(child: Center(child: Text('reps_short'.tr(), style: const TextStyle(color: Colors.grey)))),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 5),
          ...List.generate(ex.sets.length, (i) {
             final s = ex.sets[i];
             return Padding(
               padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
               child: Row(
                 children: [
                   SizedBox(width: 30, child: Text("${i+1}", style: const TextStyle(color: Colors.white))),
                   Expanded(child: _input(s.weightController, true)),
                   const SizedBox(width: 10),
                   Expanded(child: _input(s.repsController, false)),
                   IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => setState(() => ex.sets.removeAt(i)))
                 ],
               ),
             );
          }),
          GestureDetector(
            onTap: () => setState(() => ex.sets.add(WorkoutSet())),
            child: Container(
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Text('add_set'.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, bool isDec) {
    return Container(
      height: 45,
      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: isDec),
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.only(bottom: 5)),
      ),
    );
  }
}