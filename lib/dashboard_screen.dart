import 'package:flutter/material.dart';
import 'workout_session_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    HomeTab(),
    Center(child: Text('WORKOUTS (Coming Soon)')),
    Center(child: Text('PROFILE (Coming Soon)')),
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
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.fitness_center),
            label: 'Workout',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
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
          'START YOUR JOURNEY TODAY',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Create a workout plan tailored to your goals and fitness level.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () {},
          child: const Text('CREATE FIRST PROGRAM'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

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
                    'HELLO, CHAMPION',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Let\'s crush it today!',
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
            'TODAY\'S WORKOUT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF8E8E93),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const _WorkoutCard(),
          const SizedBox(height: 40),
          Text(
            'ACTIVITY',
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
                  'FULL BODY START',
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
                Text('45 min', style: TextStyle(color: Color(0xFF8E8E93))),
                SizedBox(width: 16),
                Icon(
                  Icons.local_fire_department_outlined,
                  size: 16,
                  color: Color(0xFF8E8E93),
                ),
                SizedBox(width: 8),
                Text('320 kcal', style: TextStyle(color: Color(0xFF8E8E93))),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WorkoutSessionScreen(),
                  ),
                );
              },
              child: const Text('START'),
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
