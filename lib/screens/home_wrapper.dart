import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_screen.dart'; 
import 'dashboard_screen.dart'; 
import '../services/push_notification_service.dart';
import '../services/local_notification_service.dart';
import '../services/database_service.dart'; 
import 'onboarding_screen.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor, 
            body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
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
  bool? _isAppInReview; 

  // Асинхронно спрашиваем у базы, находимся ли мы на модерации
  Future<void> _checkReviewStatus() async {
    try {
      bool inReview = await DatabaseService().isAppInReview();
      if (mounted) {
        setState(() {
          _isAppInReview = inReview;
        });
      }
    } catch (e) {
      debugPrint('Ошибка при проверке AppInReview: $e');
      if (mounted) {
        setState(() {
          _isAppInReview = false; // Безопасный фолбэк при сбое сети
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    PushNotificationService().initialize();
    PushNotificationService().forceUpdateToken();
    _checkReviewStatus(); 
    
    LocalNotificationService().requestPermissions(); 
    LocalNotificationService().syncNotificationsOnStartup();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Ждем долю секунды, пока загрузится статус рубильника
    if (_isAppInReview == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor, 
            body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor, 
            body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          );
        }

        // Защита от вечной загрузки: отправляем на онбординг, если документа нет
        if (!snapshot.data!.exists) {
          return const OnboardingScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        
        final bool isOnboardingCompleted = data['isOnboardingCompleted'] ?? true;

        if (isOnboardingCompleted == false) {
          return const OnboardingScreen(); 
        }

        return const DashboardScreen();
      },
    );
  }
}