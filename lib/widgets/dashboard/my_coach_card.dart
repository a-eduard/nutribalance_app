import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../screens/coach_profile_screen.dart'; 
import '../../screens/p2p_chat_screen.dart';     

class MyCoachCard extends StatelessWidget {
  final String coachId;
  final String? requestStatus;

  const MyCoachCard({
    super.key, 
    required this.coachId, 
    this.requestStatus, 
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('coaches').doc(coachId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: CircularProgressIndicator(color: Color(0xFF9CD600)),
            ),
          );
        }
        
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink(); 
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String name = data['name']?.toString().trim() ?? 'coach'.tr();
        final String photoUrl = data['photoUrl'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            // ИЗМЕНЕНИЕ 1: Обводка как у карточки "Питание" и "Прогресс"
            border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3), width: 1.5), 
          ),
          child: InkWell(
            onTap: () {
              final Map<String, dynamic> coachDataToPass = Map.from(data);
              coachDataToPass['id'] = coachId;
              
              Navigator.push(
                context, 
                MaterialPageRoute(
                  builder: (context) => CoachProfileScreen(coachData: coachDataToPass),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ИЗМЕНЕНИЕ 2: Добавлен заголовок "ВАШ ТРЕНЕР"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person, color: Color(0xFF9CD600), size: 18),
                          SizedBox(width: 6),
                          Text('ВАШ ТРЕНЕР', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                        ],
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 12),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center, 
                    children: [
                      // Аватар
                      Container(
                        width: 56, 
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle, 
                          border: Border.all(color: const Color(0xFF9CD600), width: 1.5)
                        ),
                        child: ClipOval(
                          child: photoUrl.isNotEmpty
                              ? (photoUrl.startsWith('http') 
                                  ? CachedNetworkImage(
                                      imageUrl: photoUrl, 
                                      fit: BoxFit.cover, 
                                      placeholder: (context, url) => const CircularProgressIndicator(color: Color(0xFF9CD600)),
                                      errorWidget: (context, url, error) => const Icon(Icons.person, size: 28, color: Colors.grey),
                                    )
                                  : Image.memory(base64Decode(photoUrl), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.person, size: 28, color: Colors.grey)))
                              : const Icon(Icons.person, size: 28, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // Имя и статус
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name.toUpperCase(), 
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), 
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis
                            ),
                            if (requestStatus == 'pending') ...[
                              const SizedBox(height: 4),
                              const Text('В ожидании...', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                            ]
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Иконка чата
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context, 
                          MaterialPageRoute(
                            builder: (_) => P2PChatScreen(otherUserId: coachId, otherUserName: name)
                          )
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Color(0xFF9CD600), 
                            shape: BoxShape.circle, 
                          ), 
                          child: const Icon(Icons.chat_bubble, color: Colors.black, size: 20)
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }
}