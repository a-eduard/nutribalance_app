import 'package:flutter/material.dart';
import 'exercise_data.dart';
import 'exercise_selection_screen.dart';

class CreateWorkoutScreen extends StatefulWidget {
  const CreateWorkoutScreen({super.key});

  @override
  State<CreateWorkoutScreen> createState() => _CreateWorkoutScreenState();
}

class _CreateWorkoutScreenState extends State<CreateWorkoutScreen> {
  final TextEditingController _nameController = TextEditingController();

  // Список выбранных упражнений
  final List<Exercise> _selectedExercises = [];

  // Метод открытия экрана выбора
  Future<void> _navigateAndAddExercise() async {
    // Ждем, пока пользователь выберет что-то и вернется
    final Exercise? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExerciseSelectionScreen()),
    );

    // Если упражнение выбрано, добавляем в список
    if (result != null) {
      setState(() {
        _selectedExercises.add(result);
      });
    }
  }

  // Логика перетаскивания
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final Exercise item = _selectedExercises.removeAt(oldIndex);
      _selectedExercises.insert(newIndex, item);
    });
  }

  // Удаление упражнения из списка
  void _removeExercise(int index) {
    setState(() {
      _selectedExercises.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая тренировка'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              // Тут будет логика сохранения в БД
              if (_nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите название тренировки')),
                );
                return;
              }
              Navigator.pop(context); // Просто выходим назад
            },
            child: const Text(
              'СОХРАНИТЬ',
              style: TextStyle(
                color: Color(0xFFCCFF00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      // Кнопка добавления внизу
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateAndAddExercise,
        backgroundColor: const Color(0xFFCCFF00),
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text(
          'ДОБАВИТЬ УПРАЖНЕНИЕ',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // Скрыть клавиатуру
        child: Column(
          children: [
            // 1. Название тренировки
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: 'Название (напр. День груди)',
                  hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                  border: InputBorder.none, // Без рамки, как заголовок
                ),
              ),
            ),

            const Divider(color: Color(0xFF2C2C2E)),

            // 2. Список упражнений (Drag & Drop)
            Expanded(
              child: _selectedExercises.isEmpty
                  ? Center(
                      child: Text(
                        'Список упражнений пуст',
                        style: TextStyle(color: Colors.grey.withOpacity(0.5)),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(
                        bottom: 100,
                      ), // Отступ под кнопку
                      itemCount: _selectedExercises.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final exercise = _selectedExercises[index];
                        // Ключ обязателен для ReorderableListView
                        return Container(
                          key: ValueKey(
                            "${exercise.id}_$index",
                          ), // Уникальный ключ
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const Icon(
                              Icons.drag_handle,
                              color: Color(0xFF8E8E93),
                            ),
                            title: Text(
                              exercise.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              exercise.muscleGroup,
                              style: const TextStyle(color: Color(0xFF8E8E93)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Color(0xFFFF453A),
                              ),
                              onPressed: () => _removeExercise(index),
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
