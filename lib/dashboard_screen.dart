import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'exercise_data.dart'; 
import 'workout_session_screen.dart'; 
import 'create_workout_screen.dart'; 
import 'profile_screen.dart'; // <--- Подключили Профиль
import 'ui_widgets.dart'; 
import 'services/database_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // СПИСОК ЭКРАНОВ ДЛЯ НИЖНЕЙ НАВИГАЦИИ
    final List<Widget> widgetOptions = <Widget>[
      const HomeTab(),          // 0: Главная
      const WorkoutsListTab(),  // 1: Список тренировок
      const ProfileScreen(),    // 2: Профиль (Новый экран)
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      // extendBodyBehindAppBar: true, // Можно убрать, если мешает на профиле
      body: widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F0F0F),
          elevation: 0,
          selectedItemColor: const Color(0xFFCCFF00),
          unselectedItemColor: const Color(0xFF8E8E93),
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.fitness_center), label: 'Тренировки'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
          ],
        ),
      ),
    );
  }
}

// --- ВКЛАДКА 1: ГЛАВНАЯ ---
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: DatabaseService().getUserWorkouts(),
      builder: (context, snapshot) {
        // 1. ЗАГРУЗКА
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
        }

        // 2. ОШИБКА
        if (snapshot.hasError) {
          return Center(child: Text("Ошибка: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
        }

        final docs = snapshot.data?.docs ?? [];
        bool hasWorkouts = docs.isNotEmpty;

        return Stack(
          children: [
            // Фоновый градиент сверху
            Positioned(
              top: 0, left: 0, right: 0, height: 400,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [const Color(0xFFCCFF00).withOpacity(0.08), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: hasWorkouts 
                  ? _ActiveStateView(latestWorkoutDoc: docs.first, totalWorkouts: docs.length) 
                  : const _EmptyStateView(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// СОСТОЯНИЕ: НЕТ ТРЕНИРОВОК
class _EmptyStateView extends StatelessWidget {
  const _EmptyStateView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          PremiumGlassCard(
            child: Column(
              children: [
                const Icon(Icons.add_task, size: 64, color: Color(0xFF8E8E93)),
                const SizedBox(height: 24),
                Text('НАЧНИ СВОЙ ПУТЬ', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text('Создай свою первую программу тренировок.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          NeonActionButton(
            text: 'СОЗДАТЬ ПРОГРАММУ',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CreateWorkoutScreen()));
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// СОСТОЯНИЕ: ЕСТЬ ТРЕНИРОВКИ
class _ActiveStateView extends StatelessWidget {
  final QueryDocumentSnapshot latestWorkoutDoc;
  final int totalWorkouts;

  const _ActiveStateView({required this.latestWorkoutDoc, required this.totalWorkouts});

  // Преобразование документа Firestore в объект Workout
  Workout _convertDocToWorkout(QueryDocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    List<dynamic> exerciseNames = data['exercises'] ?? [];
    
    List<Exercise> exercises = exerciseNames.map((name) {
      return Exercise(id: DateTime.now().toString(), title: name.toString(), muscleGroup: "Общее");
    }).toList();

    return Workout(
      name: data['name'] ?? "Без названия",
      exercises: exercises,
    );
  }

  @override
  Widget build(BuildContext context) {
    final workoutObj = _convertDocToWorkout(latestWorkoutDoc);
    final data = latestWorkoutDoc.data() as Map<String, dynamic>;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // ПРИВЕТСТВИЕ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ПРИВЕТ, ЧЕМПИОН', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    const Text('Твоя программа готова!', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFCCFF00), width: 2)),
                  child: const CircleAvatar(radius: 22, backgroundColor: Color(0xFF2C2C2E), child: Icon(Icons.person, color: Colors.white)),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // ЗАГОЛОВОК СТАТИСТИКИ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: const [
              Icon(Icons.bar_chart, color: Color(0xFFCCFF00), size: 20),
              SizedBox(width: 8),
              Text('СТАТИСТИКА', style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ]),
          ),
          const SizedBox(height: 8),
          
          // ПЛАШКА СТАТИСТИКИ
          PremiumGlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(value: "$totalWorkouts", label: "Программ"),
                Container(width: 1, height: 40, color: Colors.white12),
                _StatItem(value: "0", label: "Выполнено", isHighlighted: true),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ЗАГОЛОВОК ПОСЛЕДНЕЙ ТРЕНИРОВКИ
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(children: const [
              Icon(Icons.bolt, color: Color(0xFFCCFF00), size: 20),
              SizedBox(width: 8),
              Text('ПОСЛЕДНЯЯ ДОБАВЛЕННАЯ', style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ]),
          ),
          const SizedBox(height: 8),
          
          // КАРТОЧКА ПОСЛЕДНЕЙ ТРЕНИРОВКИ С МЕНЮ
          PremiumGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(workoutObj.name.toUpperCase(), 
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24), overflow: TextOverflow.ellipsis),
                    ),
                    // --- МЕНЮ УПРАВЛЕНИЯ (EDIT/DELETE) ---
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF1C1C1E),
                      onSelected: (value) {
                        if (value == 'edit') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CreateWorkoutScreen(
                            docId: latestWorkoutDoc.id,
                            initialName: data['name'],
                            initialExercises: List<String>.from(data['exercises']),
                          )));
                        } else if (value == 'delete') {
                          DatabaseService().deleteWorkout(latestWorkoutDoc.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 12), Text("Редактировать", style: TextStyle(color: Colors.white))]),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 12), Text("Удалить", style: TextStyle(color: Colors.white))]),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text("${workoutObj.exercises.length} упражнений", style: const TextStyle(color: Color(0xFF8E8E93))),
                const SizedBox(height: 16),
                NeonActionButton(
                  text: 'НАЧАТЬ',
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (context) => WorkoutSessionScreen(workout: workoutObj)));
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              onPressed: () {
                 Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CreateWorkoutScreen()));
              },
              icon: const Icon(Icons.add, color: Colors.grey),
              label: const Text("СОЗДАТЬ НОВУЮ", style: TextStyle(color: Colors.grey)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

// ВИДЖЕТ ЭЛЕМЕНТА СТАТИСТИКИ
class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final bool isHighlighted;
  const _StatItem({required this.value, required this.label, this.isHighlighted = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: isHighlighted ? const Color(0xFFCCFF00) : Colors.white)),
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// --- ВКЛАДКА 2: СПИСОК ВСЕХ ТРЕНИРОВОК ---
class WorkoutsListTab extends StatelessWidget {
  const WorkoutsListTab({super.key});

  Workout _convertDocToWorkout(QueryDocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    List<dynamic> exerciseNames = data['exercises'] ?? [];
    List<Exercise> exercises = exerciseNames.map((name) {
      return Exercise(id: DateTime.now().toString(), title: name.toString(), muscleGroup: "Общее");
    }).toList();
    return Workout(name: data['name'] ?? "Без названия", exercises: exercises);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Мои Программы'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFFCCFF00)),
            onPressed: () {
               Navigator.of(context).push(MaterialPageRoute(builder: (context) => const CreateWorkoutScreen()));
            },
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: DatabaseService().getUserWorkouts(),
        builder: (context, snapshot) {
           if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
             return Center(child: Text("Нет программ", style: TextStyle(color: Colors.white.withOpacity(0.5))));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final workout = _convertDocToWorkout(doc);
              final data = doc.data() as Map<String, dynamic>;

              return PremiumGlassCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => WorkoutSessionScreen(workout: workout))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(workout.name, style: Theme.of(context).textTheme.titleLarge),
                          Text("${workout.exercises.length} упражнений", style: const TextStyle(color: Color(0xFF8E8E93))),
                        ],
                      ),
                    ),
                    
                    // --- МЕНЮ В СПИСКЕ ---
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      color: const Color(0xFF1C1C1E),
                      onSelected: (value) {
                        if (value == 'edit') {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CreateWorkoutScreen(
                            docId: doc.id,
                            initialName: data['name'],
                            initialExercises: List<String>.from(data['exercises']),
                          )));
                        } else if (value == 'delete') {
                          DatabaseService().deleteWorkout(doc.id);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 12), Text("Редактировать", style: TextStyle(color: Colors.white))]),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 12), Text("Удалить", style: TextStyle(color: Colors.white))]),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        }
      ),
    );
  }
}