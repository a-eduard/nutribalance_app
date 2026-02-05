import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/database_service.dart';
import 'ui_widgets.dart';
import 'create_workout_screen.dart';
import 'workout_session_screen.dart';
import 'exercise_data.dart';
import 'widgets/activity_chart.dart';
import 'screens/profile_screen.dart';
import 'screens/ai_workout_screen.dart';
import 'screens/history_screen.dart'; // <--- ПОДКЛЮЧИЛИ ИСТОРИЮ
import 'screens/ai_chat_screen.dart'; // <--- ПОДКЛЮЧИЛИ ЧАТ

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const HomeTab(),
    const HistoryScreen(), // <--- ТЕПЕРЬ ТУТ ПОЛНОЦЕННЫЙ ЭКРАН ИСТОРИИ
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: _pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F0F0F),
          selectedItemColor: const Color(0xFFCCFF00),
          unselectedItemColor: Colors.grey,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Тренировки'),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: 'История'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _history = [];
  int _totalWorkouts = 0;
  int _totalTonnage = 0;
  bool _loadingStats = true;
  String? _avatarPath;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _avatarPath = prefs.getString('avatar_path'));
  }

  Future<void> _loadStats() async {
    final historyData = await DatabaseService().getUserHistory();
    int tonnage = 0;
    for (var session in historyData) {
      tonnage += (session['tonnage'] as int? ?? 0);
    }
    if (mounted) {
      setState(() {
        _history = historyData;
        _totalWorkouts = historyData.length;
        _totalTonnage = tonnage;
        _loadingStats = false;
      });
    }
  }

  Map<String, dynamic> _calculateLevelInfo(int totalTonnageKg, String gender) {
    final int levelThresholdKg = (gender == 'male' ? 100 : 50) * 1000;
    int currentLevel = (totalTonnageKg / levelThresholdKg).floor();
    if (currentLevel < 1) currentLevel = 0; 
    int remainder = totalTonnageKg % levelThresholdKg;
    int neededForNext = levelThresholdKg - remainder;
    double progressPercent = remainder / levelThresholdKg;
    return {"level": currentLevel, "progress": progressPercent, "neededTons": (neededForNext / 1000).toStringAsFixed(1)};
  }

  String _getGreetingPhrase(String name, String gender) {
    final random = DateTime.now().millisecondsSinceEpoch;
    final index = random % 5;
    if (gender == 'male') {
      const phrases = ["Привет, машина!", "Время побеждать, {name}!", "Покажи мощь!", "Твоя цель близка.", "Железо ждет."];
      return phrases[index].replaceAll("{name}", name);
    } else {
      const phrases = ["Сияй, {name}!", "Ты прекрасна!", "Время для себя.", "С каждым днем лучше.", "Спорт тебе к лицу!"];
      return phrases[index].replaceAll("{name}", name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        String name = "Чемпион";
        String gender = "male";
        if (userSnap.hasData && userSnap.data!.exists) {
          final data = userSnap.data!.data() as Map<String, dynamic>;
          name = data['name'] ?? "Чемпион";
          gender = data['gender'] ?? "male";
        }

        final greeting = _getGreetingPhrase(name, gender);
        final levelInfo = _calculateLevelInfo(_totalTonnage, gender);
        
        return Scaffold(
          backgroundColor: const Color(0xFF0F0F0F),
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFFCCFF00),
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateWorkoutScreen())),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ШАПКА
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: const Color(0xFF1C1C1E),
                              backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                              child: _avatarPath == null ? const Icon(Icons.person, color: Colors.grey) : null,
                            ),
                            Positioned(
                              bottom: -4, right: -4,
                              child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFCCFF00), shape: BoxShape.circle), child: Text("${levelInfo['level']}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12))),
                            )
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(greeting.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: 18)),
                              const SizedBox(height: 6),
                              Row(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: levelInfo['progress'], backgroundColor: Colors.white10, color: const Color(0xFFCCFF00), minHeight: 6))), const SizedBox(width: 8), Text("+${levelInfo['neededTons']} т", style: const TextStyle(color: Colors.grey, fontSize: 10))]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        
                        // КНОПКА ГЕНЕРАТОРА
                        _buildHeaderBtn(Icons.auto_awesome, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AIWorkoutScreen()))),
                        const SizedBox(width: 8),
                        // КНОПКА ЧАТА (НОВАЯ)
                        _buildHeaderBtn(Icons.chat_bubble_outline, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AIChatScreen()))),
                      ],
                    ),
                  ),

                  // ОСТАЛЬНОЙ КОНТЕНТ (График и Список)
                  const SizedBox(height: 24),
                  if (!_loadingStats) Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Row(children: [Expanded(flex: 3, child: Container(height: 140, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)), child: ActivityChart(history: _history))), const SizedBox(width: 12), Expanded(flex: 2, child: Column(children: [_StatCard(label: "ТРЕНИРОВОК", value: "$_totalWorkouts"), const SizedBox(height: 12), _StatCard(label: "ТОННАЖ", value: "${(_totalTonnage / 1000).toStringAsFixed(1)} т")]))])),
                  const SizedBox(height: 24),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 24.0), child: Text("ТВОИ ПРОГРАММЫ", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: DatabaseService().getUserWorkouts(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmptyState(context);
                      final docs = snapshot.data!.docs;
                      return ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: docs.length, itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final workout = Workout(name: data['name'] ?? "Без названия", exercises: (data['exercises'] as List<dynamic>).map((e) => Exercise(id: e, title: e, muscleGroup: "Unknown")).toList(), targets: Map<String, String>.from(data['targets'] ?? {}));
                          return Padding(padding: const EdgeInsets.only(bottom: 12), child: _WorkoutCard(workout: workout, docId: doc.id));
                        });
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderBtn(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.3))),
      child: IconButton(icon: Icon(icon, color: const Color(0xFFCCFF00), size: 20), onPressed: onTap, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40)),
    );
  }

  // ... (Остальные виджеты: _buildEmptyState, _StatCard, _WorkoutCard - такие же, как были)
  Widget _buildEmptyState(BuildContext context) { return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(children: [Icon(Icons.fitness_center, size: 48, color: Colors.white.withOpacity(0.1)), const SizedBox(height: 16), const Text("Пока нет программ", style: TextStyle(color: Colors.grey)), const SizedBox(height: 8), const Text("Нажми +, чтобы создать", style: TextStyle(color: Colors.grey, fontSize: 12))]))); }
}

class _StatCard extends StatelessWidget { final String label; final String value; const _StatCard({required this.label, required this.value}); @override Widget build(BuildContext context) { return Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Column(children: [Text(value, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 9))])); } }

class _WorkoutCard extends StatelessWidget { final Workout workout; final String docId; const _WorkoutCard({required this.workout, required this.docId}); void _confirmDelete(BuildContext context) { showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1C1C1E), title: const Text("Удалить?", style: TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Нет")), TextButton(onPressed: () async { Navigator.pop(ctx); await DatabaseService().deleteWorkout(docId); }, child: const Text("Да", style: TextStyle(color: Colors.red)))])); } @override Widget build(BuildContext context) { return GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => WorkoutSessionScreen(workout: workout))), child: PremiumGlassCard(child: Row(children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: const Color(0xFFCCFF00).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.bolt, color: Color(0xFFCCFF00))), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(workout.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text("${workout.exercises.length} упражнений", style: const TextStyle(color: Colors.grey, fontSize: 12))])), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFCCFF00), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFFCCFF00).withOpacity(0.4), blurRadius: 10, spreadRadius: 1)]), child: const Icon(Icons.play_arrow, color: Colors.black, size: 20)), const SizedBox(width: 8), Theme(data: Theme.of(context).copyWith(cardColor: const Color(0xFF1C1C1E), iconTheme: const IconThemeData(color: Colors.grey)), child: PopupMenuButton<String>(onSelected: (value) { if (value == 'edit') { Navigator.push(context, MaterialPageRoute(builder: (context) => CreateWorkoutScreen(existingWorkout: workout, docId: docId))); } else if (value == 'delete') { _confirmDelete(context); } }, itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[const PopupMenuItem<String>(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text("Редактировать", style: TextStyle(color: Colors.white))])), const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text("Удалить", style: TextStyle(color: Colors.red))]))], icon: const Icon(Icons.more_vert)))]))); } }