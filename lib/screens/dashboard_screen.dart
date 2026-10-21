import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/eva_colors.dart';
import '../widgets/dashboard/fast_food_scanner_sheet.dart';
import '../widgets/eva_ui.dart';
import 'community_screen.dart';
import 'harmony_screen.dart';
import 'home_tab.dart';
import 'profile_screen.dart';

class DashboardScreen extends StatefulWidget {
  final int initialTab;

  const DashboardScreen({super.key, this.initialTab = 0});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _currentIndex;
  final Set<int> _visited = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unreadStream;

  static const _tabs = <_NavItem>[
    _NavItem(Icons.home_outlined, Icons.home_rounded, 'Главная'),
    _NavItem(Icons.spa_outlined, Icons.spa_rounded, 'Гармония'),
    _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Чаты'),
    _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, _tabs.length - 1).toInt();
    _visited.add(_currentIndex);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _unreadStream = FirebaseFirestore.instance.collection('chats').where('users', arrayContains: uid).snapshots();
    }
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _checkAndMigrateOldUsers();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _select(widget.initialTab);
    }
  }

  void _select(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  Future<void> _checkAndMigrateOldUsers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      if (data['goal'] == null || data['activityLevel'] == null || data['goal'].toString().isEmpty) {
        if (mounted) _showMigrationBottomSheet(uid);
      }
    } catch (e) {
      debugPrint("Ошибка миграции: $e");
    }
  }

  void _showMigrationBottomSheet(String uid) {
    String selectedGoal = 'Похудеть';
    String selectedActivity = 'Умеренная (1-2 тренировки)';
    const goals = ['Похудеть', 'Поддержание веса', 'Набрать вес'];
    const activities = ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'];

    EvaSheet.show<void>(
      context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EvaSheetHeader(title: 'Ева стала умнее ✨', subtitle: 'Уточни пару деталей — рассчитаю норму точнее'),
                Text('Главная цель', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                ...goals.map((g) => EvaOptionTile(title: g, selected: selectedGoal == g, onTap: () => setModalState(() => selectedGoal = g))),
                const SizedBox(height: 8),
                Text('Уровень активности', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                ...activities.map((a) => EvaOptionTile(title: a, selected: selectedActivity == a, onTap: () => setModalState(() => selectedActivity = a))),
                const SizedBox(height: 16),
                EvaPrimaryButton(
                  label: 'Сохранить',
                  onPressed: () {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({'goal': selectedGoal, 'activityLevel': selectedActivity}, SetOptions(merge: true))
                        .catchError((e) => debugPrint('migration: $e'));
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabBody(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    switch (index) {
      case 0:
        return const HomeTab();
      case 1:
        return const HarmonyScreen();
      case 2:
        return const CommunityScreen();
      default:
        return const ProfileScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_tabs.length, _tabBody),
      ),
      bottomNavigationBar: _EvaNavBar(
        items: _tabs,
        currentIndex: _currentIndex,
        onSelect: _select,
        onCenterTap: () => FastFoodScannerSheet.show(context),
        badgeFor: (index) {
          if (index != 2 || uid == null || _unreadStream == null) return null;
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _unreadStream,
            builder: (context, snapshot) {
              int total = 0;
              for (final doc in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                total += evaInt(doc.data()['unread_$uid']);
              }
              if (total <= 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                ),
                child: Text(
                  total > 99 ? '99+' : '$total',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: EvaFonts.sans, color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

class _EvaNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCenterTap;
  final Widget? Function(int index) badgeFor;

  const _EvaNavBar({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.onCenterTap,
    required this.badgeFor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;

    Widget item(int i) {
      final bool active = i == currentIndex;
      final Color color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
      final Widget? badge = badgeFor(i);
      return Expanded(
        child: Semantics(
          selected: active,
          button: true,
          label: items[i].label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: active ? theme.colorScheme.primary.withValues(alpha: context.isDark ? 0.22 : 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Icon(active ? items[i].activeIcon : items[i].icon, color: color, size: 23),
                    ),
                    if (badge != null) Positioned(right: 4, top: -4, child: badge),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  items[i].label,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final Color bg = theme.scaffoldBackgroundColor;
    // Под плавающим меню — заливка цветом фона с плавным переходом:
    // карточки при прокрутке уходят под меню, а не просвечивают по краям.
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.92), bg],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: SizedBox(
            height: 82,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: context.isDark ? 0.97 : 0.98),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: palette.hairline),
                    boxShadow: palette.floatingShadow,
                  ),
                  child: Row(
                    children: [
                      item(0),
                      item(1),
                      const SizedBox(width: 72),
                      item(2),
                      item(3),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  child: Semantics(
                    button: true,
                    label: 'Добавить еду по фото',
                    child: EvaPressable(
                      onTap: onCenterTap,
                      pressedScale: 0.92,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          gradient: palette.hero,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 4),
                          boxShadow: [
                            BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
