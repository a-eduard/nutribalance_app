import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart'; 
import 'history_screen.dart';
import 'coach_list_screen.dart'; 
import 'chat_list_screen.dart'; 
import 'my_programs_screen.dart';
import 'ai_chat_screen.dart'; 

import '../services/push_notification_service.dart';
import '../widgets/base_background.dart'; 

import '../widgets/dashboard/my_coach_card.dart';
import '../widgets/dashboard/nutrition_card.dart';
import '../widgets/dashboard/progress_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  static const Color _accentColor = Color(0xFF9CD600); 
  bool _isPro = false; 

  @override
  void initState() {
    super.initState();
    PushNotificationService().initialize(); 
    _checkProStatus();
  }

  Future<void> _checkProStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _isPro = doc.data()?['isPro'] == true;
        });
      }
    }
  }

  final List<Widget> _screens = [
    const HomeTab(),
    const HistoryScreen(),
    const ChatListScreen(), 
    const CoachListScreen(), 
    const ProfileScreen(),
  ];

  Widget _buildChatIcon(bool isActive, int unreadSum) {
    Widget iconWidget = isActive 
      ? Image.asset('assets/icons/chats.png', width: 30)
      : Opacity(
          opacity: 0.5,
          child: Image.asset('assets/icons/chats.png', width: 30),
        );

    if (unreadSum > 0) {
      return Badge(
        label: Text(unreadSum.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        child: iconWidget,
      );
    }
    return iconWidget;
  }

  void _onTabTapped(int index) {
    if (index == 3 && !_isPro) {
      Navigator.pushNamed(context, '/paywall');
      return; 
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        body: _screens[_currentIndex],
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFF1C1C1E))), 
            color: Color(0xFF000000), 
          ),
          child: uid == null 
            ? _buildNavBar(0)
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('chats').where('users', arrayContains: uid).snapshots(),
                builder: (context, snapshot) {
                  int unreadSum = 0;
                  if (snapshot.hasData) {
                    for (var doc in snapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      unreadSum += (data['unread_$uid'] ?? 0) as int;
                    }
                  }
                  return _buildNavBar(unreadSum);
                },
              ),
        ),
      ),
    );
  }

  Widget _buildNavBar(int unreadSum) {
    return BottomNavigationBar(
      backgroundColor: Colors.transparent, 
      selectedItemColor: _accentColor, 
      unselectedItemColor: Colors.grey, 
      currentIndex: _currentIndex,
      onTap: _onTabTapped, 
      type: BottomNavigationBarType.fixed, 
      elevation: 0,
      items: [
        BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/home.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/home.png', width: 30)), label: 'Главная'),
        BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/history.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/history.png', width: 30)), label: 'История'),
        BottomNavigationBarItem(icon: _buildChatIcon(false, unreadSum), activeIcon: _buildChatIcon(true, unreadSum), label: 'Чаты'),
        BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/marketplace.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/marketplace.png', width: 30)), label: 'Тренеры'),
        BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/profile.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/profile.png', width: 30)), label: 'Профиль'),
      ],
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  static const Color _accentColor = Color(0xFF9CD600);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _accentColor));
            }

            final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final name = userData['name']?.toString() ?? '';
            final coachId = userData['currentCoachId'];
            bool isPro = userData['isPro'] ?? false;
            bool hasNewProgram = userData['hasNewProgram'] == true;

            // БЛОК 1: Проверяем, является ли имя дефолтным
            final bool isDefaultName = name.isEmpty || name.startsWith('Атлет_') || name.startsWith('Тренер_');

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Tonna AI", style: TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  
                  // БЛОК 1: Показываем приветствие только если имя настоящее
                  if (!isDefaultName)
                    Text(
                      "Привет, $name", 
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold) 
                    ),
                  
                  const SizedBox(height: 24),

                  if (coachId != null && coachId.toString().isNotEmpty)
                     MyCoachCard(
                      coachId: coachId.toString(),
                      requestStatus: userData['coachRequestStatus']?.toString(),
                     ),

                  if (isPro) const NutritionSummaryCard(),
                  
                  const WorkoutProgressCard(), 

                  const SizedBox(height: 16),
                  
                  _AIAssistantsCardIntegrated(isPro: isPro),

                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const MyProgramsScreen()));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.transparent, 
                        borderRadius: BorderRadius.circular(16), 
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5)
                      ),
                      child: Row(
                        children: [
                          Badge(
                            isLabelVisible: hasNewProgram,
                            backgroundColor: Colors.redAccent,
                            smallSize: 12,
                            child: Image.asset('assets/icons/my_programs.png', width: 40, height: 40, fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Мои тренировки', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                          const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32), 
                ],
              ),
            );
          }
        ),
      ),
    );
  }
}

class _AIAssistantsCardIntegrated extends StatelessWidget {
  final bool isPro;
  const _AIAssistantsCardIntegrated({required this.isPro});

  Widget _buildActionCard(BuildContext context, {required String title, required String imagePath, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(imagePath, width: 32, height: 32, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(title, maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ИИ-АССИСТЕНТЫ', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                title: 'Питание',
                imagePath: 'assets/icons/ai_dietitian.png',
                onTap: () {
                  if (isPro) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
                  } else {
                    Navigator.pushNamed(context, '/paywall'); 
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                title: 'Тренер',
                imagePath: 'assets/icons/ai_trainer.png',
                onTap: () {
                  if (isPro) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'trainer')));
                  } else {
                    Navigator.pushNamed(context, '/paywall'); 
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}