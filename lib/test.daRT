import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Для kIsWeb

// Импорты ваших экранов
import 'auth_screen.dart';       
import 'dashboard_screen.dart';   
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация Firebase с настройками для Web
  await Firebase.initializeApp(
    options: kIsWeb
        ? const FirebaseOptions(
            apiKey: "AIzaSyDEQkDTSjNikxsxjMLKCYdJ4BSOTEoCO_4",
            appId: "1:830594518730:web:b1e384f2e830b4323e2e33",
            messagingSenderId: "830594518730",
            projectId: "gym-tracker-9925c",
            storageBucket: "gym-tracker-9925c.firebasestorage.app",
            authDomain: "gym-tracker-9925c.firebaseapp.com"  
          )
        : null, // Для Android и iOS настройки берутся автоматически
  );

  runApp(const MyApp());
}

// ВОТ ЭТОТ КЛАСС БЫЛ ПОТЕРЯН
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gym Tracker',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: const Color(0xFFCCFF00),
        useMaterial3: true,
      ),
      // Стартуем с Обертки Авторизации
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Ждем инициализацию
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Color(0xFF0F0F0F), body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
        }

        // 2. Если НЕ авторизован -> Экран Входа
        if (!snapshot.hasData) {
          return const AuthScreen();
        }

        // 3. Если авторизован -> Проверяем профиль
        final uid = snapshot.data!.uid;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(backgroundColor: Color(0xFF0F0F0F), body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
            }

            // Если анкеты нет -> OnboardingScreen
            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              return const OnboardingScreen();
            }
            
            final userData = userSnapshot.data!.data() as Map<String, dynamic>;
            // Если имя пустое -> OnboardingScreen
            if (userData['name'] == null || (userData['name'] as String).isEmpty) {
              return const OnboardingScreen();
            }

            // Иначе -> ГЛАВНАЯ
            return const DashboardScreen();
          },
        );
      },
    );
  }
}