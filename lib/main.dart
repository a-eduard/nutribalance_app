import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';

import 'firebase_options.dart';
import 'screens/home_wrapper.dart';
import 'services/local_notification_service.dart';
import 'services/theme_service.dart'; 
import 'theme/app_theme.dart'; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    RustoreBillingClient.initialize('2063702590', 'nutribalance', true);
    debugPrint("✅ RuStore Billing успешно инициализирован");
  } catch (e) {
    debugPrint("⚠️ RuStore Billing не доступен: $e");
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await LocalNotificationService().init();
  await EasyLocalization.ensureInitialized();

  // Инициализируем сервис тем перед запуском
  await ThemeService().init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Убрали жесткую привязку Brightness.dark, теперь AppBarTheme управляет цветом иконок
    ),
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ru'), Locale('en')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ru'),
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
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode, // Реактивое переключение темы
          home: const HomeWrapper(),
        );
      },
    );
  }
}