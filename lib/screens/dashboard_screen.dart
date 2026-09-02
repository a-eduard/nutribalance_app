import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart';
import 'harmony_screen.dart';
import 'home_tab.dart'; 
import 'community_screen.dart'; 
import '../widgets/dashboard/fast_food_scanner_sheet.dart';

class DashboardScreen extends StatefulWidget {
  final int initialTab; 

  const DashboardScreen({super.key, this.initialTab = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _currentIndex;

  final List<Widget> _screens = [
    const HomeTab(),
    const HarmonyScreen(),
    const SizedBox.shrink(), 
    const CommunityScreen(), 
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _checkAndMigrateOldUsers();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() {
        _currentIndex = widget.initialTab;
      });
    }
  }

  Future<void> _checkAndMigrateOldUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      if (data['goal'] == null || data['activityLevel'] == null || data['goal'].toString().isEmpty) {
        if (mounted) _showMigrationBottomSheet(context, uid);
      }
    } catch (e) {
      debugPrint("Ошибка миграции: $e");
    }
  }

  void _showMigrationBottomSheet(BuildContext context, String uid) {
    String selectedGoal = 'Похудеть';
    String selectedActivity = 'Умеренная (1-2 тренировки)';
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context, isScrollControlled: true, isDismissible: false, enableDrag: false,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 32, bottom: MediaQuery.of(ctx).viewInsets.bottom + 40),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Важное обновление ✨", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text("MyEva стала умнее! Уточни пару деталей для точного расчета нормы калорий:", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: 24),
                Text("Ваша главная цель", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ИСПРАВЛЕНО: value -> initialValue
                  initialValue: selectedGoal,
                  dropdownColor: theme.colorScheme.surface,
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                  items: ['Похудеть', 'Поддержать вес', 'Набрать массу'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setModalState(() => selectedGoal = v!),
                ),
                const SizedBox(height: 16),
                Text("Уровень активности", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ИСПРАВЛЕНО: value -> initialValue
                  initialValue: selectedActivity,
                  dropdownColor: theme.colorScheme.surface,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
                  items: ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setModalState(() => selectedActivity = v!),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('users').doc(uid).update({'goal': selectedGoal, 'activityLevel': selectedActivity});
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800)),
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: IndexedStack(index: _currentIndex, children: _screens),
      floatingActionButton: (_currentIndex != 2)
          ? SizedBox(
              height: 64, width: 64,
              child: FloatingActionButton(
                heroTag: 'main_add_photo', onPressed: () => FastFoodScannerSheet.show(context), 
                backgroundColor: theme.colorScheme.primary, elevation: 6, shape: const CircleBorder(),
                child: Icon(Icons.add_a_photo, size: 28, color: theme.colorScheme.onPrimary), 
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: theme.bottomNavigationBarTheme.backgroundColor, 
        shape: const CircularNotchedRectangle(), notchMargin: 8, elevation: 16,
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
    final theme = Theme.of(context);
    final color = isSelected ? theme.bottomNavigationBarTheme.selectedItemColor! : theme.bottomNavigationBarTheme.unselectedItemColor!;

    final Widget baseIcon = SizedBox(width: 36, height: 36, child: Center(child: Image.asset(iconPath, width: iconSize, height: iconSize, color: color)));
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
          return Badge(isLabelVisible: totalUnread > 0, label: Text(totalUnread.toString()), backgroundColor: theme.colorScheme.primary, child: baseIcon);
        },
      );
    }

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65,
        child: Column(
          mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end,
          children: [
            finalIcon, const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, height: 1.0)),
          ],
        ),
      ),
    );
  }
}