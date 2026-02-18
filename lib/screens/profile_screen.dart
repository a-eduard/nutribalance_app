import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import '../widgets/base_background.dart'; // ИМПОРТ ФОНА
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _buildAvatar(String? photoUrl) {
    ImageProvider? imageProvider;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('http')) {
        // Это URL из Storage
        imageProvider = NetworkImage(photoUrl);
      } else {
        // Это старая Base64 строка (обратная совместимость)
        try {
          imageProvider = MemoryImage(base64Decode(photoUrl));
        } catch (e) {
          // Если битая строка
          imageProvider = null;
        }
      }
    }

    return Container(
      width: 100, height: 100,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9CD600), width: 2)),
      child: ClipOval(
        child: imageProvider != null
            ? Image(image: imageProvider, width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 50, color: Colors.grey))
            : const Icon(Icons.person, size: 50, color: Colors.grey),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: Text("auth_error".tr(), style: const TextStyle(color: Colors.white))));

    // ОБЕРТКА В ФОН
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, // ПРОЗРАЧНЫЙ ФОН
        appBar: AppBar(
          title: Text('profile'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent, // ПРОЗРАЧНЫЙ APPBAR
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
            if (!snapshot.hasData || !snapshot.data!.exists) return Center(child: Text('profile_not_found'.tr(), style: const TextStyle(color: Colors.grey)));

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final String name = data['name']?.toString().trim() ?? 'client'.tr();
            final String bio = data['bio']?.toString().trim() ?? 'bio_empty'.tr();
            final String base64Image = data['photoUrl'] ?? '';
            
            final String age = data['age']?.toString() ?? '—';
            final String height = data['height']?.toString() ?? '—';
            final String weight = data['weight']?.toString() ?? '—';

            double totalVolumeKg = (data['totalVolumeKg'] ?? 0.0).toDouble(); 
            double totalTons = totalVolumeKg / 1000;
            
            int currentLevel = 0;
            double tonsToNext = 100.0;
            
            if (totalTons < 100) { currentLevel = 0; tonsToNext = 100 - totalTons; } 
            else if (totalTons < 250) { currentLevel = 1; tonsToNext = 250 - totalTons; } 
            else if (totalTons < 450) { currentLevel = 2; tonsToNext = 450 - totalTons; } 
            else if (totalTons < 700) { currentLevel = 3; tonsToNext = 700 - totalTons; } 
            else if (totalTons < 1000) { currentLevel = 4; tonsToNext = 1000 - totalTons; } 
            else { currentLevel = 5; tonsToNext = 0; }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAvatar(base64Image),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(bio, style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildInfoChip('age'.tr(), age),
                      const SizedBox(width: 8),
                      _buildInfoChip('height'.tr(), "$height см"),
                      const SizedBox(width: 8),
                      _buildInfoChip('weight'.tr(), "$weight кг"),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('total_volume'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text("${totalTons.toStringAsFixed(1)} т", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, color: Colors.white12),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              String message = currentLevel == 5 ? 'max_level'.tr() : 'to_next_level'.tr().replaceAll('{}', tonsToNext.toStringAsFixed(1));
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFCCFF00), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              children: [
                                const Icon(Icons.local_fire_department, color: Color(0xFFCCFF00), size: 28),
                                const SizedBox(height: 4),
                                Text("${'rating'.tr()}: $currentLevel", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}