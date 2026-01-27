// lib/exercise_data.dart

class Exercise {
  final String id;
  final String title;
  final String muscleGroup; // "Грудь", "Спина" и т.д.

  const Exercise({
    required this.id,
    required this.title,
    required this.muscleGroup,
  });
}

// Наша база данных (Mock Data)
final List<Exercise> mockExercises = [
  const Exercise(id: '1', title: 'Жим лежа', muscleGroup: 'Грудь'),
  const Exercise(id: '2', title: 'Разводка гантелей', muscleGroup: 'Грудь'),
  const Exercise(id: '3', title: 'Подтягивания', muscleGroup: 'Спина'),
  const Exercise(id: '4', title: 'Тяга штанги в наклоне', muscleGroup: 'Спина'),
  const Exercise(id: '5', title: 'Приседания', muscleGroup: 'Ноги'),
  const Exercise(id: '6', title: 'Жим ногами', muscleGroup: 'Ноги'),
  const Exercise(id: '7', title: 'Жим Арнольда', muscleGroup: 'Плечи'),
  const Exercise(id: '8', title: 'Бицепс со штангой', muscleGroup: 'Руки'),
  const Exercise(id: '9', title: 'Французский жим', muscleGroup: 'Руки'),
  const Exercise(id: '10', title: 'Планка', muscleGroup: 'Пресс'),
];
