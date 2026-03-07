import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/base_background.dart';
import 'profile_settings_screen.dart'; 

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: Color(0xFFF9F9F9));

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          title: const Text('Профиль', style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent, 
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Color(0xFF2D2D2D)), 
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()))
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)));

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final String name = data['name']?.toString().trim() ?? 'Пользователь';
            final String photoUrl = data['photoUrl'] ?? '';
            final String weight = data['weight']?.toString() ?? '—';
            final String nickname = data['nickname']?.toString().trim() ?? '';
            final String displayNickname = nickname.isNotEmpty ? '@$nickname' : '';

            return SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40), 
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        border: Border.all(color: const Color(0xFFB76E79), width: 3),
                        color: const Color(0xFFF0F0F0), // Светлый фон, если нет фото
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty 
                          ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, errorWidget: (c, u, e) => const Icon(Icons.person, color: Colors.grey, size: 60))
                          : const Icon(Icons.person, color: Colors.grey, size: 60),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Темный текст для имени
                    Text(name, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 26, fontWeight: FontWeight.bold)),
                    
                    if (displayNickname.isNotEmpty) 
                      Padding(
                        padding: const EdgeInsets.only(top: 4), 
                        child: Text(displayNickname, style: const TextStyle(color: Colors.grey, fontSize: 16))
                      ),
                      
                    const SizedBox(height: 32),
                    
                    // Светлая карточка веса с тенью
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))
                        ]
                      ),
                      child: Column(
                        children: [
                          const Text("Текущий вес", style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Text("$weight кг", style: const TextStyle(color: Color(0xFFB76E79), fontSize: 28, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}