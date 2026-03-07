import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ИМПОРТ ДЛЯ UI Overlay
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'screens/home_wrapper.dart';
import 'paywall_screen.dart'; 

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // UI FIX: Белый статус-бар с прозрачным фоном
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ru')], 
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
      title: 'NutriBalance',
      debugShowCheckedModeBanner: false,
      
      // Настройки локализации (так как у тебя используется easy_localization)
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      // НОВАЯ СВЕТЛАЯ ТЕМА
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF9F9F9), // Нежный светло-серый фон
        primaryColor: const Color(0xFFB76E79), // Наш Rose Gold
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFB76E79),
          secondary: Color(0xFFD49A89), // Персиковый для градиентов
          surface: Colors.white, // Белый цвет для карточек
        ),
        
        // Делаем весь стандартный текст темно-серым (почти черным) для читаемости на белом
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: const Color(0xFF2D2D2D),
          displayColor: const Color(0xFF2D2D2D),
        ),
        
        // Настройка верхней панели (AppBar) под светлый стиль
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF9F9F9), // Сливается с фоном приложения
          elevation: 0, // Убираем тень
          iconTheme: IconThemeData(color: Color(0xFF2D2D2D)), // Темные иконки (кнопка "назад" и т.д.)
          titleTextStyle: TextStyle(
            color: Color(0xFF2D2D2D), // Темный заголовок
            fontSize: 18, 
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      
      // Корневой виджет с проверкой авторизации
      home: const HomeWrapper(),
    );
  }
}