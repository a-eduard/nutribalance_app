import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_localization/easy_localization.dart';

// Импортируем обертку (путь должен быть верным)
import 'screens/home_wrapper.dart';

// Обработчик фоновых пушей (обязательно вне класса)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Firebase
  await Firebase.initializeApp();
  
  // Регистрация фонового обработчика
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Инициализация локализации
  await EasyLocalization.ensureInitialized();

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
      title: 'TONNA GYM',
      debugShowCheckedModeBanner: false,
      
      // Настройки локализации
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        // DESIGN FIX: Новый акцентный цвет #9CD600
        primaryColor: const Color(0xFF9CD600), 
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF9CD600),
          secondary: const Color(0xFF9CD600),
        ),
      ),
      
      // Точка входа — наш исправленный HomeWrapper
      home: const HomeWrapper(),
    );
  }
}