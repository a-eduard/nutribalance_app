import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';

// --- ИСПРАВЛЕННЫЕ ИМПОРТЫ (Файлы лежат в корне lib) ---
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_wrapper.dart'; // Только этот в папке screens

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tonna Gym',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFCCFF00),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFCCFF00),
          secondary: Color(0xFFCCFF00),
          surface: Color(0xFF1C1C1E),
        ),
      ),
      home: const AppInitializer(),
    );
  }
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initFirebase();
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      print("--- FIREBASE INITIALIZED ---");
      
      // ПРОВЕРКА: Кто сейчас залогинен сразу после запуска?
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        print("--- ДИАГНОСТИКА: Пользователь НАЙДЕН: ${currentUser.email} (UID: ${currentUser.uid}) ---");
      } else {
        print("--- ДИАГНОСТИКА: Пользователь НЕ НАЙДЕН (null) ---");
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print("--- ОШИБКА FIREBASE: $e ---");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))),
      );
    }
    return const AuthGate();
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Пока Firebase проверяет токен (работает под капотом)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))),
          );
        }

        // Если пользователь авторизован — идем в ОБЕРТКУ (HomeWrapper)
        if (snapshot.hasData) {
          return const HomeWrapper(); 
        }

        // Если не авторизован — показываем экран входа
        return const AuthScreen();
      },
    );
  }
}