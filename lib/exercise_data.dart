// lib/exercise_data.dart

// 1. Модель Упражнения
class Exercise {
  final String id;
  final String title;
  final String muscleGroup; 

  const Exercise({
    required this.id,
    required this.title,
    required this.muscleGroup,
  });
}

// 2. Модель Шаблона Тренировки
class Workout {
  final String name;
  final List<Exercise> exercises;
  final Map<String, String> targets; // <--- НОВОЕ ПОЛЕ

  Workout({
    required this.name,
    required this.exercises,
    this.targets = const {}, // По умолчанию пустая map
  });
}

// 3. Модель ЛОГА (Завершенная тренировка)
class WorkoutLog {
  final String workoutName;
  final DateTime date;
  final int totalVolume;
  final int durationMinutes;
  // Данные упражнений: { "Жим лежа": [{weight: 100, reps: 10}, ...] }
  final Map<String, List<Map<String, dynamic>>> exerciseLogs;

  WorkoutLog({
    required this.workoutName,
    required this.date,
    required this.totalVolume,
    required this.durationMinutes,
    required this.exerciseLogs,
  });
}

// 4. Глобальный сервис (State)
class WorkoutDataService {
  static List<Workout> userWorkouts = [];

  static void addWorkout(Workout workout) {
    userWorkouts.add(workout);
  }

  // --- ИСТОРИЯ (НОВОЕ) ---
  static List<WorkoutLog> completedWorkouts = [];

  static void saveLog(WorkoutLog log) {
    completedWorkouts.add(log);
  }

  // Получить данные последней тренировки для конкретного упражнения
  static List<Map<String, dynamic>>? getLastSetsFor(String exerciseTitle) {
    // Ищем с конца (самые новые)
    for (var log in completedWorkouts.reversed) {
      if (log.exerciseLogs.containsKey(exerciseTitle)) {
        return log.exerciseLogs[exerciseTitle];
      }
    }
    return null; // Если упражнение делаем впервые
  }

  // Получить объем прошлой тренировки с таким же названием (для сравнения)
  static int getLastVolumeForWorkout(String workoutName) {
    for (var log in completedWorkouts.reversed) {
      if (log.workoutName == workoutName) {
        return log.totalVolume;
      }
    }
    return 0;
  }

  // Статистика за последние 7 дней
  static Map<String, int> getWeeklyStats() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    
    int workouts = 0;
    int volume = 0;

    for (var log in completedWorkouts) {
      if (log.date.isAfter(weekAgo)) {
        workouts++;
        volume += log.totalVolume;
      }
    }
    return {"workouts": workouts, "volume": volume};
  }
  
  // Метод для добавления кастомного упражнения
  static void addCustomExercise(Exercise exercise) {
    mockExercises.add(exercise);
  }
}

// 5. База упражнений
final List<Exercise> mockExercises = [
  const Exercise(id: '1', title: 'Жим штанги лежа', muscleGroup: 'Грудь'),
  const Exercise(id: '2', title: 'Жим гантелей на наклонной', muscleGroup: 'Грудь'),
  const Exercise(id: '3', title: 'Сведение в кроссовере', muscleGroup: 'Грудь'),
  const Exercise(id: '4', title: 'Отжимания на брусьях', muscleGroup: 'Грудь'),
  const Exercise(id: '5', title: 'Подтягивания', muscleGroup: 'Спина'),
  const Exercise(id: '6', title: 'Тяга штанги в наклоне', muscleGroup: 'Спина'),
  const Exercise(id: '7', title: 'Тяга верхнего блока', muscleGroup: 'Спина'),
  const Exercise(id: '8', title: 'Гиперэкстензия', muscleGroup: 'Спина'),
  const Exercise(id: '9', title: 'Приседания со штангой', muscleGroup: 'Ноги'),
  const Exercise(id: '10', title: 'Жим ногами', muscleGroup: 'Ноги'),
  const Exercise(id: '11', title: 'Выпады с гантелями', muscleGroup: 'Ноги'),
  const Exercise(id: '12', title: 'Сгибание ног в тренажере', muscleGroup: 'Ноги'),
  const Exercise(id: '13', title: 'Разгибание ног', muscleGroup: 'Ноги'),
  const Exercise(id: '14', title: 'Армейский жим', muscleGroup: 'Плечи'),
  const Exercise(id: '15', title: 'Махи гантелями в стороны', muscleGroup: 'Плечи'),
  const Exercise(id: '16', title: 'Тяга штанги к подбородку', muscleGroup: 'Плечи'),
  const Exercise(id: '17', title: 'Подъем штанги на бицепс', muscleGroup: 'Руки'),
  const Exercise(id: '18', title: 'Молотки', muscleGroup: 'Руки'),
  const Exercise(id: '19', title: 'Французский жим', muscleGroup: 'Руки'),
  const Exercise(id: '20', title: 'Разгибание на блоке', muscleGroup: 'Руки'),
];