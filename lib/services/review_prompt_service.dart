import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_review/flutter_rustore_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

/// Просьба оценить приложение в RuStore.
///
/// Правила RuStore для SDK оценок: без кнопки «Оценить приложение» и без вопросов
/// перед окном («Вам нравится?», «Поставите 5 звёзд?»), окно показываем как есть
/// и не слишком часто. Поэтому окно RuStore открывается само, в удачный момент:
/// пользователь пользуется приложением 3+ разных дня и только что получил ответ Евы.
/// Звёзды пользователь ставит сам.
class ReviewPromptService {
  ReviewPromptService._();

  static const int minActiveDays = 3;
  static const int maxAttempts = 3;
  static const Duration minInterval = Duration(days: 30);

  static const String _kDays = 'review_active_days';
  static const String _kLastDay = 'review_last_active_day';
  static const String _kAttempts = 'review_attempts';
  static const String _kLastAttempt = 'review_last_attempt_ms';
  static const String _kDone = 'review_done';

  static bool _initialized = false;
  static bool _inProgress = false;

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Отмечает сегодняшний день как день использования (вызывать при открытии приложения).
  static Future<void> recordActiveDay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String today = _dayKey(DateTime.now());
      if (prefs.getString(_kLastDay) == today) return;
      await prefs.setString(_kLastDay, today);
      await prefs.setInt(_kDays, (prefs.getInt(_kDays) ?? 0) + 1);
    } catch (e) {
      debugPrint('ReviewPrompt.recordActiveDay: $e');
    }
  }

  /// Открывает окно оценки RuStore, если все условия выполнены. Ошибки не показываем пользователю.
  static Future<void> maybeAsk() async {
    if (kIsWeb || !Platform.isAndroid || _inProgress) return;
    _inProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_kDone) == true) return;
      if ((prefs.getInt(_kDays) ?? 0) < minActiveDays) return;
      final int attempts = prefs.getInt(_kAttempts) ?? 0;
      if (attempts >= maxAttempts) return;
      final int lastMs = prefs.getInt(_kLastAttempt) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - lastMs < minInterval.inMilliseconds) return;

      if (!_initialized) {
        await RustoreReviewClient.initialize();
        _initialized = true;
      }
      await RustoreReviewClient.request();
      await prefs.setInt(_kAttempts, attempts + 1);
      await prefs.setInt(_kLastAttempt, DateTime.now().millisecondsSinceEpoch);
      Analytics.event('review_flow_shown', {'attempt': attempts + 1});
      await RustoreReviewClient.review();
      // SDK не сообщает, какую оценку поставили и поставили ли вообще — считаем процесс завершённым.
      await prefs.setBool(_kDone, true);
      Analytics.event('review_flow_finished');
    } catch (e) {
      final String err = e.toString();
      if (err.contains('ReviewExists')) {
        // Пользователь уже оценил приложение — больше не просим.
        try {
          (await SharedPreferences.getInstance()).setBool(_kDone, true);
        } catch (_) {}
      }
      Analytics.event('review_flow_error', {'type': _errorType(err)});
      debugPrint('ReviewPrompt.maybeAsk: $err');
    } finally {
      _inProgress = false;
    }
  }

  static String _errorType(String err) {
    for (final t in ['NotInstalled', 'Outdated', 'UserUnauthorized', 'RequestLimitReached', 'ReviewExists', 'InvalidReviewInfo']) {
      if (err.contains(t)) return t;
    }
    return 'other';
  }
}
