import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'profile_screen.dart';
import 'harmony_screen.dart';
import 'p2p_chat_screen.dart';
import 'home_tab.dart'; 
import '../services/local_notification_service.dart';
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
  static const Color _darkColor = Color(0xFF1C1C1E);

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
      body: _screens[_currentIndex],
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
                // === ИСПРАВЛЕНИЕ: ВОЗВРАЩАЕМ СТАРУЮ ИКОНКУ ===
                // Убрали белый плюс (Icons.add)
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

// КЛАСС КОМЬЮНИТИ (остается в dashboard_screen, так как он короткий)
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    LocalNotificationService().cancelAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatChatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    if (now.day == date.day && now.month == date.month && now.year == date.year) {
      return DateFormat('HH:mm').format(date);
    } else if (now.difference(date).inDays <= 1 && now.day != date.day) {
      return 'Вчера';
    } else {
      return DateFormat('dd.MM.yy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Чаты', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFFE5E5EA).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() { _searchQuery = value.replaceAll('@', '').toLowerCase().trim(); });
                },
                decoration: const InputDecoration(hintText: "Поиск пользователей", hintStyle: TextStyle(color: _subTextColor, fontWeight: FontWeight.w500), prefixIcon: Icon(Icons.search, color: _subTextColor), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 14)),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isEmpty ? _buildActiveChats(currentUserId) : _buildGlobalSearch(currentUserId),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveChats(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').where('users', arrayContains: currentUserId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _accentColor));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("У вас пока нет активных диалогов", style: TextStyle(color: _subTextColor)));
        }

        final chats = snapshot.data!.docs.toList();
        chats.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['lastUpdated'] as Timestamp?;
          final bTime = bData['lastUpdated'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chatData = chats[index].data() as Map<String, dynamic>;
            final List<dynamic> users = chatData['users'] ?? [];

            final otherUserId = users.firstWhere((id) => id != currentUserId, orElse: () => '');
            if (otherUserId.isEmpty) return const SizedBox.shrink();

            final lastMessage = chatData['lastMessage'] ?? 'Нет сообщений';
            final Timestamp? lastUpdated = chatData['lastUpdated'] as Timestamp?;
            final unreadCount = (chatData['unread_$currentUserId'] as num?)?.toInt() ?? 0;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();

                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  WidgetsBinding.instance.addPostFrameCallback((_) { FirebaseFirestore.instance.collection('chats').doc(chats[index].id).delete(); });
                  return const SizedBox.shrink();
                }

                final otherUserData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                final name = otherUserData['name'] ?? 'Пользователь';
                final photoUrl = otherUserData['photoUrl'] ?? '';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: CircleAvatar(radius: 28, backgroundColor: const Color(0xFFF2F2F7), backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(Icons.person, color: Color(0xFFC7C7CC), size: 28) : null),
                  title: Text(name, style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _subTextColor, fontSize: 14)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatChatTime(lastUpdated), style: const TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 6),
                      if (unreadCount > 0)
                        Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: _accentColor, shape: BoxShape.circle), child: Text(unreadCount > 9 ? '9+' : unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  onTap: () {
                    FirebaseFirestore.instance.collection('chats').doc(chats[index].id).set({'unread_$currentUserId': 0}, SetOptions(merge: true));
                    Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: otherUserId, otherUserName: name)));
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGlobalSearch(String currentUserId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final users = snapshot.data!.docs.where((doc) {
          if (doc.id == currentUserId) return false;
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final nickname = (data['nickname'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery) || nickname.contains(_searchQuery);
        }).toList();

        if (users.isEmpty) return const Center(child: Text('Пользователи не найдены', style: TextStyle(color: _subTextColor, fontSize: 15)));

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final data = users[index].data() as Map<String, dynamic>;
            final userId = users[index].id;
            final name = data['name'] ?? 'Пользователь';
            final photoUrl = data['photoUrl'] ?? '';
            final nickname = data['nickname'] ?? '';

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: CircleAvatar(radius: 24, backgroundColor: const Color(0xFFF2F2F7), backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null, child: photoUrl.isEmpty ? const Icon(Icons.person, color: Color(0xFFC7C7CC)) : null),
              title: Text(name, style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text(nickname.isNotEmpty ? '@$nickname' : '', style: const TextStyle(color: _subTextColor, fontSize: 13)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: userId, otherUserName: name))),
            );
          },
        );
      },
    );
  }
}