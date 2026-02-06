import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../ui_widgets.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';

class AIWorkoutScreen extends StatefulWidget {
  const AIWorkoutScreen({super.key});

  @override
  State<AIWorkoutScreen> createState() => _AIWorkoutScreenState();
}

class _AIWorkoutScreenState extends State<AIWorkoutScreen> {
  String _goal = 'Набор массы';
  String _level = 'Новичок';
  String _equipment = 'Gym'; // <-- НОВОЕ: Место тренировки
  double _daysPerWeek = 3;
  
  bool _isLoading = false;
  Map<String, dynamic>? _aiResult;

  final List<String> _goals = ['Набор массы', 'Похудение', 'Сила', 'Рельеф'];
  final List<String> _levels = ['Новичок', 'Средний', 'Опытный'];
  // Варианты для UI
  final Map<String, String> _equipmentOptions = {
    'Gym': 'В зале (Gym)',
    'Home': 'Дома (Home)'
  };

  Future<void> _generate() async {
    setState(() {
      _isLoading = true;
      _aiResult = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("Нет пользователя");

      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = doc.data() ?? {};

      final result = await AIService().generateWorkoutPlan(
        goal: _goal,
        level: _level,
        gender: userData['gender'] ?? 'male',
        weight: (userData['weight'] ?? 0).toDouble(),
        height: (userData['height'] ?? 0).toDouble(),
        bodyFat: (userData['bodyFat'] ?? 0).toDouble(),
        experience: userData['experience'] ?? "Нет стажа",
        daysPerWeek: _daysPerWeek.toInt(),
        equipment: _equipment, // <-- Передаем место тренировки
      );
      
      setState(() {
        _aiResult = result;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAllWorkouts() async {
    if (_aiResult == null) return;
    setState(() => _isLoading = true);
    try {
      final schedule = _aiResult!['schedule'] as List<dynamic>;
      for (var day in schedule) {
        String dayName = day['dayName'];
        List<dynamic> exercises = day['exercises'];
        List<String> exerciseNames = [];
        Map<String, String> targets = {};

        for (var ex in exercises) {
          String name = ex['name'];
          String sets = ex['sets'].toString();
          String reps = ex['reps'].toString();
          exerciseNames.add(name);
          targets[name] = "${sets}x$reps";
        }
        await DatabaseService().saveUserWorkout("AI: $dayName", exerciseNames, targets);
      }

      if (_aiResult!['nutrition'] != null) {
        await DatabaseService().saveNutritionPlan(_aiResult!['nutrition']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Программа и питание сохранены!"), backgroundColor: Color(0xFFCCFF00)));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка сохранения: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("AI Тренер Pro"),
        backgroundColor: Colors.transparent,
        leading: const BackButton(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ПАНЕЛЬ НАСТРОЕК
            PremiumGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDropdown("Цель", _goal, _goals, (v) => setState(() => _goal = v!)),
                  const SizedBox(height: 16),
                  _buildDropdown("Уровень", _level, _levels, (v) => setState(() => _level = v!)),
                  const SizedBox(height: 16),
                  
                  // ВЫБОР ОБОРУДОВАНИЯ (НОВОЕ)
                  const Text("Место тренировок:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _equipment,
                    items: _equipmentOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setState(() => _equipment = v!),
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true, fillColor: Colors.black.withOpacity(0.3),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Text("Дней в неделю:", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _daysPerWeek,
                          min: 1, max: 7, divisions: 6,
                          activeColor: const Color(0xFFCCFF00),
                          inactiveColor: Colors.grey[800],
                          label: _daysPerWeek.toInt().toString(),
                          onChanged: (v) => setState(() => _daysPerWeek = v),
                        ),
                      ),
                      Text("${_daysPerWeek.toInt()}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  )
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            if (_isLoading)
              const Center(child: Column(children: [CircularProgressIndicator(color: Color(0xFFCCFF00)), SizedBox(height: 16), Text("Анализирую биометрию...", style: TextStyle(color: Colors.grey))]))
            else if (_aiResult == null)
              NeonActionButton(text: "СОСТАВИТЬ ПРОГРАММУ", onTap: _generate, isFullWidth: true),

            const SizedBox(height: 32),

            // РЕЗУЛЬТАТЫ
            if (_aiResult != null && !_isLoading) ...[
              _buildNutritionCard(_aiResult!['nutrition']),
              const SizedBox(height: 24),
              const Text("ВАША ПРОГРАММА:", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: (_aiResult!['schedule'] as List).length,
                itemBuilder: (context, index) {
                  final day = _aiResult!['schedule'][index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        title: Text(day['dayName'], style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                        childrenPadding: const EdgeInsets.all(16),
                        children: (day['exercises'] as List).map<Widget>((ex) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.fitness_center, color: Colors.grey, size: 16),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(ex['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      Text("${ex['sets']} x ${ex['reps']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      if (ex['comment'] != null) Text(ex['comment'], style: TextStyle(color: Colors.grey[600], fontSize: 11, fontStyle: FontStyle.italic)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              NeonActionButton(text: "СОХРАНИТЬ ПРОГРАММУ И ПИТАНИЕ", onTap: _saveAllWorkouts, isFullWidth: true),
              const SizedBox(height: 40),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionCard(Map<String, dynamic> nutrition) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [const Color(0xFFCCFF00).withOpacity(0.2), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ОБНОВЛЕННЫЙ ЗАГОЛОВОК
              const Text("ПИТАНИЕ И АКТИВНОСТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const Icon(Icons.local_fire_department, color: Color(0xFFCCFF00)),
            ],
          ),
          const SizedBox(height: 16),
          
          Center(
            child: Wrap(
              spacing: 20, runSpacing: 20, alignment: WrapAlignment.center,
              children: [
                _buildMacro("КАЛОРИИ", nutrition['calories'].toString()),
                _buildMacro("БЕЛОК", nutrition['protein'].toString()),
                _buildMacro("ЖИРЫ", nutrition['fats'].toString()),
                _buildMacro("УГЛЕВОДЫ", nutrition['carbs'].toString()),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          // НОВЫЙ БЛОК СОВЕТА С ИКОНКОЙ
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.directions_walk, color: Color(0xFFCCFF00), size: 20), // Иконка шагов
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nutrition['advice'], style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMacro(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 10)),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: onChanged,
          dropdownColor: const Color(0xFF2C2C2E),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: Colors.black.withOpacity(0.3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }
}