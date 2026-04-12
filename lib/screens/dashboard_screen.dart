import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart';
import 'harmony_screen.dart';
import 'home_tab.dart'; 
import 'community_screen.dart'; // <-- ДОБАВИЛИ ИМПОРТ НОВОГО ФАЙЛА
import '../widgets/dashboard/fast_food_scanner_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  static const Color _bgColor = Color(0xFFF9F9F9);
  static const Color _accentColor = Color(0xFFB76E79);

  final List<Widget> _screens = [
    const HomeTab(),
    const HarmonyScreen(),
    const SizedBox.shrink(),
    const CommunityScreen(), // Теперь он берется из отдельного файла
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _checkAndMigrateOldUsers();
      }
    });
  }

  Future<void> _checkAndMigrateOldUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;

      if (data['goal'] == null || data['activityLevel'] == null || data['goal'].toString().isEmpty) {
        if (mounted) {
          _showMigrationBottomSheet(context, uid);
        }
      }
    } catch (e) {
      debugPrint("Ошибка миграции: $e");
    }
  }

  void _showMigrationBottomSheet(BuildContext context, String uid) {
    String selectedGoal = 'Похудеть';
    String selectedActivity = 'Умеренная (1-2 тренировки)';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 32, bottom: MediaQuery.of(ctx).viewInsets.bottom + 40),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Важное обновление ✨", style: TextStyle(color: Color(0xFF2D2D2D), fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text("MyEva стала умнее! Уточни пару деталей для точного расчета нормы калорий:", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
                const SizedBox(height: 24),
                const Text("Ваша главная цель", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedGoal,
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                  items: ['Похудеть', 'Поддержать вес', 'Набрать массу'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setModalState(() => selectedGoal = v!),
                ),
                const SizedBox(height: 16),
                const Text("Уровень активности", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedActivity,
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                  items: [
                    'Низкая (сидячий образ)',
                    'Умеренная (1-2 тренировки)',
                    'Высокая (3-5 тренировок)',
                    'Очень высокая (каждый день)',
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (v) => setModalState(() => selectedActivity = v!),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('users').doc(uid).update({
                        'goal': selectedGoal,
                        'activityLevel': selectedActivity,
                      });
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

 @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bgColor,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      floatingActionButton: (_currentIndex != 2)
          ? SizedBox(
              height: 64,
              width: 64,
              child: FloatingActionButton(
                heroTag: 'main_add_photo',
                onPressed: () => FastFoodScannerSheet.show(context), 
                backgroundColor: _accentColor, 
                elevation: 6,
                shape: const CircleBorder(),
                child: const Icon(Icons.add_a_photo, size: 28, color: Colors.white), 
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 16,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, 'assets/icons/home.png', 'Главная', iconSize: 27),
              _buildNavItem(1, 'assets/icons/harmony.png', 'Гармония', iconSize: 34),
              const SizedBox(width: 48),
              _buildNavItem(3, 'assets/icons/chats.png', 'Комьюнити', uid: uid, iconSize: 34),
              _buildNavItem(4, 'assets/icons/profile.png', 'Профиль', iconSize: 26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String iconPath, String label, {String? uid, double iconSize = 26}) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? _accentColor : const Color(0xFF8E8E93);

    final Widget baseIcon = SizedBox(
      width: 36, height: 36,
      child: Center(child: Image.asset(iconPath, width: iconSize, height: iconSize, color: color)),
    );

    Widget finalIcon = baseIcon;

    if (index == 3 && uid != null) {
      finalIcon = StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('chats').where('users', arrayContains: uid).snapshots(),
        builder: (context, snapshot) {
          int totalUnread = 0;
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              totalUnread += ((doc.data() as Map<String, dynamic>)['unread_$uid'] as num?)?.toInt() ?? 0;
            }
          }
          return Badge(isLabelVisible: totalUnread > 0, label: Text(totalUnread.toString()), backgroundColor: _accentColor, child: baseIcon);
        },
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            finalIcon,
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, height: 1.0)),
          ],
        ),
      ),
    );
  }
}