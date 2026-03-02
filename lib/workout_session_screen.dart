import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/database_service.dart';
import '../ui_widgets.dart';
import '../utils/exercise_parser.dart';

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
  final String? notes; 
  final TextEditingController noteController = TextEditingController(); 

  SessionExercise({required this.name, required this.sets, this.notes});

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
    bool isHistoryDoc = widget.existingDocId != null && widget.existingData != null && widget.existingData!.containsKey('tonnage');

    if (isHistoryDoc) {
      _parseExistingData(widget.existingData!);
      setState(() => _isLoadingHistory = false);
    } else {
      if (widget.existingData != null && widget.existingData!['exercises'] != null) {
        final rawExercises = widget.existingData!['exercises'] as List<dynamic>;
        final Map<String, dynamic> targets = widget.existingData?['targets'] ?? {};
        
        for (var rawEx in rawExercises) {
          final parsed = ExerciseParser.parse(rawEx, targets);
          _sessionExercises.add(SessionExercise(name: parsed.name, sets: [WorkoutSet()], notes: parsed.notes));
        }
      } else {
        for (var nameItem in widget.initialExercises) {
          final parsed = ExerciseParser.parse(nameItem);
          _sessionExercises.add(SessionExercise(name: parsed.name, sets: [WorkoutSet()], notes: parsed.notes.isNotEmpty ? parsed.notes : null));
        }
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
        final parsed = ExerciseParser.parse(rawEx);
        String name = parsed.name;
        String? parsedNotes = parsed.notes.isNotEmpty ? parsed.notes : null;
        String? userNote; 

        if (rawEx is Map) {
          userNote = rawEx['note']?.toString(); 
        }

        var loadedSets = <WorkoutSet>[];
        if (rawEx is Map && rawEx['sets'] != null) {
          final rawSets = rawEx['sets'] as List<dynamic>;
          for (var setData in rawSets) {
            var newSet = WorkoutSet();
            String wStr = (setData['weight'] ?? "").toString();
            if (wStr.endsWith('.0')) wStr = wStr.substring(0, wStr.length - 2);
            
            newSet.weightController.text = wStr;
            newSet.repsController.text = (setData['reps'] ?? "").toString();
            loadedSets.add(newSet);
          }
        }
        
        if (loadedSets.isEmpty) loadedSets.add(WorkoutSet());
        
        var newEx = SessionExercise(name: name, sets: loadedSets, notes: parsedNotes);
        if (userNote != null && userNote.isNotEmpty) newEx.noteController.text = userNote;
        _sessionExercises.add(newEx);
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
          final match = oldEx.firstWhere((o) => o is Map && o['name'] == current.name, orElse: () => null);
          if (match != null) {
            if ((match['note'] ?? "").toString().isNotEmpty) {
              current.noteController.text = match['note'];
            }
            List sets = match['sets'] ?? [];
            if (sets.isNotEmpty) {
              current.sets.clear(); 
              for (var s in sets) {
                var ws = WorkoutSet();
                String wStr = s['weight'].toString();
                if (wStr.endsWith('.0')) wStr = wStr.substring(0, wStr.length - 2);
                
                ws.weightController.text = wStr;
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
        double w = double.tryParse(s.weightController.text.replaceAll(',', '.').trim()) ?? 0.0;
        int r = int.tryParse(s.repsController.text.trim()) ?? 0;
        
        if (w > 0 || r > 0) {
          totalTonnage += (w * r);
          setsData.add({'weight': w, 'reps': r});
        }
      }
      
      exercisesData.add({
        'name': ex.name, 
        'note': ex.noteController.text.trim(), 
        'sets': setsData
      });
    }

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      
      if (widget.existingDocId != null && widget.assignedWorkoutId == null && widget.existingData != null && widget.existingData!.containsKey('tonnage')) {
        await DatabaseService().updateHistoryItem(
          widget.existingDocId!,
          {
            'workoutName': widget.workoutTitle, 
            'tonnage': totalTonnage.round(), 
            'exercises': exercisesData
          },
        );
      } else {
        await DatabaseService().saveWorkoutSession(
          widget.workoutTitle, 
          totalTonnage.round(), 
          60, 
          exercisesData, 
          workoutId: widget.workoutId 
        );
      }

      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'totalVolumeKg': FieldValue.increment(totalTonnage)
        }, SetOptions(merge: true));
      }
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка сохранения: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.workoutTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: const Color(0xFF1C1C1E),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_isLoadingHistory)
                const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))))
              else
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
                      text: (widget.existingDocId != null && widget.existingData != null && widget.existingData!.containsKey('tonnage')) ? 'save_changes'.tr() : 'finish_workout'.tr(),
                      onTap: _finishWorkout,
                      isFullWidth: true,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(SessionExercise ex) {
    String cleanName = ex.name.replaceAll(RegExp(r'[{}""\[\],]|(name|notes|sets|reps|rest|coach_note)\s*:'), '').trim();

    String targetText = "";
    String coachTip = "";

    // ИСПРАВЛЕННАЯ ЛОГИКА ОТОБРАЖЕНИЯ СОВЕТОВ ТРЕНЕРА
    if (ex.notes != null && ex.notes!.isNotEmpty) {
      if (ex.notes!.contains('💡')) {
        // Это ИИ с эмодзи лампочки
        final parts = ex.notes!.split('💡');
        targetText = parts[0].trim(); 
        coachTip = parts.sublist(1).join('💡').trim(); 
      } else if (ex.notes!.contains('🎯') || ex.notes!.contains('Подходы:')) {
        // Это просто таргеты ИИ без лампочки
        targetText = ex.notes!.trim();
      } else {
        // Это комментарий от живого тренера! Показываем его как красивый совет.
        coachTip = ex.notes!.trim();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), 
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cleanName.tr(),
                  style: const TextStyle(color: Color(0xFF9CD600), fontSize: 18, fontWeight: FontWeight.bold),
                ),
                
                if (targetText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    targetText, 
                    style: TextStyle(color: Colors.grey[400], fontSize: 13, fontStyle: FontStyle.italic),
                  ),
                ],

                if (coachTip.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFCCFF00).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.2)),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          iconColor: const Color(0xFFCCFF00),
                          collapsedIconColor: const Color(0xFFCCFF00),
                          title: const Row(
                            children: [
                              Icon(Icons.lightbulb_outline, color: Color(0xFFCCFF00), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Комментарий тренера', 
                                style: TextStyle(color: Color(0xFFCCFF00), fontSize: 13, fontWeight: FontWeight.bold)
                              ),
                            ],
                          ),
                          children: [
                            Text(
                              coachTip.replaceAll(RegExp(r'(Совет\s*:|notes\s*:)'), '').trim(), 
                              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: ex.noteController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Ваша заметка...',
                hintStyle: TextStyle(color: Colors.grey.withOpacity(0.4)),
                filled: true, 
                fillColor: Colors.black.withOpacity(0.3),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                isDense: true,
                prefixIcon: const Icon(Icons.edit_note, color: Colors.grey, size: 18),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 30, child: Text("#", style: TextStyle(color: Colors.grey, fontSize: 12))), 
                Expanded(child: Center(child: Text('kg'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12)))), 
                const SizedBox(width: 10),
                Expanded(child: Center(child: Text('reps_short'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12)))),
                const SizedBox(width: 40),
              ],
            ),
          ),

          const SizedBox(height: 8),

          ...List.generate(ex.sets.length, (i) {
            final s = ex.sets[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 30, 
                    child: Text("${i + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ),
                  Expanded(child: _input(s.weightController, true)),
                  const SizedBox(width: 10),
                  Expanded(child: _input(s.repsController, false)),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20), 
                    onPressed: () {
                      if (ex.sets.length > 1) {
                        setState(() => ex.sets.removeAt(i));
                      }
                    },
                  )
                ],
              ),
            );
          }),

          InkWell(
            onTap: () => setState(() => ex.sets.add(WorkoutSet())),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, color: Color(0xFFCCFF00), size: 16),
                  const SizedBox(width: 4),
                  Text('add_set'.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, bool isDec) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black, 
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10)
      ),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: isDec),
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
        cursorColor: const Color(0xFFCCFF00),
        decoration: const InputDecoration(
          border: InputBorder.none, 
          contentPadding: EdgeInsets.only(bottom: 4)
        ),
      ),
    );
  }
}