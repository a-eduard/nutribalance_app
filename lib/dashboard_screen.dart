import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_widgets.dart'; 
import 'services/database_service.dart';
import 'workout_session_screen.dart'; 
import 'create_workout_screen.dart'; 
import 'screens/ai_workout_screen.dart';
import 'screens/ai_chat_screen.dart'; 
import 'screens/profile_screen.dart'; 
import 'screens/history_screen.dart'; // <--- ИСПРАВЛЕННЫЙ ПУТЬ

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeTab(),
    const HistoryScreen(), // Теперь этот класс будет найден
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1C1C1E),
        selectedItemColor: const Color(0xFFCCFF00),
        unselectedItemColor: Colors.grey,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Главная"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "История"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Профиль"),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("С возвращением,", style: TextStyle(color: Colors.grey)),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final data = snapshot.data!.data() as Map<String, dynamic>?;
                          final name = data?['name'] ?? 'Атлет';
                          return Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic));
                        }
                        return const Text("...", style: TextStyle(color: Colors.white, fontSize: 24));
                      },
                    ),
                  ],
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.notifications, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _AICard(
                    title: "AI ТРЕНЕР",
                    icon: Icons.fitness_center,
                    color: const Color(0xFFCCFF00),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIWorkoutScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AICard(
                    title: "AI ДИЕТОЛОГ",
                    icon: Icons.restaurant,
                    color: Colors.cyanAccent,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("МОИ ПРОГРАММЫ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFFCCFF00)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateWorkoutScreen())),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: DatabaseService().getUserWorkouts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("Нет программ. Создай первую!", style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] ?? "Без названия";
                    final exercises = (data['exercises'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text("${exercises.length} упражнений", style: const TextStyle(color: Colors.grey)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.play_arrow, color: Color(0xFFCCFF00)),
                              onPressed: () {
                                // --- ИСПРАВЛЕННЫЙ ВЫЗОВ ---
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(
                                    builder: (_) => WorkoutSessionScreen(
                                      workoutTitle: name, 
                                      initialExercises: exercises,
                                    )
                                  )
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                await DatabaseService().deleteWorkout(doc.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AICard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AICard({required this.title, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}