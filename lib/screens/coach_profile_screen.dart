import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import '../services/chat_service.dart';
import '../widgets/base_background.dart';
import 'p2p_chat_screen.dart';

class CoachProfileScreen extends StatefulWidget {
  final Map<String, dynamic> coachData;

  const CoachProfileScreen({super.key, required this.coachData});

  @override
  State<CoachProfileScreen> createState() => _CoachProfileScreenState();
}

class _CoachProfileScreenState extends State<CoachProfileScreen> {
  int _selectedRating = 0;
  bool _hasRatedCoach = false;
  bool _isLoadingRating = true;
  bool _isSubmittingRating = false;

  @override
  void initState() {
    super.initState();
    _checkIfRated();
  }

  Future<void> _checkIfRated() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final String coachId = widget.coachData['id'] ?? '';
    
    if (currentUserId == null || coachId.isEmpty || currentUserId == coachId) {
      if (mounted) setState(() => _isLoadingRating = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(currentUserId)
          .collection('rated_coaches').doc(coachId)
          .get();
          
      if (doc.exists && mounted) {
        setState(() {
          _hasRatedCoach = true;
          _selectedRating = doc.data()?['rating'] ?? 5;
        });
      }
    } catch (e) {
      debugPrint("Ошибка проверки рейтинга: $e");
    } finally {
      if (mounted) setState(() => _isLoadingRating = false);
    }
  }

  Future<void> _showConfirmRatingDialog(String coachId) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Подтверждение', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Вы уверены что хотите поставить $_selectedRating звезды?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Отмена', style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9CD600),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitRating(coachId);
            },
            child: const Text('Да', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRating(String coachId) async {
    if (_selectedRating == 0) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _isSubmittingRating = true);
    try {
      // 1. Отправляем оценку тренеру
      await DatabaseService().rateCoach(coachId, _selectedRating.toDouble());
      
      // 2. Записываем клиенту, что он уже оценил этого тренера
      await FirebaseFirestore.instance
          .collection('users').doc(currentUserId)
          .collection('rated_coaches').doc(coachId)
          .set({
            'rated': true,
            'rating': _selectedRating,
            'timestamp': FieldValue.serverTimestamp(),
          });
          
      if (mounted) {
        setState(() => _hasRatedCoach = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Спасибо за оценку!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
            backgroundColor: Color(0xFF9CD600)
          )
        );
      }
    } catch (e) {
      debugPrint("Ошибка сохранения рейтинга: $e");
    } finally {
      if (mounted) setState(() => _isSubmittingRating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final String id = widget.coachData['id'] ?? currentUserId ?? '';
    
    final String name = widget.coachData['name']?.toString().trim() ?? 'role_coach'.tr();
    final String photoUrl = widget.coachData['photoUrl'] ?? '';
    final String specialization = widget.coachData['specialization']?.toString().trim() ?? 'no_specialization'.tr();
    final String bio = widget.coachData['bio']?.toString().trim() ?? 'coach_no_bio'.tr();
    final String price = widget.coachData['price']?.toString() ?? 'price_negotiable'.tr();

    final double rating = (widget.coachData['rating'] ?? 5.0).toDouble();
    final int totalVotes = (widget.coachData['totalVotes'] ?? 0).toInt();

    ImageProvider? bgImage;
    if (photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('http')) {
        bgImage = NetworkImage(photoUrl);
      } else {
        try {
          bgImage = MemoryImage(base64Decode(photoUrl));
        } catch (_) {}
      }
    }

    final bool isOwnProfile = (currentUserId == id);

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('profile'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (isOwnProfile)
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity, height: 300,
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E), image: bgImage != null ? DecorationImage(image: bgImage, fit: BoxFit.cover) : null),
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
                        if (totalVotes > 0)
                          Row(
                            children: [
                              const Icon(Icons.star, color: Color(0xFF9CD600), size: 24),
                              const SizedBox(width: 4),
                              Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          )
                        else
                          const Text("Нет оценок", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
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

                    if (isOwnProfile) ...[
                      SizedBox(
                        width: double.infinity, height: 56,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.swap_horiz, color: Colors.black),
                          label: const Text('В режим клиента', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CD600), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: () async {
                            await FirebaseFirestore.instance.collection('users').doc(currentUserId).set({'activeRole': 'athlete'}, SetOptions(merge: true));
                            if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                          },
                        ),
                      ),
                    ] else if (currentUserId != null) ...[
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
                        builder: (context, snapshot) {
                          bool isMyCoach = false;
                          bool isPending = false;

                          if (snapshot.hasData && snapshot.data!.exists) {
                            final userData = snapshot.data!.data() as Map<String, dynamic>;
                            isMyCoach = userData['currentCoachId'] == id && userData['coachRequestStatus'] == 'accepted';
                            isPending = userData['currentCoachId'] == id && userData['coachRequestStatus'] == 'pending';
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () async {
                                        await ChatService().getOrCreateChat(id);
                                        if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: id, otherUserName: name)));
                                      },
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF9CD600), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                                      child: Text('chat_btn'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 16)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: isMyCoach
                                        ? OutlinedButton(
                                            onPressed: () async {
                                              await FirebaseFirestore.instance.collection('users').doc(currentUserId).update({'currentCoachId': FieldValue.delete(), 'coachRequestStatus': FieldValue.delete()});
                                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сотрудничество завершено')));
                                            },
                                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                                            child: Text('end_coaching'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                                          )
                                        : ElevatedButton(
                                            onPressed: isPending ? null : () async {
                                              await DatabaseService().sendRequestToCoach(id);
                                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заявка отправлена тренеру!', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Color(0xFF9CD600)));
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: isPending ? Colors.grey : const Color(0xFF9CD600), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                                            child: Text(isPending ? 'Ожидает' : 'Подать заявку', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                          ),
                                  ),
                                ],
                              ),

                              if (isMyCoach) ...[
                                const SizedBox(height: 32),
                                const Divider(color: Colors.white10, height: 1),
                                const SizedBox(height: 24),
                                
                                // ЗАДАЧА 6: Обновленный блок оценки с кнопкой и диалогом
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                                  child: _isLoadingRating 
                                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)))
                                    : Column(
                                        children: [
                                          const Text("ОЦЕНИТЕ РАБОТУ ТРЕНЕРА", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                          const SizedBox(height: 8),
                                          Text(
                                            _hasRatedCoach ? "Ваша оценка сохранена" : "Поделитесь своим мнением", 
                                            style: TextStyle(color: _hasRatedCoach ? const Color(0xFF9CD600) : Colors.white70, fontSize: 12)
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: List.generate(5, (index) => IconButton(
                                              icon: Icon(
                                                index < _selectedRating ? Icons.star_rounded : Icons.star_outline_rounded, 
                                                color: index < _selectedRating ? const Color(0xFF9CD600).withOpacity(_hasRatedCoach ? 1.0 : 0.6) : Colors.white24, 
                                                size: 36
                                              ),
                                              onPressed: _hasRatedCoach ? null : () {
                                                setState(() => _selectedRating = index + 1);
                                              },
                                            )),
                                          ),
                                          if (!_hasRatedCoach) ...[
                                            const SizedBox(height: 16),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: (_selectedRating > 0 && !_isSubmittingRating) ? () => _showConfirmRatingDialog(id) : null,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF9CD600),
                                                  disabledBackgroundColor: Colors.white10,
                                                  foregroundColor: Colors.black,
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                                                ),
                                                child: _isSubmittingRating 
                                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                                    : const Text('ОЦЕНИТЬ ТРЕНЕРА', style: TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ]
                                        ],
                                      ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}