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
  String _equipment = 'Gym'; 
  double _daysPerWeek = 3;
  bool _isLoading = false;
  Map<String, dynamic>? _aiResult;

  final List<String> _goals = ['Набор массы', 'Похудение', 'Сила', 'Рельеф'];
  final List<String> _levels = ['Новичок', 'Средний', 'Опытный'];
  final Map<String, String> _equipmentOptions = {'Gym': 'В зале', 'Home': 'Дома'};

  Future<void> _generate() async {
    setState(() { _isLoading = true; _aiResult = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("Нет пользователя");
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = doc.data() ?? {};

      // ИСПРАВЛЕННЫЙ ВЫЗОВ МЕТОДА
      final result = await AIService().generateWorkout(
        goal: _goal,
        level: _level,
        gender: userData['gender'] ?? 'male',
        weight: (userData['weight'] ?? 0).toDouble(),
        height: (userData['height'] ?? 0).toDouble(),
        bodyFat: (userData['bodyFat'] ?? 0).toDouble(),
        experience: userData['experience'] ?? "Нет стажа",
        daysPerWeek: _daysPerWeek.toInt(),
        equipment: _equipment, 
      );
      
      if (mounted) setState(() => _aiResult = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          exerciseNames.add(name);
          targets[name] = "${ex['sets']}x${ex['reps']}";
        }
        await DatabaseService().saveUserWorkout("AI: $dayName", exerciseNames, targets);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Программа сохранена!"), backgroundColor: Color(0xFFCCFF00)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка сохранения: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(title: const Text("AI Тренер"), backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            PremiumGlassCard(
              child: Column(
                children: [
                  DropdownButtonFormField(
                    value: _goal, 
                    items: _goals.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), 
                    onChanged: (v) => setState(() => _goal = v!),
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField(
                    value: _level, 
                    items: _levels.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), 
                    onChanged: (v) => setState(() => _level = v!),
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField(
                    value: _equipment, 
                    items: _equipmentOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), 
                    onChanged: (v) => setState(() => _equipment = v!),
                    dropdownColor: const Color(0xFF2C2C2E),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Slider(value: _daysPerWeek, min: 1, max: 7, divisions: 6, onChanged: (v) => setState(() => _daysPerWeek = v), activeColor: const Color(0xFFCCFF00)),
                  Text("Дней в неделю: ${_daysPerWeek.toInt()}", style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_isLoading) const CircularProgressIndicator(color: Color(0xFFCCFF00))
            else if (_aiResult == null) NeonActionButton(text: "СОСТАВИТЬ ПРОГРАММУ", onTap: _generate, isFullWidth: true),
            
            if (_aiResult != null && !_isLoading) ...[
              const SizedBox(height: 20),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: (_aiResult!['schedule'] as List).length,
                itemBuilder: (context, index) {
                  final day = _aiResult!['schedule'][index];
                  return Card(
                    color: const Color(0xFF1C1C1E),
                    child: ExpansionTile(
                      title: Text(day['dayName'], style: const TextStyle(color: Color(0xFFCCFF00))),
                      collapsedIconColor: Colors.white,
                      iconColor: const Color(0xFFCCFF00),
                      children: (day['exercises'] as List).map<Widget>((ex) => ListTile(title: Text(ex['name'], style: const TextStyle(color: Colors.white)), subtitle: Text("${ex['sets']}x${ex['reps']}", style: const TextStyle(color: Colors.grey)))).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              NeonActionButton(text: "СОХРАНИТЬ", onTap: _saveAllWorkouts, isFullWidth: true),
            ]
          ],
        ),
      ),
    );
  }
}