import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <--- ВАЖНО
import 'exercise_data.dart';
import 'exercise_selection_screen.dart';
import 'ui_widgets.dart';
import 'services/database_service.dart';

class CreateWorkoutScreen extends StatefulWidget {
  // Вместо кучи параметров принимаем один документ (если редактируем)
  final DocumentSnapshot? existingWorkout;

  const CreateWorkoutScreen({super.key, this.existingWorkout});

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  late TextEditingController _nameController;
  final List<Exercise> _selectedExercises = [];
  
  // Контроллеры для целей: Ключ = ID упражнения (уникальный)
  final Map<String, TextEditingController> _targetControllers = {};
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();

    // ЛОГИКА ЗАПОЛНЕНИЯ ДАННЫМИ (ЕСЛИ РЕДАКТИРУЕМ)
    if (widget.existingWorkout != null) {
      final data = widget.existingWorkout!.data() as Map<String, dynamic>;
      
      // 1. Название
      _nameController.text = data['name'] ?? '';

      // 2. Упражнения и Цели
      if (data['exercises'] != null) {
        final exercisesList = List<String>.from(data['exercises']);
        final targetsMap = data['targets'] != null 
            ? Map<String, String>.from(data['targets']) 
            : <String, String>{};

        for (var name in exercisesList) {
          // Генерируем уникальный ID для UI
          final uniqueId = DateTime.now().millisecondsSinceEpoch.toString() + name + _selectedExercises.length.toString();
          
          // Добавляем упражнение в список
          _selectedExercises.add(Exercise(
            id: uniqueId, 
            title: name, 
            muscleGroup: "Сохраненное" // Можно не уточнять, это для UI
          ));
          
          // Создаем контроллер и сразу вписываем туда старую цель
          String existingTarget = targetsMap[name] ?? "";
          _targetControllers[uniqueId] = TextEditingController(text: existingTarget);
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (var c in _targetControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _navigateAndAddExercise() async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()));
    if (result != null && result is List<Exercise>) {
      setState(() {
        for (var ex in result) {
           final uniqueId = DateTime.now().millisecondsSinceEpoch.toString() + ex.title;
           _selectedExercises.add(Exercise(id: uniqueId, title: ex.title, muscleGroup: ex.muscleGroup));
           _targetControllers[uniqueId] = TextEditingController(); 
        }
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final Exercise item = _selectedExercises.removeAt(oldIndex);
      _selectedExercises.insert(newIndex, item);
    });
  }

  void _removeExercise(int index) {
    setState(() {
      final ex = _selectedExercises[index];
      _targetControllers[ex.id]?.dispose();
      _targetControllers.remove(ex.id);
      _selectedExercises.removeAt(index);
    });
  }

  Future<void> _saveWorkout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название и добавьте упражнения'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isSaving = true);

    try {
      List<String> exerciseNames = _selectedExercises.map((e) => e.title).toList();
      
      // Собираем карту целей
      Map<String, String> targetsToSave = {};
      for (var ex in _selectedExercises) {
        String text = _targetControllers[ex.id]?.text.trim() ?? "";
        if (text.isNotEmpty) {
          targetsToSave[ex.title] = text;
        }
      }

      // ГЛАВНОЕ ИЗМЕНЕНИЕ: ПРОВЕРКА НА REUPDATE
      if (widget.existingWorkout != null) {
        // ОБНОВЛЕНИЕ
        await DatabaseService().updateWorkout(
          widget.existingWorkout!.id, 
          name, 
          exerciseNames, 
          targetsToSave
        );
      } else {
        // СОЗДАНИЕ
        await DatabaseService().saveUserWorkout(name, exerciseNames, targetsToSave);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingWorkout != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(isEditing ? 'Редактировать' : 'Новая тренировка', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _isSaving 
            ? const Center(child: Padding(padding: EdgeInsets.only(right: 16), child: CircularProgressIndicator(color: Color(0xFFCCFF00))))
            : TextButton(onPressed: _saveWorkout, child: const Text('СОХРАНИТЬ', style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)))
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF0F0F0F),
        child: Opacity(
          opacity: _isSaving ? 0.5 : 1.0,
          child: NeonActionButton(text: "ДОБАВИТЬ УПРАЖНЕНИЕ", onTap: _isSaving ? () {} : _navigateAndAddExercise, isFullWidth: true),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                decoration: const InputDecoration(hintText: 'Название (напр. Спина)', hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none, suffixIcon: Icon(Icons.edit, color: Color(0xFFCCFF00))),
                enabled: !_isSaving,
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: _selectedExercises.length,
                onReorder: _onReorder,
                buildDefaultDragHandles: !_isSaving,
                itemBuilder: (context, index) {
                  final exercise = _selectedExercises[index];
                  return Container(
                    key: ValueKey(exercise.id),
                    child: PremiumGlassCard(
                      child: Row(
                        children: [
                          const Icon(Icons.drag_handle, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(exercise.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 8),
                                Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                                  child: TextField(
                                    controller: _targetControllers[exercise.id],
                                    style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 14),
                                    decoration: const InputDecoration(
                                      hintText: "Цель (напр. 4x12)", 
                                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13), 
                                      border: InputBorder.none,
                                      icon: Icon(Icons.notes, size: 16, color: Colors.grey)
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFFF453A)), onPressed: _isSaving ? null : () => _removeExercise(index)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}