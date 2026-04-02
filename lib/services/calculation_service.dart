import 'package:flutter/foundation.dart';
import 'database_service.dart';

class CalculationService {
  final DatabaseService _dbService = DatabaseService();

  // Главный метод пересчета КБЖУ
  Future<void> recalculateAndSaveGoals({
    required double weight,
    required double height,
    required int age,
    required String goal,
    required String activityLevel,
    required bool isPregnant,
  }) async {
    try {
      // 1. Базовый обмен веществ (BMR) по формуле Миффлина-Сан Жеора для женщин
      double bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;

      // 2. Коэффициент активности
      double multiplier = 1.2; // Низкая
      if (activityLevel.contains('Умеренная')) {
        multiplier = 1.375;
      } else if (activityLevel.contains('Высокая')) {
        multiplier = 1.55;
      } else if (activityLevel.contains('Очень высокая')) {
        multiplier = 1.725;
      }

      int maintenance = (bmr * multiplier).round();
      int targetCals = maintenance;

      // 3. Цель и Safety-логика
      if (isPregnant || goal == 'Здоровая беременность') {
        // SAFETY: Для беременных дефицит запрещен! 
        // Даем базу + 300 ккал (усредненно для 2-3 триместра)
        targetCals = maintenance + 300;
      } else {
        if (goal == 'Похудеть') {
          targetCals = (maintenance * 0.85).round(); // Дефицит 15%
        } else if (goal == 'Набрать массу' || goal == 'Набрать вес') {
          targetCals = (maintenance * 1.15).round(); // Профицит 15%
        }
      }

      // 4. Расчет БЖУ (Белки: 1.8г/кг, Жиры: 1.0г/кг, Углеводы: остаток)
      int protein = (weight * 1.8).round();
      int fat = (weight * 1.0).round();
      int carbs = ((targetCals - (protein * 4) - (fat * 9)) / 4).round();
      if (carbs < 0) carbs = 0; // Защита от отрицательных значений

      // 5. Сохраняем расчеты в БД
      await _dbService.saveNutritionGoal({
        'calories': targetCals,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
      });

      // Обновляем базовые показатели в профиле
      await _dbService.updateUserData({
        'bmr': bmr.round(),
        'maintenanceCalories': maintenance,
        'goal': goal,
        'activityLevel': activityLevel,
        'isPregnant': isPregnant || goal == 'Здоровая беременность',
      });

      debugPrint("КБЖУ успешно пересчитано и сохранено: $targetCals ккал");
    } catch (e) {
      debugPrint("Ошибка в CalculationService: $e");
    }
  }
}