import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_screen.dart'; 
import 'dashboard_screen.dart'; 
import '../paywall_screen.dart'; 
import '../services/push_notification_service.dart';
import '../services/local_notification_service.dart';
import '../services/database_service.dart'; // <-- 1. ИМПОРТИРУЕМ СЕРВИС
import 'onboarding_screen.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A1C), 
            body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)))
          );
        }
        if (!snapshot.hasData || snapshot.data == null) return const AuthScreen();
        return FirestoreRoleLoader(user: snapshot.data!);
      },
    );
  }
}

class FirestoreRoleLoader extends StatefulWidget {
  final User user;
  const FirestoreRoleLoader({super.key, required this.user});

  @override
  State<FirestoreRoleLoader> createState() => _FirestoreRoleLoaderState();
}

class _FirestoreRoleLoaderState extends State<FirestoreRoleLoader> {
  bool? _isAppInReview; // <-- 2. ПЕРЕМЕННАЯ ДЛЯ СТАТУСА РУБИЛЬНИКА

  // Асинхронно спрашиваем у базы, находимся ли мы на модерации
  Future<void> _checkReviewStatus() async {
    final status = await DatabaseService().isAppInReview();
    if (mounted) {
      setState(() => _isAppInReview = status);
    }
  }

  @override
  void initState() {
    super.initState();
    PushNotificationService().initialize();
    PushNotificationService().forceUpdateToken();
    _checkReviewStatus(); 
    
    LocalNotificationService().requestPermissions(); 
    LocalNotificationService().scheduleDailyNotifications();
  }

  @override
  Widget build(BuildContext context) {
    // Ждем долю секунды, пока загрузится статус рубильника
    if (_isAppInReview == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A1C),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)))
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A1C), 
            body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)))
          );
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A1A1C), 
            body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)))
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final bool isPro = data['isPro'] == true;
        
        // === НОВАЯ ЛОГИКА: ПРОВЕРКА ОНБОРДИНГА ===
        // Если флага нет (старый юзер), по умолчанию считаем true (пускаем дальше).
        // Если флаг false (новый юзер после регистрации) — кидаем на онбординг.
        final bool isOnboardingCompleted = data['isOnboardingCompleted'] ?? true;

        if (isOnboardingCompleted == false) {
          return const OnboardingScreen(); // Отправляем новичков заполнять профиль
        }

        // === СТАРАЯ ЛОГИКА: ПЕЙВОЛ ИЛИ ДАШБОРД ===
        // Если премиума нет И мы НЕ на проверке в сторе -> показываем пейвол
        if (!isPro && _isAppInReview == false) {
          return const PaywallScreen();
        }

        // В противном случае (если есть премиум, включен рубильник или пройден онбординг) -> пускаем внутрь
        return const DashboardScreen();
      },
    );
  }
}