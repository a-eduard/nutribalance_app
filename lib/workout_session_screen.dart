import 'dart:async';
import 'dart:ui'; // Нужно для FontFeature
import 'package:flutter/material.dart';

class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Timer? _timer;
  int _secondsElapsed = 0;

  final List<Map<String, dynamic>> _exercises = [
    {
      "title": "Bench Press (Barbell)",
      "sets": [
        {"weight": "60", "reps": "12", "isCompleted": false},
        {"weight": "60", "reps": "10", "isCompleted": false},
        {"weight": "60", "reps": "8", "isCompleted": false},
      ],
    },
    {
      "title": "Squat (Barbell)",
      "sets": [
        {"weight": "80", "reps": "10", "isCompleted": false},
        {"weight": "80", "reps": "10", "isCompleted": false},
        {"weight": "80", "reps": "10", "isCompleted": false},
      ],
    },
    {
      "title": "Pull Ups",
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'FINISH',
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
                    "SET",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      "KG",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Center(
                    child: Text(
                      "REPS",
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
            Map<String, dynamic> setData = entry.value;
            return SetRowWidget(
              setNumber: setIndex,
              initialWeight: setData['weight'],
              initialReps: setData['reps'],
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class SetRowWidget extends StatefulWidget {
  final int setNumber;
  final String initialWeight;
  final String initialReps;

  const SetRowWidget({
    super.key,
    required this.setNumber,
    required this.initialWeight,
    required this.initialReps,
  });

  @override
  State<SetRowWidget> createState() => _SetRowWidgetState();
}

class _SetRowWidgetState extends State<SetRowWidget> {
  bool isCompleted = false;
  late TextEditingController _weightController;
  late TextEditingController _repsController;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: widget.initialWeight);
    _repsController = TextEditingController(text: widget.initialReps);
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  void _toggleComplete() {
    setState(() {
      isCompleted = !isCompleted;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ИСПРАВЛЕНИЕ: withValues вместо withOpacity (убирает синюю ошибку)
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
          Expanded(child: _buildInput(_weightController)),
          const SizedBox(width: 16),
          Expanded(child: _buildInput(_repsController)),
          const SizedBox(width: 16),
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

  Widget _buildInput(TextEditingController controller) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
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
