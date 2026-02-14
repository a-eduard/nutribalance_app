import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../exercise_data.dart';
import '../services/database_service.dart';

// Класс модели упражнения
class ExerciseItem {
  final String id;
  final String title;
  final String muscleGroup;
  final bool isCustom;

  ExerciseItem({
    required this.id, 
    required this.title, 
    required this.muscleGroup,
    this.isCustom = false,
  });
}

class ExerciseSelectionScreen extends StatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  State<ExerciseSelectionScreen> createState() => _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  String _selectedCategory = 'Все';
  String _searchQuery = '';
  
  // Список выбранных упражнений (для мультивыбора)
  final Set<String> _selectedExercises = {};

  final List<String> _categories = ['Все', 'Грудь', 'Спина', 'Ноги', 'Руки', 'Плечи', 'Пресс', 'Другое'];

  void _toggleSelection(String exerciseName) {
    setState(() {
      if (_selectedExercises.contains(exerciseName)) {
        _selectedExercises.remove(exerciseName);
      } else {
        _selectedExercises.add(exerciseName);
      }
    });
  }

  void _finishSelection() {
    Navigator.pop(context, _selectedExercises.toList());
  }

  void _showAddCustomExerciseDialog() {
    final titleController = TextEditingController();
    String selectedMuscle = 'Грудь';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Новое упражнение", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "Название",
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedMuscle,
              dropdownColor: const Color(0xFF2C2C2E),
              items: _categories.where((c) => c != 'Все').map((c) => 
                DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(color: Colors.white)))
              ).toList(),
              onChanged: (v) => selectedMuscle = v!,
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () {
              if (titleController.text.isNotEmpty) {
                DatabaseService().addCustomExercise(titleController.text, selectedMuscle);
                Navigator.pop(ctx);
              }
            }, 
            child: const Text("Создать", style: TextStyle(color: Color(0xFFCCFF00)))
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        title: const Text("Библиотека"),
        backgroundColor: const Color(0xFF1C1C1E),
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFCCFF00)),
            onPressed: _showAddCustomExerciseDialog,
          )
        ],
      ),
      // ПЛАВАЮЩАЯ КНОПКА ПОДТВЕРЖДЕНИЯ
      floatingActionButton: _selectedExercises.isNotEmpty 
          ? FloatingActionButton.extended(
              onPressed: _finishSelection,
              backgroundColor: const Color(0xFFCCFF00),
              label: Text("ДОБАВИТЬ (${_selectedExercises.length})", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.check, color: Colors.black),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Поиск упражнения...",
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      setState(() => _selectedCategory = cat);
                    },
                    backgroundColor: const Color(0xFF1C1C1E),
                    selectedColor: const Color(0xFFCCFF00),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? Colors.transparent : Colors.white24)
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 16),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService().getCustomExercises(),
              builder: (context, snapshot) {
                List<ExerciseItem> allExercises = [];

                ExerciseData.library.forEach((category, names) {
                  for (var name in names) {
                    allExercises.add(ExerciseItem(id: name, title: name, muscleGroup: category, isCustom: false));
                  }
                });

                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    allExercises.add(ExerciseItem(
                      id: doc.id,
                      title: data['title'] ?? 'Без названия',
                      muscleGroup: data['muscleGroup'] ?? 'Другое',
                      isCustom: true
                    ));
                  }
                }

                final filteredList = allExercises.where((ex) {
                  final matchesCategory = _selectedCategory == 'Все' || ex.muscleGroup == _selectedCategory;
                  final matchesSearch = ex.title.toLowerCase().contains(_searchQuery.toLowerCase());
                  return matchesCategory && matchesSearch;
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80), // Отступ под FAB
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    final exercise = filteredList[index];
                    final isSelected = _selectedExercises.contains(exercise.title);

                    return GestureDetector(
                      onTap: () => _toggleSelection(exercise.title),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFCCFF00).withValues(alpha: 0.1) : const Color(0xFF1C1C1E), // Исправлено withOpacity -> withValues
                          borderRadius: BorderRadius.circular(12),
                          border: isSelected ? Border.all(color: const Color(0xFFCCFF00)) : null,
                        ),
                        child: ListTile(
                          title: Text(exercise.title, style: TextStyle(color: isSelected ? const Color(0xFFCCFF00) : Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(exercise.muscleGroup, style: TextStyle(color: isSelected ? Colors.white70 : Colors.grey, fontSize: 12)),
                          trailing: exercise.isCustom
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => DatabaseService().deleteExercise(exercise.id),
                                )
                              : (isSelected 
                                  ? const Icon(Icons.check_circle, color: Color(0xFFCCFF00))
                                  : const Icon(Icons.circle_outlined, color: Colors.grey)
                                ),
                        ),
                      ),
                    );
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