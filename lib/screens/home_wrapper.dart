import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Правильные импорты (убедись, что файлы лежат в этой же папке screens)
import 'auth_screen.dart'; 
import 'dashboard_screen.dart'; 
import 'coach_dashboard_screen.dart';
import '../services/push_notification_service.dart';

class HomeWrapper extends StatefulWidget {
  const HomeWrapper({super.key});

  @override
  State<HomeWrapper> createState() => _HomeWrapperState();
}

class _HomeWrapperState extends State<HomeWrapper> {
  bool _notificationsInitialized = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
        }

        final user = authSnapshot.data;

        if (user == null) {
          _notificationsInitialized = false;
          return const AuthScreen();
        }

        // Инициализируем пуши только один раз при входе
        if (!_notificationsInitialized) {
          PushNotificationService().initialize();
          _notificationsInitialized = true;
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));
            }

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final data = userSnapshot.data!.data() as Map<String, dynamic>;
              final String activeRole = data['activeRole'] ?? 'user';

              if (activeRole == 'coach') {
                return const CoachDashboardScreen();
              }
            }

            return const DashboardScreen();
          },
        );
      },
    );
  }
}