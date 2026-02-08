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
import 'screens/onboarding_screen.dart'; // Только этот в папке screens

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('ru', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tonna Gym Tracker',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        primaryColor: const Color(0xFFCCFF00),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFCCFF00),
          secondary: Color(0xFFCCFF00),
          surface: Color(0xFF1C1C1E),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto', 
      ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Color(0xFF000000), body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
        }
        if (!snapshot.hasData) return const AuthScreen();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(backgroundColor: Color(0xFF000000), body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
            }
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              if (userData != null && userData.containsKey('name') && (userData['name'] as String).isNotEmpty) {
                return const DashboardScreen();
              }
            }
            return const OnboardingScreen();
          },
        );
      },
    );
  }
}