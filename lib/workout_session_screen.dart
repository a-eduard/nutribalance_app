import 'dart:async';
import 'dart:ui'; // Для FontFeature
import 'package:flutter/material.dart';
import 'workout_success_screen.dart'; // <--- ВАЖНЫЙ ИМПОРТ

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Timer? _timer;
  int _secondsElapsed = 0;

  // Данные тренировки
  final List<Map<String, dynamic>> _exercises = [
    {
      "title": "Жим лежа (Штанга)",
      "sets": [
        {"weight": "60", "reps": "12", "isCompleted": false},
        {"weight": "60", "reps": "10", "isCompleted": false},
        {"weight": "60", "reps": "8", "isCompleted": false},
      ],
    },
    {
      "title": "Приседания",
      "sets": [
        {"weight": "80", "reps": "10", "isCompleted": false},
        {"weight": "80", "reps": "10", "isCompleted": false},
        {"weight": "80", "reps": "10", "isCompleted": false},
      ],
    },
    {
      "title": "Подтягивания",
      "sets": [
        {"weight": "0", "reps": "10", "isCompleted": false},
        {"weight": "0", "reps": "8", "isCompleted": false},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  // Логика завершения тренировки
  void _finishWorkout() {
    int totalVolume = 0;
    int completedExercisesCount = 0;

    // 1. Проходим по всем упражнениям
    for (var exercise in _exercises) {
      bool isExerciseStarted = false;

      for (var set in exercise['sets']) {
        // Если сет выполнен (галочка стоит)
        if (set['isCompleted'] == true) {
          isExerciseStarted = true;
          // Парсим вес и повторы (защита от ошибок, если там пусто)
          int weight = int.tryParse(set['weight'].toString()) ?? 0;
          int reps = int.tryParse(set['reps'].toString()) ?? 0;

          // Если вес 0 (свой вес), можно считать условные 60-70кг или 0,
          // но для MVP считаем чистый поднятый вес железа.
          totalVolume += (weight * reps);
        }
      }

      if (isExerciseStarted) {
        completedExercisesCount++;
      }
    }

    // 2. Переходим на экран успеха
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WorkoutSuccessScreen(
          durationInMinutes: (_secondsElapsed ~/ 60), // Секунды в минуты
          totalWeight: totalVolume,
          exercisesCount: completedExercisesCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _formattedTime,
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          TextButton(
            onPressed: _finishWorkout,
            child: const Text(
              'ЗАВЕРШИТЬ',
              style: TextStyle(
                color: Color(0xFFCCFF00),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 100),
          itemCount: _exercises.length,
          itemBuilder: (context, index) {
            final exercise = _exercises[index];
            return _ExerciseCard(
              title: exercise['title'],
              setsData: exercise['sets'],
            );
          },
        ),
      ),
    );
  }
}

/// Виджет карточки упражнения
class _ExerciseCard extends StatelessWidget {
  final String title;
  final List<dynamic> setsData;

  const _ExerciseCard({required this.title, required this.setsData});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontSize: 18),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              children: const [
                SizedBox(
                  width: 24,
                  child: Text(
                    "СЕТ",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      "ВЕС (КГ)",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      "ПОВТОРЫ",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
                SizedBox(width: 44),
              ],
            ),
          ),
          ...setsData.asMap().entries.map((entry) {
            int setIndex = entry.key + 1;
            // Передаем ссылку на Map сета, чтобы обновлять данные напрямую
            Map<String, dynamic> setData = entry.value;
            return SetRowWidget(setNumber: setIndex, setData: setData);
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Виджет строки сета
class SetRowWidget extends StatefulWidget {
  final int setNumber;
  final Map<String, dynamic> setData; // Ссылка на данные сета

  const SetRowWidget({
    super.key,
    required this.setNumber,
    required this.setData,
  });

  @override
  State<SetRowWidget> createState() => _SetRowWidgetState();
}

class _SetRowWidgetState extends State<SetRowWidget> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: widget.setData['weight']);
    _repsController = TextEditingController(text: widget.setData['reps']);
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _toggleComplete() {
    setState(() {
      // Меняем состояние в UI
      bool currentStatus = widget.setData['isCompleted'] ?? false;
      widget.setData['isCompleted'] = !currentStatus;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isCompleted = widget.setData['isCompleted'] ?? false;

    // Используем withValues (современный аналог withOpacity)
    final backgroundColor = isCompleted
        ? Colors.green.withValues(alpha: 0.2)
        : Colors.transparent;

    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              "${widget.setNumber}",
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Поле Вес
          Expanded(child: _buildInput(_weightController, 'weight')),
          const SizedBox(width: 16),
          // Поле Повторы
          Expanded(child: _buildInput(_repsController, 'reps')),
          const SizedBox(width: 16),
          // Чекбокс
          InkWell(
            onTap: _toggleComplete,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFFCCFF00)
                    : const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.check,
                color: isCompleted ? Colors.black : Colors.grey,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String dataKey) {
    bool isCompleted = widget.setData['isCompleted'] ?? false;

    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        onChanged: (value) {
          // Обновляем данные в главном массиве при вводе текста
          widget.setData[dataKey] = value;
        },
        style: TextStyle(
          color: isCompleted ? const Color(0xFF8E8E93) : Colors.white,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: const Color(0xFF2C2C2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        enabled: !isCompleted,
      ),
    );
  }
}
