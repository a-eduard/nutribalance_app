import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../widgets/base_background.dart';
import 'profile_settings_screen.dart'; 

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Widget _buildAvatar(String? photoUrl) {
    Widget avatarWidget = const Icon(Icons.person, size: 50, color: Colors.grey);

    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('http')) {
        avatarWidget = CachedNetworkImage(
          imageUrl: photoUrl,
          width: 100, height: 100, fit: BoxFit.cover,
          placeholder: (context, url) => const CircularProgressIndicator(color: Color(0xFF9CD600)),
          errorWidget: (context, url, error) => const Icon(Icons.person, size: 50, color: Colors.grey),
        );
      } else {
        try {
          avatarWidget = Image.memory(base64Decode(photoUrl), width: 100, height: 100, fit: BoxFit.cover);
        } catch (_) {}
      }
    }

    return Container(
      width: 110, height: 110,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF9CD600), width: 2)),
      child: ClipOval(child: avatarWidget),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5), 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: Colors.white12)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("$label: ", style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: Text("auth_error".tr(), style: const TextStyle(color: Colors.white))));

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          title: const Text('Профиль', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent, 
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
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
            final String photoUrl = data['photoUrl'] ?? '';
            
            final String age = data['age']?.toString() ?? '—';
            final String height = data['height']?.toString() ?? '—';
            final String weight = data['weight']?.toString() ?? '—';

            final String nickname = data['nickname']?.toString().trim() ?? '';
            final String displayNickname = nickname.isNotEmpty ? '@$nickname' : '@new_athlete';
            
            final String registeredRole = data['registeredRole']?.toString() ?? 'athlete';
            final bool canSwitchToCoach = registeredRole == 'coach';

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 50), 
                      
                      _buildAvatar(photoUrl),
                      const SizedBox(height: 24),
                      
                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(displayNickname, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                      
                      const SizedBox(height: 40),

                      Wrap(
                        spacing: 12.0, 
                        runSpacing: 12.0, 
                        alignment: WrapAlignment.center,
                        children: [
                          _buildInfoChip('age'.tr(), age),
                          _buildInfoChip('height'.tr(), "$height см"),
                          _buildInfoChip('weight'.tr(), "$weight кг"),
                        ],
                      ),
                      
                      // БЛОК 5: Кнопка возврата стала меньше и аккуратнее (Outlined)
                      if (canSwitchToCoach) ...[
                        const SizedBox(height: 40),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.swap_horiz, color: Color(0xFF9CD600)),
                          label: const Text('В РЕЖИМ ТРЕНЕРА', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            side: const BorderSide(color: Color(0xFF9CD600), width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () async {
                            await FirebaseFirestore.instance.collection('users').doc(uid).set(
                              {'activeRole': 'coach'}, 
                              SetOptions(merge: true)
                            );
                            if (context.mounted) {
                              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                            }
                          },
                        ),
                      ],
                      
                      const SizedBox(height: 40), 
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}