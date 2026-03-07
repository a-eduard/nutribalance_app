import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_screen.dart'; 
import 'dashboard_screen.dart'; 
import '../paywall_screen.dart'; 
import '../services/push_notification_service.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(backgroundColor: Color(0xFF1A1A1C), body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79))));
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
  @override
  void initState() {
    super.initState();
    PushNotificationService().initialize();
    PushNotificationService().forceUpdateToken();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(backgroundColor: Color(0xFF1A1A1C), body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79))));
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) return const Scaffold(backgroundColor: Color(0xFF1A1A1C), body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79))));

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final bool isPro = data['isPro'] == true;

        // Пока отключим пейволл для всех, чтобы не блокировал вход (потом настроишь под себя)
        return const DashboardScreen();
      },
    );
  }
}