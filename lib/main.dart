import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';

import 'firebase_options.dart';
import 'screens/home_wrapper.dart';
import 'services/local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

   // === ОТКЛЮЧЕНО ДЛЯ ЛОКАЛЬНОГО ТЕСТИРОВАНИЯ ===
  // Firebase App Check блокирует запросы с эмулятора (ошибка 403 App attestation failed).
  // Раскомментируй этот блок только перед релизом в Google Play / App Store!
  /*
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
    debugPrint("✅ App Check готов");
  } catch (e) {
    debugPrint("❌ Ошибка App Check: $e");
  }
  */

  await LocalNotificationService().init();
  await EasyLocalization.ensureInitialized();

  // Делаем статус-бар прозрачным с темными иконками для премиального вида
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

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
    return MaterialApp(
      title: 'MyEva',
      debugShowCheckedModeBanner: false,
      
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF9F9F9), 
        primaryColor: const Color(0xFFB76E79), 
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFB76E79),
          secondary: Color(0xFFD49A89), 
          surface: Colors.white, 
        ),
        
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF2D2D2D),
          displayColor: const Color(0xFF2D2D2D),
        ),
        
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF9F9F9),
          elevation: 0, 
          iconTheme: IconThemeData(color: Color(0xFF2D2D2D)), 
          titleTextStyle: TextStyle(
            color: Color(0xFF2D2D2D), 
            fontSize: 20, 
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),

        // ПРЕМИАЛЬНЫЙ СТИЛЬ НИЖНЕЙ ПАНЕЛИ
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 0,
          selectedItemColor: Color(0xFFB76E79),
          unselectedItemColor: Color(0xFF8E8E93),
          selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
          type: BottomNavigationBarType.fixed,
        ),
      ),
      
      home: const HomeWrapper(),
    );
  }
}