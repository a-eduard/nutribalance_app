// Виджет на рабочий стол Android: день цикла + сколько калорий осталось сегодня.
// Данные пишутся в общие настройки (home_widget), нативный EvaWidgetProvider
// перерисовывает виджет. Обновляем только при изменении значений.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const String _provider = 'com.eduard.nutribalance.EvaWidgetProvider';
  static String? _lastCycle;
  static String? _lastKcal;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// [day] — день цикла (null, если начало цикла не отмечено), [phase] — название фазы.
  static void updateCycle({required int? day, required String phase}) {
    if (!_supported) return;
    final String dayText = day == null ? '—' : '$day';
    final String key = '$dayText|$phase';
    if (key == _lastCycle) return;
    _lastCycle = key;
    _save({'cycle_day': dayText, 'cycle_phase': phase});
  }

  /// Калории за сегодня: [consumed] съедено, [target] норма (0 — норма не задана).
  static void updateCalories({required int consumed, required int target}) {
    if (!_supported) return;
    String value;
    String label;
    if (target <= 0) {
      value = '$consumed';
      label = 'ккал сегодня';
    } else if (consumed <= target) {
      value = '${target - consumed}';
      label = 'ккал осталось';
    } else {
      value = '+${consumed - target}';
      label = 'ккал сверх нормы';
    }
    final String key = '$value|$label';
    if (key == _lastKcal) return;
    _lastKcal = key;
    _save({'kcal_left': value, 'kcal_label': label});
  }

  /// Партнёрский аккаунт: тот же виджет, но слева её день цикла и фаза,
  /// справа — сколько дней до месячных.
  static void updatePartner({required String name, required int? day, required String phase, required int? daysLeft}) {
    if (!_supported) return;
    final String dayText = day == null ? '—' : '$day';
    final String left = daysLeft == null ? '—' : '$daysLeft';
    final String label = daysLeft == null ? name : 'дн. до месячных';
    final String key = 'p|$name|$dayText|$phase|$left';
    if (key == _lastCycle) return;
    _lastCycle = key;
    _lastKcal = null;
    _save({'cycle_day': dayText, 'cycle_phase': '$name · $phase', 'kcal_left': left, 'kcal_label': label});
  }

  static Future<void> _save(Map<String, String> values) async {
    try {
      for (final e in values.entries) {
        await HomeWidget.saveWidgetData<String>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('home widget: $e');
    }
  }
}
