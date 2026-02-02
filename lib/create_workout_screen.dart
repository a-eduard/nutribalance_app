import 'package:flutter/material.dart';
import 'exercise_data.dart';
import 'exercise_selection_screen.dart';
import 'ui_widgets.dart';
import 'services/database_service.dart';

class CreateWorkoutScreen extends StatefulWidget {
  final String? docId;
  final String? initialName;
  final List<String>? initialExercises;
  final Map<String, String>? initialTargets; // <--- ПРИНИМАЕМ ЦЕЛИ

  const CreateWorkoutScreen({
    super.key, 
    this.docId, 
    this.initialName, 
    this.initialExercises,
    this.initialTargets,
  });

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  late TextEditingController _nameController;
  final List<Exercise> _selectedExercises = [];
  
  // Храним контроллеры для ввода целей: Ключ = ID упражнения (временный)
  final Map<String, TextEditingController> _targetControllers = {}; 
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? "");

    // Инициализация при редактировании
    if (widget.initialExercises != null) {
      for (var name in widget.initialExercises!) {
        final newExercise = Exercise(
            id: DateTime.now().toString() + name, // Уникальный ID для UI
            title: name, 
            muscleGroup: "Сохраненное"
        );
        _selectedExercises.add(newExercise);
        
        // Достаем цель, если есть
        String existingTarget = "";
        if (widget.initialTargets != null && widget.initialTargets!.containsKey(name)) {
          existingTarget = widget.initialTargets![name]!;
        }
        _targetControllers[newExercise.id] = TextEditingController(text: existingTarget);
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()),
    );

    if (result != null && result is List<Exercise>) {
      setState(() {
        for (var ex in result) {
           // Создаем копию упражнения с уникальным ID для этого экрана
           // чтобы контроллеры не путались
           final uniqueId = DateTime.now().millisecondsSinceEpoch.toString() + ex.title;
           final newEx = Exercise(id: uniqueId, title: ex.title, muscleGroup: ex.muscleGroup);
           
           _selectedExercises.add(newEx);
           _targetControllers[uniqueId] = TextEditingController(); // Пустой контроллер
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
      _targetControllers[ex.id]?.dispose(); // Чистим память
      _targetControllers.remove(ex.id);
      _selectedExercises.removeAt(index);
    });
  }

  Future<void> _saveWorkout() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название'), backgroundColor: Colors.red));
      return;
    }
    if (_selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Добавьте упражнения'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 1. Собираем список имен
      List<String> exerciseNames = _selectedExercises.map((e) => e.title).toList();
      
      // 2. Собираем карту целей (Имя -> Цель)
      Map<String, String> targetsMap = {};
      for (var ex in _selectedExercises) {
        final text = _targetControllers[ex.id]?.text.trim() ?? "";
        if (text.isNotEmpty) {
          targetsMap[ex.title] = text;
        }
      }

      if (widget.docId == null) {
        await DatabaseService().saveUserWorkout(name, exerciseNames, targetsMap);
      } else {
        await DatabaseService().updateWorkout(widget.docId!, name, exerciseNames, targetsMap);
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
    final pageTitle = widget.docId == null ? 'Новая тренировка' : 'Редактирование';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text(pageTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          _isSaving 
            ? const Padding(padding: EdgeInsets.only(right: 16), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFCCFF00), strokeWidth: 2))))
            : TextButton(onPressed: _saveWorkout, child: const Text('СОХРАНИТЬ', style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)))
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF0F0F0F),
        child: IgnorePointer(
          ignoring: _isSaving,
          child: Opacity(
            opacity: _isSaving ? 0.5 : 1.0,
            child: NeonActionButton(text: "ДОБАВИТЬ УПРАЖНЕНИЕ", onTap: _navigateAndAddExercise, isFullWidth: true),
          ),
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
                decoration: const InputDecoration(
                  hintText: 'Название (напр. Спина)',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  suffixIcon: Icon(Icons.edit, color: Color(0xFFCCFF00)),
                ),
                enabled: !_isSaving,
              ),
            ),
            const Divider(color: Colors.white10),
            Expanded(
              child: _selectedExercises.isEmpty
                  ? Center(child: Text('Список пуст', style: TextStyle(color: Colors.white.withOpacity(0.3))))
                  : ReorderableListView.builder(
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
                                      // ПОЛЕ ВВОДА ЦЕЛИ
                                      Container(
                                        height: 36,
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: TextField(
                                          controller: _targetControllers[exercise.id],
                                          style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 14),
                                          decoration: const InputDecoration(
                                            hintText: "Цель (напр. 3x12)",
                                            hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                                            border: InputBorder.none,
                                            icon: Icon(Icons.track_changes, size: 14, color: Colors.grey),
                                            contentPadding: EdgeInsets.only(bottom: 12)
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