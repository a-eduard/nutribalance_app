import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_screen.dart'; 
import 'dashboard_screen.dart'; 
import 'coach_dashboard_screen.dart';
import '../paywall_screen.dart'; // Импорт Пейвола
import '../services/push_notification_service.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

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
  bool _isLoading = true;
  String _activeRole = 'athlete'; 
  String _registeredRole = 'athlete';
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _activeRole = data['activeRole'] ?? 'athlete';
        _registeredRole = data['registeredRole'] ?? 'athlete';
        _isPro = data['isPro'] == true;
      }

      PushNotificationService().initialize();
      PushNotificationService().forceUpdateToken();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("КРИТИЧЕСКАЯ ОШИБКА СТАРТА: $e");
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))),
      );
    }

    // --- ЛОГИКА ПЕЙВОЛА ---
    // Если пользователь регался как Тренер, но не оплатил подписку 
    // -> Запираем его на экране PaywallScreen (он не попадет ни в клиента, ни в тренера)
    if (_registeredRole == 'coach' && !_isPro) {
      return const PaywallScreen();
    }

    // Если всё оплачено (или это бесплатный Клиент) -> пускаем дальше по активной роли
    if (_activeRole == 'coach') {
      return const CoachDashboardScreen();
    }

    return const DashboardScreen();
  }
}