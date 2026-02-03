class Exercise {
  final String id;
  final String title;
  final String muscleGroup;

  Exercise({
    required this.id,
    required this.title,
    required this.muscleGroup,
  });
}

class Workout {
  final String name;
  final List<Exercise> exercises;
  final Map<String, String> targets; // Цели упражнений

  Workout({
    required this.name,
    required this.exercises,
    this.targets = const {}, 
  });
}