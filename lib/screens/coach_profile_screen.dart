import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/database_service.dart'; 
import '../widgets/base_background.dart'; 
import 'p2p_chat_screen.dart';

class CoachProfileScreen extends StatelessWidget {
  final Map<String, dynamic> coachData;

  const CoachProfileScreen({super.key, required this.coachData});

  @override
  Widget build(BuildContext context) {
    final String id = coachData['id'] ?? '';
    final String name = coachData['name']?.toString().trim() ?? 'role_coach'.tr();
    final String photoUrl = coachData['photoUrl'] ?? '';
    final String specialization = coachData['specialization']?.toString().trim() ?? 'no_specialization'.tr();
    final String bio = coachData['bio']?.toString().trim() ?? 'coach_no_bio'.tr();
    final String price = coachData['price']?.toString() ?? 'price_negotiable'.tr();
    final double rating = (coachData['rating'] ?? 5.0).toDouble();

    ImageProvider? bgImage;
    if (photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('http')) {
        bgImage = NetworkImage(photoUrl);
      } else {
        try { bgImage = MemoryImage(base64Decode(photoUrl)); } catch (_) {}
      }
    }

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('profile'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  image: bgImage != null 
                      ? DecorationImage(image: bgImage, fit: BoxFit.cover)
                      : null,
                ),
                child: bgImage == null ? const Icon(Icons.person, color: Colors.grey, size: 100) : null,
              ),
              
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Color(0xFF9CD600), size: 24),
                            const SizedBox(width: 4),
                            Text(rating.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(specialization.toUpperCase(), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    
                    const SizedBox(height: 24),
                    Text('about_coach'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 8),
                    Text(bio, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
                    
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('price_label'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 14)),
                        Text(price, style: const TextStyle(color: Color(0xFF9CD600), fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    
                    const SizedBox(height: 40),
                    
                    Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: const Color(0xFF9CD600).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: id, otherUserName: name)));
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CD600), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: Text('write_message'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () async {
                          await DatabaseService().connectWithCoach(id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('request_sent'.tr(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFF9CD600), behavior: SnackBarBehavior.floating));
                          }
                        },
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF9CD600), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: Text('start_work'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}