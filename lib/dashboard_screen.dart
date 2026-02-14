import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Виджеты и экраны в корне lib
import 'ui_widgets.dart'; 
import 'workout_session_screen.dart'; 
import 'create_workout_screen.dart'; 

// Сервисы
import 'services/database_service.dart';

// Экраны в папке screens
import 'screens/ai_workout_screen.dart';
import 'screens/ai_chat_screen.dart'; 
import 'screens/profile_screen.dart'; 
import 'screens/history_screen.dart';
import 'screens/coach_list_screen.dart'; 
import 'screens/p2p_chat_screen.dart';
import 'screens/assigned_workout_preview_screen.dart'; // <--- НОВЫЙ ИМПОРТ

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeTab(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF1C1C1E)))),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF000000),
          selectedItemColor: const Color(0xFFCCFF00),
          unselectedItemColor: Colors.grey,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: "Тренировки"),
            BottomNavigationBarItem(icon: Icon(Icons.history), label: "История"),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: "Профиль"),
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ================= ШАПКА =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "TONNA GYM", 
                      style: TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)
                    ),
                    StreamBuilder<DocumentSnapshot>(
                      stream: DatabaseService().getUserData(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final data = snapshot.data!.data() as Map<String, dynamic>?;
                          final name = data?['name']?.toString().trim() ?? '';
                          if (name.isNotEmpty) {
                            return Text("ПРИВЕТ, ${name.toUpperCase()}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic));
                          }
                        }
                        return const Text("ПРИВЕТ, АТЛЕТ", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic));
                      },
                    ),
                  ],
                ),
                CircleAvatar(
                  backgroundColor: const Color(0xFF1C1C1E),
                  child: IconButton(onPressed: () {}, icon: const Icon(Icons.notifications, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ================= КАРТОЧКА НАЗНАЧЕННОГО ТРЕНЕРА =================
            StreamBuilder<DocumentSnapshot>(
              stream: DatabaseService().getUserData(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  final currentCoachId = data?['currentCoachId'] as String?;
                  
                  if (currentCoachId != null && currentCoachId.isNotEmpty) {
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: currentCoachId, otherUserName: "Мой тренер"))),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: const Color(0xFFCCFF00).withOpacity(0.1), shape: BoxShape.circle),
                                  child: const Icon(Icons.person, color: Color(0xFFCCFF00)),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(child: Text("Ваш тренер назначен", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                                const Icon(Icons.chat_bubble_outline, color: Color(0xFFCCFF00)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            ),

            // ================= ПРОГРАММЫ ОТ ТРЕНЕРА =================
            if (uid != null)
              StreamBuilder<QuerySnapshot>(
                // УБРАЛИ .where('isCompleted', isEqualTo: false)
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('assigned_workouts')
                    .orderBy('date', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    // Выводим все программы списком (Column)
                    return Column(
                      children: snapshot.data!.docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context, 
                                MaterialPageRoute(builder: (_) => AssignedWorkoutPreviewScreen(workoutId: doc.id, workoutData: data))
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFCCFF00), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFCCFF00).withOpacity(0.15),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  )
                                ]
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.local_fire_department, color: Color(0xFFCCFF00), size: 16),
                                            SizedBox(width: 6),
                                            Text("ПРОГРАММА ОТ ТРЕНЕРА", style: TextStyle(color: Color(0xFFCCFF00), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          data['name']?.toString() ?? 'Тренировка', 
                                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, color: Color(0xFFCCFF00), size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

            // ================= КАРТОЧКИ ИИ =================
            Row(
              children: [
                Expanded(
                  child: _AICard(
                    title: "AI ТРЕНЕР",
                    subtitle: "Создать план",
                    icon: Icons.bolt,
                    color: const Color(0xFFCCFF00),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIWorkoutScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AICard(
                    title: "AI ДИЕТОЛОГ",
                    subtitle: "План питания",
                    icon: Icons.restaurant,
                    color: Colors.white,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen())),
                  ),
                ),
              ],
            ),
            
            // ================= КНОПКА МАРКЕТПЛЕЙСА =================
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoachListScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.3), width: 1.5),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFCCFF00).withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.people, color: Color(0xFFCCFF00), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("МАРКЕТПЛЕЙС", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                        Text("Найти тренера", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
            
            // ================= МОИ ПРОГРАММЫ =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("МОИ ПРОГРАММЫ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateWorkoutScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFCCFF00), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add, color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ================= СПИСОК ПРОГРАММ =================
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: DatabaseService().getUserWorkouts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fitness_center, size: 48, color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          const Text("Нет программ", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final doc = snapshot.data!.docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name'] ?? "Без названия";
                      final exercises = (data['exercises'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
                      final targets = Map<String, dynamic>.from(data['targets'] ?? {});

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart, 
                        background: Container(
                          alignment: Alignment.centerRight,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1C1C1E),
                              title: const Text("Удалить программу?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              content: const Text("Это действие нельзя отменить.", style: TextStyle(color: Colors.grey)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Отмена", style: TextStyle(color: Colors.white))),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Удалить", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) async => await DatabaseService().deleteWorkout(doc.id),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutSessionScreen(workoutTitle: name, initialExercises: exercises, workoutId: doc.id)));
                          },
                          onLongPress: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CreateWorkoutScreen(existingDocId: doc.id, existingData: data)));
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text("${exercises.length} упражнений", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                iconColor: const Color(0xFFCCFF00),
                                collapsedIconColor: const Color(0xFFCCFF00),
                                children: exercises.map<Widget>((exName) {
                                  String comment = "";
                                  if (targets.containsKey(exName)) {
                                    final parts = targets[exName].toString().split('|');
                                    if (parts.length > 1) comment = parts[1];
                                  }
                                  return ListTile(
                                    dense: true,
                                    title: Text(exName, style: const TextStyle(color: Colors.white)),
                                    subtitle: comment.isNotEmpty ? Text(comment, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12)) : null,
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
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
      ),
    );
  }
}

class _AICard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _AICard({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                Text(subtitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            )
          ],
        ),
      ),
    );
  }
}