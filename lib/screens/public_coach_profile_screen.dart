import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart'; 
import 'package:cached_network_image/cached_network_image.dart';

import '../models/coach.dart';
import '../services/database_service.dart';

class PublicCoachProfileScreen extends StatefulWidget {
  final Coach coach;

  const PublicCoachProfileScreen({super.key, required this.coach});

  @override
  State<PublicCoachProfileScreen> createState() => _PublicCoachProfileScreenState();
}

class _PublicCoachProfileScreenState extends State<PublicCoachProfileScreen> {

  void _showRatingDialog(BuildContext context) {
    int selectedStars = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('rate_coach_title'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('rate_coach_desc'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < selectedStars ? Icons.star : Icons.star_border,
                          color: const Color(0xFFCCFF00),
                          size: 36,
                        ),
                        onPressed: () {
                          setStateDialog(() => selectedStars = index + 1);
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('cancel'.tr(), style: const TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedStars == 0) return;
                    Navigator.pop(ctx);
                    await _submitRating(selectedStars);
                  },
                  child: Text('send'.tr(), style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitRating(int selectedStars) async {
    final coachRef = FirebaseFirestore.instance.collection('coaches').doc(widget.coach.id);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(coachRef);
        if (!snapshot.exists) return;

        double currentRating = (snapshot.data()?['rating'] ?? 5.0).toDouble();
        int count = snapshot.data()?['ratingCount'] ?? 0;

        double newRating = ((currentRating * count) + selectedStars) / (count + 1);

        transaction.update(coachRef, {
          'rating': newRating,
          'ratingCount': count + 1,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('rating_thanks'.tr(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFFCCFF00),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${'error_msg'.tr()}: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Подготовка картинки для шапки (умеет читать и ссылки из Storage, и старый Base64)
    ImageProvider? headerImageProvider;
    if (widget.coach.photoUrl.isNotEmpty) {
      if (widget.coach.photoUrl.startsWith('http')) {
        headerImageProvider = CachedNetworkImageProvider(widget.coach.photoUrl);
      } else {
        try { headerImageProvider = MemoryImage(base64Decode(widget.coach.photoUrl)); } catch (_) {}
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
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
              height: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                image: headerImageProvider != null
                    ? DecorationImage(
                        image: headerImageProvider,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: headerImageProvider == null
                  ? const Icon(Icons.person, size: 100, color: Colors.grey)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.coach.name,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.coach.specialization.toUpperCase(),
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Color(0xFFCCFF00), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        widget.coach.rating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "(${widget.coach.ratingCount} ${'ratings_count'.tr()})",
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('about_me'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  Text(
                    widget.coach.bio.isEmpty ? 'coach_no_bio'.tr() : widget.coach.bio,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 32),
                  Text('price'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Text(
                    widget.coach.price,
                    style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        await DatabaseService().connectWithCoach(widget.coach.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('request_sent'.tr(), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              backgroundColor: const Color(0xFFCCFF00),
                              behavior: SnackBarBehavior.floating,
                            )
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCCFF00),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('start_work'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => _showRatingDialog(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1C1C1E), width: 2),
                        backgroundColor: const Color(0xFF1C1C1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('rate_coach'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}