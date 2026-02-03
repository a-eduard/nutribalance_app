import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'exercise_data.dart';
import 'ui_widgets.dart';
import 'services/database_service.dart';

class ExerciseSelectionScreen extends StatefulWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  State<ExerciseSelectionScreen> createState() => _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState extends State<ExerciseSelectionScreen> {
  final List<Exercise> _selected = [];
  String _selectedFilter = 'Все'; // Текущий фильтр

  // 1. СТРУКТУРИРОВАННЫЙ СПИСОК (КАТЕГОРИИ)
  final List<Map<String, String>> _defaultExercises = [
    {'name': 'Жим штанги лежа', 'group': 'Грудь'},
    {'name': 'Жим гантелей', 'group': 'Грудь'},
    {'name': 'Сведение в кроссовере', 'group': 'Грудь'},
    {'name': 'Отжимания на брусьях', 'group': 'Грудь'},
    {'name': 'Подтягивания', 'group': 'Спина'},
    {'name': 'Тяга штанги в наклоне', 'group': 'Спина'},
    {'name': 'Тяга верхнего блока', 'group': 'Спина'},
    {'name': 'Приседания', 'group': 'Ноги'},
    {'name': 'Жим ногами', 'group': 'Ноги'},
    {'name': 'Разгибание ног', 'group': 'Ноги'},
    {'name': 'Бицепс со штангой', 'group': 'Руки'},
    {'name': 'Французский жим', 'group': 'Руки'},
    {'name': 'Молотки', 'group': 'Руки'},
    {'name': 'Армейский жим', 'group': 'Плечи'},
    {'name': 'Махи в стороны', 'group': 'Плечи'},
    {'name': 'Скручивания', 'group': 'Пресс'},
    {'name': 'Бег', 'group': 'Кардио'},
  ];

  final List<String> _filterOptions = ['Все', 'Грудь', 'Спина', 'Ноги', 'Руки', 'Плечи', 'Пресс', 'Кардио', 'Общее'];

  void _showEditDialog({String? docId, String? currentName, String? currentGroup}) {
    final nameController = TextEditingController(text: currentName ?? "");
    String selectedGroup = currentGroup ?? _filterOptions[1]; // По дефолту Грудь
    bool isEditing = docId != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(isEditing ? 'Редактировать' : 'Новое упражнение', style: const TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: 'Название', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _filterOptions.contains(selectedGroup) ? selectedGroup : 'Общее',
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                    items: _filterOptions.where((e) => e != 'Все').map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setStateDialog(() => selectedGroup = val!),
                    decoration: const InputDecoration(labelText: 'Группа мышц', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
              actions: [
                if (isEditing) TextButton(onPressed: () async { await DatabaseService().deleteExercise(docId!); Navigator.pop(context); }, child: const Text("УДАЛИТЬ", style: TextStyle(color: Colors.red))),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.grey))),
                TextButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    if (isEditing) await DatabaseService().updateExercise(docId!, nameController.text.trim(), selectedGroup);
                    else await DatabaseService().addCustomExercise(nameController.text.trim(), selectedGroup);
                    Navigator.pop(context);
                  },
                  child: const Text("СОХРАНИТЬ", style: TextStyle(color: Color(0xFFCCFF00))),
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
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Библиотека', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFFCCFF00)),
            onPressed: () => Navigator.pop(context, _selected),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFCCFF00),
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => _showEditDialog(),
      ),
      body: Column(
        children: [
          // 2. ФИЛЬТРЫ (ЧИПЫ)
          SizedBox(
            height: 60,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _filterOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filterOptions[index];
                final isSelected = _selectedFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  selectedColor: const Color(0xFFCCFF00),
                  backgroundColor: const Color(0xFF1C1C1E),
                  labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
                  onSelected: (bool selected) {
                    setState(() {
                      _selectedFilter = filter;
                    });
                  },
                );
              },
            ),
          ),

          // СПИСОК
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService().getCustomExercises(),
              builder: (context, snapshot) {
                List<Exercise> allExercises = [];

                // А) Стандартные
                for (var item in _defaultExercises) {
                  allExercises.add(Exercise(
                    id: "default_${item['name']}", 
                    title: item['name']!, 
                    muscleGroup: item['group']!
                  ));
                }

                // Б) Пользовательские
                if (snapshot.hasData) {
                  final docs = snapshot.data!.docs;
                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    allExercises.add(Exercise(
                      id: doc.id,
                      title: data['title'] ?? 'Без названия',
                      muscleGroup: data['muscleGroup'] ?? 'Общее',
                    ));
                  }
                }

                // В) Фильтрация
                if (_selectedFilter != 'Все') {
                  allExercises = allExercises.where((e) => e.muscleGroup == _selectedFilter).toList();
                }

                // Г) Сортировка
                allExercises.sort((a, b) => a.title.compareTo(b.title));

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: allExercises.length,
                  itemBuilder: (context, index) {
                    final exercise = allExercises[index];
                    final isSelected = _selected.any((e) => e.title == exercise.title);
                    final isCustom = !exercise.id.startsWith("default_");

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onLongPress: isCustom 
                          ? () => _showEditDialog(docId: exercise.id, currentName: exercise.title, currentGroup: exercise.muscleGroup) 
                          : null,
                        onTap: () {
                          setState(() {
                            if (isSelected) _selected.removeWhere((e) => e.title == exercise.title);
                            else _selected.add(exercise);
                          });
                        },
                        child: PremiumGlassCard(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(exercise.title, style: TextStyle(color: isSelected ? const Color(0xFFCCFF00) : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(exercise.muscleGroup, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                                ],
                              ),
                              if (isSelected) const Icon(Icons.check_circle, color: Color(0xFFCCFF00)),
                            ],
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