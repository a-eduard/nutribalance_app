import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Правильные пути на уровень выше
import '../dashboard_screen.dart'; 
import '../auth_screen.dart'; 

// Путь в текущей папке
import 'coach_dashboard_screen.dart'; 

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const AuthScreen();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black, 
            body: Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
          );
        }
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final activeRole = data['activeRole'] ?? 'user';
          
          if (activeRole == 'coach') {
            return const CoachDashboardScreen();
          }
        }
        return const DashboardScreen();
      },
    );
  }
}