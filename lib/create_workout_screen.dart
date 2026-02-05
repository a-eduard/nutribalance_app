import 'package:flutter/material.dart';
import 'exercise_data.dart';
import 'exercise_selection_screen.dart';
import 'services/database_service.dart';
import 'ui_widgets.dart';

class CreateWorkoutScreen extends StatefulWidget {
  // Новые поля для режима редактирования
  final Workout? existingWorkout;
  final String? docId;

  const CreateWorkoutScreen({
    super.key, 
    this.existingWorkout, 
    this.docId
  });

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  final TextEditingController _nameController = TextEditingController();
  List<Exercise> _selectedExercises = [];
  Map<String, String> _targets = {}; // Цели: "4x10"

  @override
  void initState() {
    super.initState();
    
    // ЕСЛИ РЕДАКТИРОВАНИЕ -> ЗАПОЛНЯЕМ ПОЛЯ
    if (widget.existingWorkout != null) {
      _nameController.text = widget.existingWorkout!.name;
      _selectedExercises = List.from(widget.existingWorkout!.exercises);
      _targets = Map.from(widget.existingWorkout!.targets);
    }
  }

  void _addExercises() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()),
    );

    if (result != null && result is List<Exercise>) {
      setState(() {
        for (var ex in result) {
          if (!_selectedExercises.any((e) => e.title == ex.title)) {
            _selectedExercises.add(ex);
          }
        }
      });
    }
  }

  void _removeExercise(int index) {
    setState(() {
      _targets.remove(_selectedExercises[index].title);
      _selectedExercises.removeAt(index);
    });
  }

  void _editTarget(String exerciseTitle) {
    TextEditingController controller = TextEditingController(text: _targets[exerciseTitle] ?? "");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(exerciseTitle, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Цель (напр. 4x10)",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFCCFF00))),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _targets[exerciseTitle] = controller.text);
              Navigator.pop(context);
            },
            child: const Text("OK", style: TextStyle(color: Color(0xFFCCFF00))),
          )
        ],
      ),
    );
  }

  void _saveWorkout() async {
    if (_nameController.text.isEmpty || _selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Введите название и добавьте упражнения")),
      );
      return;
    }

    final exerciseNames = _selectedExercises.map((e) => e.title).toList();

    try {
      if (widget.existingWorkout != null && widget.docId != null) {
        // РЕЖИМ РЕДАКТИРОВАНИЯ (UPDATE)
        await DatabaseService().updateWorkout(
          widget.docId!,
          _nameController.text,
          exerciseNames,
          _targets,
        );
      } else {
        // РЕЖИМ СОЗДАНИЯ (CREATE)
        await DatabaseService().saveUserWorkout(
          _nameController.text,
          exerciseNames,
          _targets,
        );
      }
      
      if (mounted) Navigator.pop(context);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isEditing = widget.existingWorkout != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(
          isEditing ? "Редактировать" : "Новая программа", 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFCCFF00),
        onPressed: _saveWorkout,
        icon: const Icon(Icons.save, color: Colors.black),
        label: Text(
          isEditing ? "СОХРАНИТЬ" : "СОЗДАТЬ", 
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeavyInput(
              controller: _nameController, 
              hint: "Название тренировки",
              onChanged: (v){},
            ),
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("УПРАЖНЕНИЯ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _addExercises,
                  icon: const Icon(Icons.add, size: 16, color: Color(0xFFCCFF00)),
                  label: const Text("ДОБАВИТЬ", style: TextStyle(color: Color(0xFFCCFF00), fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 12),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _selectedExercises.length,
              itemBuilder: (context, index) {
                final exercise = _selectedExercises[index];
                final target = _targets[exercise.title] ?? "";
                
                return Dismissible(
                  key: Key(exercise.title),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeExercise(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    color: Colors.red.withOpacity(0.2),
                    padding: const EdgeInsets.only(right: 16),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: PremiumGlassCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(exercise.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(exercise.muscleGroup, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: GestureDetector(
                          onTap: () => _editTarget(exercise.title),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: target.isNotEmpty ? const Color(0xFFCCFF00) : Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              target.isNotEmpty ? target : "Цель?",
                              style: TextStyle(
                                color: target.isNotEmpty ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}