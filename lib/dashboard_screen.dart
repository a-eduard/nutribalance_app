import 'package:flutter/material.dart';
import 'workout_session_screen.dart'; // Плеер тренировки
import 'create_workout_screen.dart'; // Конструктор тренировки (НОВОЕ)

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeTab(),
    Center(child: Text('ТРЕНИРОВКИ (Скоро)')),
    Center(child: Text('ПРОФИЛЬ (Скоро)')),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: const Color(0xFFCCFF00),
        unselectedItemColor: const Color(0xFF8E8E93),
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center),
            label: 'Тренировка',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    // -----------------------------------------------------------
    // ПЕРЕКЛЮЧАТЕЛЬ ДЛЯ ТЕСТА:
    // false = Видим экран "Новичка" (Кнопка "Создать программу")
    // true  = Видим экран "Опытного" (Кнопка "Начать")
    // -----------------------------------------------------------
    bool hasActiveProgram = true;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: hasActiveProgram
            ? const _ActiveStateView()
            : const _EmptyStateView(),
      ),
    );
  }
}

/// ВАРИАНТ 1: Новичок (Empty State)
class _EmptyStateView extends StatelessWidget {
  const _EmptyStateView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: const BoxDecoration(
            color: Color(0xFF2C2C2E),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add_task, size: 64, color: Color(0xFF8E8E93)),
        ),
        const SizedBox(height: 32),
        Text(
          'НАЧНИ СВОЙ ПУТЬ',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Создай план тренировок, адаптированный под твои цели и уровень подготовки.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
        ),
        const Spacer(),
        // КНОПКА ВЕДЕТ В КОНСТРУКТОР
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const CreateWorkoutScreen(),
              ),
            );
          },
          child: const Text('СОЗДАТЬ ПРОГРАММУ'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// ВАРИАНТ 2: Опытный (Dashboard)
class _ActiveStateView extends StatelessWidget {
  const _ActiveStateView();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ПРИВЕТ, ЧЕМПИОН',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Давай порвем этот день!',
                    style: TextStyle(color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF2C2C2E),
                child: Icon(Icons.person, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 40),
          Text(
            'СЕГОДНЯ ПО ПЛАНУ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF8E8E93),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const _WorkoutCard(),
          const SizedBox(height: 40),
          Text(
            'АКТИВНОСТЬ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF8E8E93),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const _ActivityChartStub(),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ФУЛЛ-БОДИ СТАРТ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Icon(Icons.fitness_center, color: Color(0xFFCCFF00)),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: Color(0xFF8E8E93)),
                SizedBox(width: 8),
                Text('45 мин', style: TextStyle(color: Color(0xFF8E8E93))),
                SizedBox(width: 16),
                Icon(
                  Icons.local_fire_department_outlined,
                  size: 16,
                  color: Color(0xFF8E8E93),
                ),
                SizedBox(width: 8),
                Text('320 ккал', style: TextStyle(color: Color(0xFF8E8E93))),
              ],
            ),
            const SizedBox(height: 24),
            // КНОПКА ВЕДЕТ В ПЛЕЕР
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WorkoutSessionScreen(),
                  ),
                );
              },
              child: const Text('НАЧАТЬ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityChartStub extends StatelessWidget {
  const _ActivityChartStub();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (index) {
        final height = [40.0, 60.0, 30.0, 80.0, 50.0, 90.0, 20.0][index];
        final isToday = index == 5;
        return Container(
          width: 32,
          height: height,
          decoration: BoxDecoration(
            color: isToday ? const Color(0xFFCCFF00) : const Color(0xFF2C2C2E),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      }),
    );
  }
}
