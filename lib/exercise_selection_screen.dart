import 'package:flutter/material.dart';
import 'exercise_data.dart';
import 'ui_widgets.dart'; // <--- ВАЖНЫЙ ИМПОРТ

class ExerciseSelectionScreen extends StatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  State<ExerciseSelectionScreen> createState() => _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'Все';
  final List<Exercise> _selectedExercises = [];
  final List<String> _categories = ['Все', 'Грудь', 'Спина', 'Ноги', 'Руки', 'Плечи', 'Пресс'];

  List<Exercise> get _filteredExercises {
    return mockExercises.where((exercise) {
      final matchesSearch = exercise.title.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'Все' || exercise.muscleGroup == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  void _toggleSelection(Exercise exercise) {
    setState(() {
      if (_selectedExercises.contains(exercise)) {
        _selectedExercises.remove(exercise);
      } else {
        _selectedExercises.add(exercise);
      }
    });
  }

  void _showAddCustomExerciseDialog() {
    final TextEditingController nameController = TextEditingController();
    String selectedMuscle = 'Грудь';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Text("Новое упражнение", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: "Название (напр. Берпи)"),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(16)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedMuscle,
                        dropdownColor: const Color(0xFF2C2C2E),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white),
                        items: _categories.where((c) => c != 'Все').map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: (newValue) => setDialogState(() => selectedMuscle = newValue!),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ОТМЕНА", style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final newExercise = Exercise(
                        id: DateTime.now().toString(),
                        title: nameController.text,
                        muscleGroup: selectedMuscle,
                      );
                      WorkoutDataService.addCustomExercise(newExercise);
                      setState(() {});
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("ДОБАВИТЬ", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFCCFF00)),
            onPressed: _showAddCustomExerciseDialog,
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Поиск упражнения...',
                prefixIcon: Icon(Icons.search, color: Color(0xFF8E8E93)),
                filled: true,
                fillColor: Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16)), borderSide: BorderSide.none),
              ),
            ),
          ),
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
                      if (selected) setState(() => _selectedCategory = category);
                    },
                    selectedColor: const Color(0xFFCCFF00),
                    backgroundColor: const Color(0xFF1C1C1E),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _filteredExercises.length,
              itemBuilder: (context, index) {
                final exercise = _filteredExercises[index];
                final isSelected = _selectedExercises.contains(exercise);

                return PremiumGlassCard(
                  onTap: () => _toggleSelection(exercise),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.title, 
                            style: TextStyle(
                              color: isSelected ? const Color(0xFFCCFF00) : Colors.white, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 16
                            )
                          ),
                          const SizedBox(height: 4),
                          Text(exercise.muscleGroup, style: const TextStyle(color: Color(0xFF8E8E93))),
                        ],
                      ),
                      Icon(
                        isSelected ? Icons.check_circle : Icons.add_circle,
                        color: isSelected ? const Color(0xFFCCFF00) : const Color(0xFF8E8E93),
                        size: 32,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectedExercises.isNotEmpty 
        ? Container(
            color: const Color(0xFF0F0F0F),
            padding: const EdgeInsets.all(24),
            child: NeonActionButton(
              text: "ДОБАВИТЬ (${_selectedExercises.length})",
              onTap: () => Navigator.of(context).pop(_selectedExercises),
            ),
          )
        : null,
    );
  }
}