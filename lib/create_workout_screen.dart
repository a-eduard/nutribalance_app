import 'package:flutter/material.dart';
import 'exercise_data.dart';
import 'exercise_selection_screen.dart';
import 'ui_widgets.dart'; // Виджеты дизайна
import 'services/database_service.dart'; // <--- ПОДКЛЮЧЕНИЕ К БАЗЕ

class CreateWorkoutScreen extends StatefulWidget {
  // Новые поля для режима Редактирования
  final String? docId;
  final String? initialName;
  final List<String>? initialExercises;

  const CreateWorkoutScreen({
    super.key, 
    this.docId, 
    this.initialName, 
    this.initialExercises
  });

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  late TextEditingController _nameController;
  final List<Exercise> _selectedExercises = [];
  
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 1. Инициализация контроллера (если редактируем - ставим старое имя)
    _nameController = TextEditingController(text: widget.initialName ?? "");

    // 2. Инициализация списка (превращаем строки названий в объекты Exercise)
    if (widget.initialExercises != null) {
      for (var name in widget.initialExercises!) {
        _selectedExercises.add(
          Exercise(
            id: DateTime.now().toString(), // Временный ID для UI
            title: name, 
            muscleGroup: "Сохраненное" // Заглушка, так как мы храним только имена
          )
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _navigateAndAddExercise() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()),
    );

    if (result != null && result is List<Exercise>) {
      setState(() {
        _selectedExercises.addAll(result);
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
      _selectedExercises.removeAt(index);
    });
  }

  // --- УМНАЯ ЛОГИКА СОХРАНЕНИЯ ---
  Future<void> _saveWorkout() async {
    final name = _nameController.text.trim();
    
    // Валидация
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите название тренировки'), backgroundColor: Colors.red)
      );
      return;
    }
    
    if (_selectedExercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно упражнение'), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      List<String> exerciseNames = _selectedExercises.map((e) => e.title).toList();

      if (widget.docId == null) {
        // РЕЖИМ СОЗДАНИЯ
        await DatabaseService().saveUserWorkout(name, exerciseNames);
      } else {
        // РЕЖИМ РЕДАКТИРОВАНИЯ
        await DatabaseService().updateWorkout(widget.docId!, name, exerciseNames);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Меняем заголовок в зависимости от режима
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
            ? const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 20, height: 20, 
                    child: CircularProgressIndicator(color: Color(0xFFCCFF00), strokeWidth: 2)
                  ),
                ),
              )
            : TextButton(
                onPressed: _saveWorkout,
                child: const Text(
                  'СОХРАНИТЬ', 
                  style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)
                ),
              )
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFF0F0F0F),
        child: IgnorePointer(
          ignoring: _isSaving,
          child: Opacity(
            opacity: _isSaving ? 0.5 : 1.0,
            child: NeonActionButton(
              text: "ДОБАВИТЬ УПРАЖНЕНИЕ",
              onTap: _navigateAndAddExercise,
              isFullWidth: true,
            ),
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fitness_center, size: 48, color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          Text(
                            'Список пуст',
                            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _selectedExercises.length,
                      onReorder: _onReorder,
                      buildDefaultDragHandles: !_isSaving,
                      itemBuilder: (context, index) {
                        final exercise = _selectedExercises[index];
                        return Container(
                          key: ValueKey("${exercise.id}_${index}_${DateTime.now().millisecondsSinceEpoch}"),
                          child: PremiumGlassCard(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.drag_handle, color: Color(0xFF8E8E93)),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          exercise.title, 
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          exercise.muscleGroup, 
                                          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFFF453A)),
                                  onPressed: _isSaving ? null : () => _removeExercise(index),
                                ),
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