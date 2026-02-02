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
  // Список выбранных упражнений, который мы вернем назад
  final List<Exercise> _selected = [];
  
  // Для диалога добавления/редактирования
  final List<String> _muscleGroups = ['Грудь', 'Спина', 'Ноги', 'Плечи', 'Руки', 'Пресс', 'Кардио', 'Общее'];

  // --- ДИАЛОГ РЕДАКТИРОВАНИЯ ---
  void _showEditDialog({String? docId, String? currentName, String? currentGroup}) {
    final nameController = TextEditingController(text: currentName ?? "");
    String selectedGroup = currentGroup ?? _muscleGroups.first;
    bool isEditing = docId != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( // Чтобы обновлять Dropdown внутри диалога
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                isEditing ? 'Редактировать' : 'Новое упражнение',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Поле ввода названия
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFCCFF00))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Выбор мышцы
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Группа мышц',
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    ),
                    items: _muscleGroups.map((group) {
                      return DropdownMenuItem(value: group, child: Text(group));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selectedGroup = val);
                    },
                  ),
                ],
              ),
              actions: [
                // Кнопка УДАЛИТЬ (только если редактируем)
                if (isEditing)
                  TextButton(
                    onPressed: () async {
                      await DatabaseService().deleteExercise(docId!);
                      Navigator.pop(context);
                    },
                    child: const Text("УДАЛИТЬ", style: TextStyle(color: Colors.red)),
                  ),
                
                // Кнопка ОТМЕНА (если создаем)
                if (!isEditing)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("ОТМЕНА", style: TextStyle(color: Colors.grey)),
                  ),

                // Кнопка СОХРАНИТЬ
                TextButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;

                    if (isEditing) {
                      await DatabaseService().updateExercise(docId!, nameController.text.trim(), selectedGroup);
                    } else {
                      await DatabaseService().addCustomExercise(nameController.text.trim(), selectedGroup);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("СОХРАНИТЬ", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
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
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFFCCFF00)),
            onPressed: () {
              // Возвращаем список выбранных упражнений назад
              Navigator.pop(context, _selected);
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFCCFF00),
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () => _showEditDialog(), // Открываем диалог для СОЗДАНИЯ
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: DatabaseService().getCustomExercises(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
          }

          // Данные из Firestore
          final docs = snapshot.data?.docs ?? [];
          
          if (docs.isEmpty) {
            return Center(
              child: Text(
                "Библиотека пуста.\nДобавь свое первое упражнение!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final exercise = Exercise(
                id: doc.id,
                title: data['title'] ?? 'Без названия',
                muscleGroup: data['muscleGroup'] ?? 'Общее',
              );

              final isSelected = _selected.any((e) => e.title == exercise.title);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // ДОЛГОЕ НАЖАТИЕ -> РЕДАКТИРОВАНИЕ
                  onLongPress: () {
                    _showEditDialog(
                      docId: doc.id,
                      currentName: exercise.title,
                      currentGroup: exercise.muscleGroup,
                    );
                  },
                  // ОБЫЧНОЕ НАЖАТИЕ -> ВЫБОР
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
                            Text(
                              exercise.title,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFCCFF00) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              exercise.muscleGroup,
                              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                            ),
                          ],
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: Color(0xFFCCFF00)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}