import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';

import '../ui_widgets.dart'; 
import '../exercise_selection_screen.dart';
import '../services/push_notification_service.dart';

class WorkoutExerciseItem {
  String name;
  String comment;
  WorkoutExerciseItem({required this.name, this.comment = ''});
}

class AssignWorkoutScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  final String? existingWorkoutId;
  final Map<String, dynamic>? existingWorkoutData;

  const AssignWorkoutScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.existingWorkoutId,
    this.existingWorkoutData,
  });

  @override
  State<AssignWorkoutScreen> createState() => _AssignWorkoutScreenState();
}

class _AssignWorkoutScreenState extends State<AssignWorkoutScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<WorkoutExerciseItem> _exercises = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingWorkoutData != null) {
      _nameController.text = widget.existingWorkoutData!['name'] ?? "";
      final rawExercises = List<String>.from(widget.existingWorkoutData!['exercises'] ?? []);
      final targets = Map<String, String>.from(widget.existingWorkoutData!['targets'] ?? {});
      
      _exercises = rawExercises.map((name) {
        String comment = "";
        if (targets.containsKey(name)) {
          final parts = targets[name]!.split('|');
          if (parts.length > 1) comment = parts[1];
        }
        return WorkoutExerciseItem(name: name, comment: comment);
      }).toList();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _openLibrary() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()),
    );

    if (result != null && result is List<String>) {
      setState(() {
        for (var name in result) {
          _exercises.add(WorkoutExerciseItem(name: name));
        }
      });
    }
  }

  void _removeExercise(int index) {
    setState(() => _exercises.removeAt(index));
  }

  Future<void> _saveAssignedWorkout() async {
    if (_nameController.text.trim().isEmpty || _exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('fill_name_and_exercises'.tr()), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<String> namesList = _exercises.map((e) => e.name).toList();
      Map<String, String> targets = {};
      
      for (var ex in _exercises) {
        String val = "0x0"; 
        if (ex.comment.isNotEmpty) {
          val += "|${ex.comment}";
        }
        targets[ex.name] = val;
      }

      final dataToSave = {
        'name': _nameController.text.trim(),
        'exercises': namesList,
        'targets': targets,
        'date': Timestamp.now(),
        'isCompleted': false,
      };

      if (widget.existingWorkoutId != null) {
        // ОБНОВЛЕНИЕ СУЩЕСТВУЮЩЕЙ
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.clientId)
            .collection('assigned_workouts')
            .doc(widget.existingWorkoutId)
            .update(dataToSave);
            
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('updated_successfully'.tr()), backgroundColor: const Color(0xFFCCFF00)));
      } else {
        // СОЗДАНИЕ НОВОЙ
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.clientId)
            .collection('assigned_workouts')
            .add(dataToSave);
            
        // --- БЛОК ОТПРАВКИ PUSH-УВЕДОМЛЕНИЯ КЛИЕНТУ С ЛОГАМИ ---
        try {
          debugPrint('--- НАЧАЛО ОТПРАВКИ ПУША (ТРЕНИРОВКА) ---');
          final clientDoc = await FirebaseFirestore.instance.collection('users').doc(widget.clientId).get();
          
          if (clientDoc.exists) {
            debugPrint('FCM: Документ клиента найден!');
            if (clientDoc.data()!.containsKey('fcmToken')) {
              String clientToken = clientDoc.data()!['fcmToken'];
              debugPrint('FCM: Токен найден: $clientToken. Отправляем запрос на сервер...');
              
              PushNotificationService.sendPushMessage(
                token: clientToken,
                title: 'Новая тренировка! 🏋️',
                body: 'Тренер назначил вам новую программу. Заходите в приложение!',
              ).then((_) {
                debugPrint('FCM: Запрос на сервер отправлен успешно!');
              });
            } else {
              debugPrint('FCM ОШИБКА: У клиента нет поля fcmToken в базе!');
            }
          } else {
            debugPrint('FCM ОШИБКА: Документ клиента не найден в базе!');
          }
        } catch (e) {
          debugPrint('FCM КРИТИЧЕСКАЯ ОШИБКА отправки уведомления: $e');
        }
        // ----------------------------------------------
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
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: Text(
          widget.existingWorkoutId != null ? 'edit_program'.tr() : 'new_program'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        leading: const BackButton(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "КЛИЕНТ: ${widget.clientName.toUpperCase()}", 
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)
            ),
            const SizedBox(height: 24),

            Text('program_name'.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'program_name_hint'.tr(),
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)), 
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),

            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('exercises'.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: _openLibrary,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFCCFF00), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.list, color: Colors.black, size: 18),
                        const SizedBox(width: 8),
                        Text('open_database'.tr(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_exercises.isEmpty)
              Container(
                 width: double.infinity,
                 padding: const EdgeInsets.all(40),
                 child: Center(
                   child: Text('list_empty'.tr(), style: TextStyle(color: Colors.white.withOpacity(0.2))), 
                 ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _exercises.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _exercises.removeAt(oldIndex);
                    _exercises.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  return Container(
                    key: ValueKey(_exercises[index]),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text("${index + 1}. ${_exercises[index].name.tr()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                            Row(
                              children: [
                                const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () => _removeExercise(index),
                                  child: const Icon(Icons.close, color: Colors.red, size: 20),
                                ),
                              ],
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: TextEditingController(text: _exercises[index].comment),
                          onChanged: (val) => _exercises[index].comment = val,
                          style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'comment_optional'.tr(),
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)), 
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFCCFF00))),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: 40),
            _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
                : NeonActionButton(
                    text: widget.existingWorkoutId != null ? 'save_changes'.tr() : 'create_program'.tr(), 
                    onTap: _saveAssignedWorkout, 
                    isFullWidth: true
                  ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}