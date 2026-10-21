import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Единая точка для статистики: каждое событие уходит и в Firebase Analytics,
/// и в AppMetrica (Яндекс). Ошибки отправки никогда не ломают приложение.
///
/// ВАЖНО: в статистику не отправляем имена, почту, даты цикла, симптомы и
/// любые данные о здоровье — только обезличенные действия и категории.
class Analytics {
  Analytics._();

  /// API key из AppMetrica: appmetrica.yandex.ru → приложение → Настройки.
  /// Пока строка пустая, AppMetrica не включается (Firebase работает всё равно).
  static const String appMetricaApiKey = '26cd32fe-dd76-41a4-9ca1-ed2d9b3ed20b';

  static bool _appMetricaReady = false;
  static String? _lastUserId;

  static FirebaseAnalytics? get _firebase {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null; // Firebase не инициализирован
    }
  }

  static FirebaseCrashlytics? get _crashlytics {
    try {
      return FirebaseCrashlytics.instance;
    } catch (_) {
      return null;
    }
  }

  /// Вызывается один раз в main() после Firebase.initializeApp.
  static Future<void> init() async {
    try {
      // В отладочных сборках падения не отправляем, чтобы не засорять отчёты.
      await _crashlytics?.setCrashlyticsCollectionEnabled(!kDebugMode);
    } catch (e) {
      debugPrint('Crashlytics init: $e');
    }
    if (appMetricaApiKey.isNotEmpty) {
      try {
        await AppMetrica.activate(AppMetricaConfig(
          appMetricaApiKey,
          logs: kDebugMode,
          // Падения Flutter-кода собирает Crashlytics; AppMetrica — только нативные.
          flutterCrashReporting: false,
        ));
        _appMetricaReady = true;
      } catch (e) {
        debugPrint('AppMetrica init: $e');
      }
    }
  }

  /// Отслеживание экранов (добавляется в MaterialApp.navigatorObservers).
  /// Список создаётся один раз: MaterialApp перестраивается при смене темы.
  static final List<NavigatorObserver> navigatorObservers = _buildObservers();

  static List<NavigatorObserver> _buildObservers() {
    final fa = _firebase;
    return fa == null ? <NavigatorObserver>[] : <NavigatorObserver>[FirebaseAnalyticsObserver(analytics: fa)];
  }

  // ---------------------------------------------------------------------------
  // Ошибки
  // ---------------------------------------------------------------------------

  static void recordFlutterError(FlutterErrorDetails details) {
    try {
      _crashlytics?.recordFlutterFatalError(details);
    } catch (_) {}
  }

  /// Тестовое падение — чтобы Crashlytics получил первый отчёт и открыл панель.
  /// Доступно только аккаунту поддержки (меню «Администратор» в профиле).
  static Future<void> testCrash() async {
    final c = _crashlytics;
    if (c == null) return;
    await c.setCrashlyticsCollectionEnabled(true);
    c.crash();
  }

  static void recordError(Object error, StackTrace stack, {bool fatal = false}) {
    try {
      _crashlytics?.recordError(error, stack, fatal: fatal);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Пользователь
  // ---------------------------------------------------------------------------

  /// Идентификатор — Firebase UID (без имени и почты). null — выход из аккаунта.
  static void setUser(String? uid) {
    if (uid == _lastUserId) return;
    _lastUserId = uid;
    _safe(() => _firebase?.setUserId(id: uid));
    _safe(() => _crashlytics?.setUserIdentifier(uid ?? ''));
    if (_appMetricaReady) _safe(() => AppMetrica.setUserProfileID(uid));
  }

  static final Map<String, String> _sentProperties = {};

  /// Свойства для фильтров в отчётах: режим, Premium, цель и т.п.
  static void setUserProperties(Map<String, String?> properties) {
    final changed = <String, String>{};
    properties.forEach((key, value) {
      final String v = (value ?? '').trim();
      if (v.isEmpty || _sentProperties[key] == v) return;
      _sentProperties[key] = v;
      changed[key] = v.length > 36 ? v.substring(0, 36) : v;
    });
    if (changed.isEmpty) return;
    changed.forEach((key, value) => _safe(() => _firebase?.setUserProperty(name: key, value: value)));
    if (_appMetricaReady) {
      _safe(() => AppMetrica.reportUserProfile(AppMetricaUserProfile([
            for (final e in changed.entries) AppMetricaStringAttribute.withValue(e.key, e.value),
          ])));
    }
  }

  // ---------------------------------------------------------------------------
  // События
  // ---------------------------------------------------------------------------

  static void event(String name, [Map<String, Object?> params = const {}]) {
    final Map<String, Object> clean = {};
    params.forEach((key, value) {
      if (value == null) return;
      if (value is bool) {
        clean[key] = value ? 'yes' : 'no';
      } else if (value is num) {
        clean[key] = value;
      } else {
        final String s = value.toString();
        clean[key] = s.length > 100 ? s.substring(0, 100) : s;
      }
    });
    _safe(() => _firebase?.logEvent(name: name, parameters: clean.isEmpty ? null : clean));
    if (_appMetricaReady) _safe(() => AppMetrica.reportEventWithMap(name, clean.isEmpty ? null : clean));
  }

  static void login(String method) {
    _safe(() => _firebase?.logLogin(loginMethod: method));
    if (_appMetricaReady) _safe(() => AppMetrica.reportEventWithMap('login', {'method': method}));
  }

  static void signUp(String method) {
    _safe(() => _firebase?.logSignUp(signUpMethod: method));
    if (_appMetricaReady) _safe(() => AppMetrica.reportEventWithMap('sign_up', {'method': method}));
  }

  /// Успешная покупка в RuStore.
  static void purchase({required String productId, double? value, String currency = 'RUB'}) {
    _safe(() => _firebase?.logPurchase(
          currency: currency,
          value: value,
          items: [AnalyticsEventItem(itemId: productId, itemName: productId, price: value, quantity: 1)],
        ));
    if (_appMetricaReady) {
      _safe(() => AppMetrica.reportEventWithMap('purchase', {
            'product_id': productId,
            if (value != null) 'value': value,
            'currency': currency,
          }));
    }
  }

  static void _safe(Future<void>? Function() action) {
    try {
      final Future<void>? f = action();
      f?.catchError((Object e) => debugPrint('analytics: $e'));
    } catch (e) {
      debugPrint('analytics: $e');
    }
  }
}
