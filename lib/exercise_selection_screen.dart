import 'package:flutter/material.dart';
import 'exercise_data.dart'; // Подключаем наши данные

class ExerciseSelectionScreen extends StatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  State<ExerciseSelectionScreen> createState() =>
      _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  // Состояние поиска и фильтров
  String _searchQuery = '';
  String _selectedCategory = 'Все';

  final List<String> _categories = [
    'Все',
    'Грудь',
    'Спина',
    'Ноги',
    'Руки',
    'Плечи',
    'Пресс',
  ];

  // Логика фильтрации списка
  List<Exercise> get _filteredExercises {
    return mockExercises.where((exercise) {
      final matchesSearch = exercise.title.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      final matchesCategory =
          _selectedCategory == 'Все' ||
          exercise.muscleGroup == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека упражнений'),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Поле поиска
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Поиск упражнения...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF8E8E93)),
                filled: true,
                fillColor: Color(0xFF2C2C2E),
              ),
            ),
          ),

          // 2. Горизонтальные фильтры (Chips)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      }
                    },
                    // Цвета: Лайм если выбран, Серый если нет
                    selectedColor: const Color(0xFFCCFF00),
                    backgroundColor: const Color(0xFF2C2C2E),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // 3. Список результатов
          Expanded(
            child: ListView.separated(
              itemCount: _filteredExercises.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: Color(0xFF2C2C2E)),
              itemBuilder: (context, index) {
                final exercise = _filteredExercises[index];
                return ListTile(
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
                  trailing: const Icon(
                    Icons.add_circle_outline,
                    color: Color(0xFFCCFF00),
                  ),
                  onTap: () {
                    // ГЛАВНАЯ МАГИЯ: Возвращаем выбранное упражнение назад
                    Navigator.of(context).pop(exercise);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
