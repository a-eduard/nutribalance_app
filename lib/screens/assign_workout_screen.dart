import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExerciseInput {
  final TextEditingController name = TextEditingController();
  final TextEditingController sets = TextEditingController();
  final TextEditingController reps = TextEditingController();

  void dispose() {
    name.dispose();
    sets.dispose();
    reps.dispose();
  }
}

class AssignWorkoutScreen extends StatefulWidget {
  final String clientId;
  final String clientName;
  // ДОБАВЛЕНЫ ПАРАМЕТРЫ ДЛЯ РЕДАКТИРОВАНИЯ
  final String? existingWorkoutId;
  final Map<String, dynamic>? existingWorkoutData;

  const AssignWorkoutScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    this.existingWorkoutId,
    this.existingWorkoutData,
  });

  @override
  State<AssignWorkoutScreen> createState() => _AssignWorkoutScreenState();
}

class _AssignWorkoutScreenState extends State<AssignWorkoutScreen> {
  final TextEditingController _nameController = TextEditingController();
  final List<ExerciseInput> _exercises = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // ЕСЛИ РЕЖИМ РЕДАКТИРОВАНИЯ - ЗАПОЛНЯЕМ ДАННЫЕ
    if (widget.existingWorkoutData != null) {
      _nameController.text = widget.existingWorkoutData!['name'] ?? '';
      final exList = widget.existingWorkoutData!['exercises'] as List<dynamic>? ?? [];
      
      if (exList.isNotEmpty) {
        for (var ex in exList) {
          final ei = ExerciseInput();
          ei.name.text = ex['name']?.toString() ?? '';
          ei.sets.text = ex['targetSets']?.toString() ?? '';
          ei.reps.text = ex['targetReps']?.toString() ?? '';
          _exercises.add(ei);
        }
      } else {
        _exercises.add(ExerciseInput());
      }
    } else {
      // НОВАЯ ПРОГРАММА
      _exercises.add(ExerciseInput());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (var ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  Future<void> _sendWorkout() async {
    setState(() => _isLoading = true);

    try {
      final exercisesData = _exercises.map((e) => {
        'name': e.name.text.trim(),
        'targetSets': e.sets.text.trim(),
        'targetReps': e.reps.text.trim(),
      }).toList();

      final docData = {
        'name': _nameController.text.trim().isEmpty ? 'Тренировка от тренера' : _nameController.text.trim(),
        'exercises': exercisesData,
        'isCompleted': false,
      };

      if (widget.existingWorkoutId != null) {
        // РЕДАКТИРОВАНИЕ
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.clientId)
            .collection('assigned_workouts')
            .doc(widget.existingWorkoutId)
            .update(docData);
      } else {
        // НОВАЯ
        docData['date'] = FieldValue.serverTimestamp(); // Дату ставим только при создании
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.clientId)
            .collection('assigned_workouts')
            .add(docData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Программа успешно сохранена!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFFCCFF00),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.existingWorkoutId != null ? "РЕДАКТИРОВАНИЕ" : "ПРОГРАММА ДЛЯ ${widget.clientName.toUpperCase()}", 
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.0)
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                const Text("НАЗВАНИЕ ПРОГРАММЫ", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                _buildTextField(_nameController, "Например: День ног", Icons.fitness_center),
                
                const SizedBox(height: 32),
                const Text("УПРАЖНЕНИЯ", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 12),
                
                ...List.generate(_exercises.length, (index) {
                  return _buildExerciseCard(_exercises[index], index);
                }),

                const SizedBox(height: 16),
                
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _exercises.add(ExerciseInput())),
                    icon: const Icon(Icons.add, color: Color(0xFFCCFF00)),
                    label: const Text("ДОБАВИТЬ УПРАЖНЕНИЕ", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              border: Border(top: BorderSide(color: Colors.black, width: 2)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sendWorkout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : Text(
                        widget.existingWorkoutId != null ? "СОХРАНИТЬ ПРОГРАММУ" : "ОТПРАВИТЬ КЛИЕНТУ", 
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseCard(ExerciseInput exercise, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("УПРАЖНЕНИЕ ${index + 1}", style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold)),
              if (_exercises.length > 1) 
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _exercises[index].dispose();
                      _exercises.removeAt(index);
                    });
                  },
                  child: const Icon(Icons.close, color: Colors.grey, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTextField(exercise.name, "Название упражнения", null),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildTextField(exercise.sets, "Подходы", null, isNumber: true)),
              const SizedBox(width: 12),
              Expanded(child: _buildTextField(exercise.reps, "Повторения", null, isNumber: true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData? icon, {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black, 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: const Color(0xFFCCFF00),
        decoration: InputDecoration(
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: icon != null ? 14 : 16),
          isDense: true,
        ),
      ),
    );
  }
}