import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../widgets/base_background.dart';
import 'profile_settings_screen.dart'; 
import '../services/database_service.dart';

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
          title: const Text('Профиль', style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
          backgroundColor: Colors.transparent, 
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF2D2D2D), size: 28), 
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()))
            ),
            const SizedBox(width: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16), 
                    
                    // ПРЕМИАЛЬНЫЙ АВАТАР
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFB76E79).withValues(alpha: 0.2), blurRadius: 24, offset: const Offset(0, 8))
                        ],
                        color: const Color(0xFFF2F2F7),
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty 
                          ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, errorWidget: (c, u, e) => const Icon(Icons.person, color: Color(0xFFC7C7CC), size: 60))
                          : const Icon(Icons.person, color: Color(0xFFC7C7CC), size: 60),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    Text(name, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    
                    if (displayNickname.isNotEmpty) 
                      Padding(
                        padding: const EdgeInsets.only(top: 6), 
                        child: Text(displayNickname, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontWeight: FontWeight.w600))
                      ),
                      
                    const SizedBox(height: 40),
                    
                    // КАРТОЧКА ВЕСА
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
                        ]
                      ),
                      child: Column(
                        children: [
                          const Text("ТЕКУЩИЙ ВЕС", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Text("$weight кг", style: const TextStyle(color: Color(0xFFB76E79), fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // КАРТОЧКА ЖЕНСКОГО ЗДОРОВЬЯ (ТРЕКЕР ЦИКЛА)
                    const CycleTrackerWidget(),

                    const SizedBox(height: 40),
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

// === ПРЕМИАЛЬНЫЙ ТРЕКЕР ЦИКЛА ===
class CycleTrackerWidget extends StatelessWidget {
  const CycleTrackerWidget({super.key});

  Future<void> _selectPeriodDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFB76E79), 
              onPrimary: Colors.white,
              onSurface: Color(0xFF2D2D2D),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      await DatabaseService().updatePeriodStartDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final Timestamp? lastPeriod = userData['lastPeriodStartDate'] as Timestamp?;
        final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

        String dayText = "Цикл не отслеживается";
        String phaseText = "Нажмите, чтобы отметить начало цикла";
        double progress = 0.0;

        if (lastPeriod != null) {
          final start = DateTime(lastPeriod.toDate().year, lastPeriod.toDate().month, lastPeriod.toDate().day);
          final now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          final diff = now.difference(start).inDays;

          if (diff >= 0) {
            final int dayOfCycle = (diff % cycleLength) + 1;
            dayText = "$dayOfCycle-й день цикла";
            progress = (dayOfCycle / cycleLength).clamp(0.0, 1.0);

            if (dayOfCycle <= 5) phaseText = 'Менструация 🩸';
            else if (dayOfCycle <= 13) phaseText = 'Фолликулярная фаза 🌸';
            else if (dayOfCycle <= 15) phaseText = 'Овуляция ✨';
            else phaseText = 'Лютеиновая фаза (ПМС) 🌿';
          }
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ЖЕНСКОЕ ЗДОРОВЬЕ', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                  GestureDetector(
                    onTap: () => _selectPeriodDate(context),
                    child: const Icon(Icons.calendar_today, color: Color(0xFFC7C7CC), size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.spa, color: Color(0xFFB76E79), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dayText, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(phaseText, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFFF2F2F7),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD49A89)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _selectPeriodDate(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFFB76E79).withValues(alpha: 0.3), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    backgroundColor: Colors.transparent,
                  ),
                  child: const Text('Отметить начало цикла', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              )
            ],
          ),
        );
      }
    );
  }
}