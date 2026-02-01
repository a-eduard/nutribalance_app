import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'firebase_options.dart'; // <--- 1. ВАЖНЫЙ ИМПОРТ

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. ВАЖНОЕ ИСПРАВЛЕНИЕ: Передаем options
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, 
  );

  runApp(const FitnessApp());
}

class FitnessApp extends StatelessWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iron Tracker',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'),
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: const Color(0xFFCCFF00),
        textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F0F0F),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFCCFF00)),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F0F0F),
            body: Center(
              child: Text("Ошибка подключения к базе данных", style: TextStyle(color: Colors.red)),
            ),
          );
        }

        if (snapshot.hasData) {
          return const DashboardScreen();
        }

        return const AuthScreen();
      },
    );
  }
}