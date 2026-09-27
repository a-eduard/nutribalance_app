import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'screens/home_wrapper.dart';
import 'services/app_navigator.dart';
import 'services/local_notification_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ошибки не должны молча ронять приложение — логируем их.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('Uncaught async error: $error');
    return true;
  };

  // Firebase — критичная зависимость. Остальное инициализируем «мягко»,
  // чтобы сбой одной службы (часовой пояс, RuStore, VPN) не блокировал запуск.
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('⚠️ Firebase init error: $e');
  }

  try {
    // Офлайн-кэш без ограничения размера: данные показываются мгновенно,
    // а записи копятся локально, если сеть/VPN нестабильны.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  } catch (e) {
    debugPrint('⚠️ Firestore settings error: $e');
  }

  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('⚠️ FCM background handler error: $e');
  }

  try {
    RustoreBillingClient.initialize('2063702590', 'nutribalance', kDebugMode);
  } catch (e) {
    debugPrint("⚠️ RuStore Billing не доступен: $e");
  }

  await Future.wait<void>([
    EasyLocalization.ensureInitialized(),
    initializeDateFormatting('ru'),
    ThemeService().init().catchError((Object e) => debugPrint('⚠️ Theme init: $e')),
    LocalNotificationService().init().catchError((Object e) => debugPrint('⚠️ Local notifications init: $e')),
  ]);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ru'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ru'),
      startLocale: const Locale('ru'),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService().themeModeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'Моя Ева',
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.key,
          scaffoldMessengerKey: AppNavigator.messengerKey,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          themeAnimationDuration: const Duration(milliseconds: 350),
          builder: (context, child) {
            final bool dark = Theme.of(context).brightness == Brightness.dark;
            final SystemUiOverlayStyle overlay = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            );
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlay,
              // Ограничиваем системный масштаб шрифта, чтобы вёрстка не «ломалась».
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.25,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const HomeWrapper(),
        );
      },
    );
  }
}
