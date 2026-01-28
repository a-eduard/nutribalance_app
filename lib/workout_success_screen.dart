import 'package:flutter/material.dart';
import 'dashboard_screen.dart'; // Для возврата домой

class WorkoutSuccessScreen extends StatelessWidget {
  final int durationInMinutes;
  final int totalWeight;
  final int exercisesCount;

  const WorkoutSuccessScreen({
    super.key,
    required this.durationInMinutes,
    required this.totalWeight,
    required this.exercisesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // 1. Иконка Трофея с Hero анимацией
              const Hero(
                tag: 'trophy_icon',
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 120,
                  color: Color(0xFFCCFF00), // Neon Lime
                ),
              ),

              const SizedBox(height: 32),

              // 2. Заголовки
              Text(
                'ТРЕНИРОВКА ЗАВЕРШЕНА!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Ты стал сильнее, чем вчера.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
              ),

              const SizedBox(height: 48),

              // 3. Блок Статистики
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _StatItem(
                    value: '$durationInMinutes',
                    label: 'Мин',
                    subLabel: 'Время',
                  ),
                  _StatItem(
                    value: '$totalWeight',
                    label: 'кг',
                    subLabel: 'Тоннаж',
                  ),
                  _StatItem(
                    value: '$exercisesCount',
                    label: '',
                    subLabel: 'Упражнений',
                  ),
                ],
              ),

              const Spacer(),

              // 4. Кнопки
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Функция "Поделиться" будет доступна позже!',
                        ),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text(
                    'ПОДЕЛИТЬСЯ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2C2C2E), width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Удаляем все экраны из стека и возвращаемся на Dashboard
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const DashboardScreen(),
                      ),
                      (Route<dynamic> route) => false,
                    );
                  },
                  child: const Text('ДОМОЙ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final String subLabel;

  const _StatItem({
    required this.value,
    required this.label,
    required this.subLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Manrope', // Или RobotoMono если хочется цифр
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            if (label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8E8E93),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subLabel.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8E8E93),
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}
