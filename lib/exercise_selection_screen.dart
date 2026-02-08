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

  // 1. РАСШИРЕННАЯ БАЗА УПРАЖНЕНИЙ
  final List<Map<String, String>> _defaultExercises = [
    // ГРУДЬ
    {'name': 'Жим штанги лежа', 'group': 'Грудь'},
    {'name': 'Жим гантелей наклонный', 'group': 'Грудь'},
    {'name': 'Жим штанги наклонный', 'group': 'Грудь'},
    {'name': 'Разводка гантелей', 'group': 'Грудь'},
    {'name': 'Сведение в кроссовере', 'group': 'Грудь'},
    {'name': 'Отжимания на брусьях', 'group': 'Грудь'},
    {'name': 'Жим в хамере', 'group': 'Грудь'},
    {'name': 'Отжимания от пола', 'group': 'Грудь'},
    {'name': 'Пек-дек (Бабочка)', 'group': 'Грудь'},
    {'name': 'Пуловер', 'group': 'Грудь'},
    {'name': 'Жим Смита', 'group': 'Грудь'},

    // СПИНА
    {'name': 'Подтягивания', 'group': 'Спина'},
    {'name': 'Тяга верхнего блока', 'group': 'Спина'},
    {'name': 'Тяга штанги в наклоне', 'group': 'Спина'},
    {'name': 'Тяга гантели одной рукой', 'group': 'Спина'},
    {'name': 'Тяга нижнего блока', 'group': 'Спина'},
    {'name': 'Гиперэкстензия', 'group': 'Спина'},
    {'name': 'Становая тяга', 'group': 'Спина'},
    {'name': 'Тяга Т-грифа', 'group': 'Спина'},
    {'name': 'Пуловер в блоке', 'group': 'Спина'},
    {'name': 'Шраги со штангой', 'group': 'Спина'},
    {'name': 'Шраги с гантелями', 'group': 'Спина'},

    // НОГИ
    {'name': 'Приседания со штангой', 'group': 'Ноги'},
    {'name': 'Жим ногами', 'group': 'Ноги'},
    {'name': 'Разгибание ног', 'group': 'Ноги'},
    {'name': 'Сгибание ног лежа', 'group': 'Ноги'},
    {'name': 'Выпады с гантелями', 'group': 'Ноги'},
    {'name': 'Румынская тяга', 'group': 'Ноги'},
    {'name': 'Подъем на носки стоя', 'group': 'Ноги'},
    {'name': 'Гакк-приседания', 'group': 'Ноги'},
    {'name': 'Болгарские выпады', 'group': 'Ноги'},
    {'name': 'Ягодичный мост', 'group': 'Ноги'},

    // ПЛЕЧИ
    {'name': 'Армейский жим', 'group': 'Плечи'},
    {'name': 'Жим гантелей сидя', 'group': 'Плечи'},
    {'name': 'Махи гантелями в стороны', 'group': 'Плечи'},
    {'name': 'Махи в наклоне', 'group': 'Плечи'},
    {'name': 'Тяга штанги к подбородку', 'group': 'Плечи'},
    {'name': 'Подъем рук перед собой', 'group': 'Плечи'},
    {'name': 'Обратная бабочка', 'group': 'Плечи'},
    {'name': 'Жим Арнольда', 'group': 'Плечи'},
    {'name': 'Жим в тренажере', 'group': 'Плечи'},
    {'name': 'Отведение руки на блоке', 'group': 'Плечи'},

    // РУКИ
    {'name': 'Подъем штанги на бицепс', 'group': 'Руки'},
    {'name': 'Молотки', 'group': 'Руки'},
    {'name': 'Концентрированный подъем', 'group': 'Руки'},
    {'name': 'Французский жим', 'group': 'Руки'},
    {'name': 'Разгибание на блоке (канаты)', 'group': 'Руки'},
    {'name': 'Отжимания узким хватом', 'group': 'Руки'},
    {'name': 'Сгибание на скамье Скотта', 'group': 'Руки'},
    {'name': 'Разгибание гантели из-за головы', 'group': 'Руки'},
    {'name': 'Разгибание одной рукой на блоке', 'group': 'Руки'},
    {'name': 'Бицепс на нижнем блоке', 'group': 'Руки'},

    // ПРЕСС
    {'name': 'Скручивания', 'group': 'Пресс'},
    {'name': 'Подъем ног в висе', 'group': 'Пресс'},
    {'name': 'Планка', 'group': 'Пресс'},
    {'name': 'Русские скручивания', 'group': 'Пресс'},
    {'name': 'Ролик для пресса', 'group': 'Пресс'},
    {'name': 'Вакуум', 'group': 'Пресс'},
    {'name': 'Велосипед', 'group': 'Пресс'},
    {'name': 'Молитва (на блоке)', 'group': 'Пресс'},

    // КАРДИО
    {'name': 'Бег', 'group': 'Кардио'},
    {'name': 'Эллипс', 'group': 'Кардио'},
    {'name': 'Велотренажер', 'group': 'Кардио'},
    {'name': 'Скакалка', 'group': 'Кардио'},
    {'name': 'Гребля', 'group': 'Кардио'},
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
                    initialValue: _filterOptions.contains(selectedGroup) ? selectedGroup : 'Общее',
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                    items: _filterOptions.where((e) => e != 'Все').map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                    onChanged: (val) => setStateDialog(() => selectedGroup = val!),
                    decoration: const InputDecoration(labelText: 'Группа мышц', labelStyle: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
              actions: [
                if (isEditing) TextButton(onPressed: () async { await DatabaseService().deleteExercise(docId); Navigator.pop(context); }, child: const Text("УДАЛИТЬ", style: TextStyle(color: Colors.red))),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ОТМЕНА", style: TextStyle(color: Colors.grey))),
                TextButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    if (isEditing) {
                      await DatabaseService().updateExercise(docId, nameController.text.trim(), selectedGroup);
                    } else {
                      await DatabaseService().addCustomExercise(nameController.text.trim(), selectedGroup);
                    }
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
          // ФИЛЬТРЫ (ЧИПЫ)
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

                // А) Стандартные (из большого списка)
                for (var item in _defaultExercises) {
                  allExercises.add(Exercise(
                    id: "default_${item['name']}", 
                    title: item['name']!, 
                    muscleGroup: item['group']!
                  ));
                }

                // Б) Пользовательские (из Firebase)
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

                // Г) Сортировка по алфавиту
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
                            if (isSelected) {
                              _selected.removeWhere((e) => e.title == exercise.title);
                            } else {
                              _selected.add(exercise);
                            }
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