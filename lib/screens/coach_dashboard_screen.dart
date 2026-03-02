import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart'; 

import '../widgets/base_background.dart';
import 'client_details_screen.dart'; 
import 'profile_settings_screen.dart'; 
import 'chat_list_screen.dart'; 
import 'ai_chat_screen.dart';
import '../services/database_service.dart';

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({super.key});

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  int _currentIndex = 0;

  Widget _buildClientsIcon(String uid, bool isActive) {
    Widget iconWidget = isActive 
        ? Image.asset('assets/icons/clients.png', width: 30)
        : Opacity(opacity: 0.5, child: Image.asset('assets/icons/clients.png', width: 30));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('athlete_requests').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        int pendingCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        if (pendingCount > 0) return Badge(label: Text(pendingCount.toString()), backgroundColor: Colors.redAccent, child: iconWidget);
        return iconWidget;
      },
    );
  }

  Widget _buildChatIcon(String uid, bool isActive) {
    Widget iconWidget = isActive 
        ? Image.asset('assets/icons/chats.png', width: 30)
        : Opacity(opacity: 0.5, child: Image.asset('assets/icons/chats.png', width: 30));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').where('users', arrayContains: uid).snapshots(),
      builder: (context, snapshot) {
        int unreadSum = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            unreadSum += (data['unread_$uid'] ?? 0) as int;
          }
        }
        if (unreadSum > 0) return Badge(label: Text(unreadSum.toString()), backgroundColor: Colors.redAccent, child: iconWidget);
        return iconWidget;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(backgroundColor: Colors.black);

    String appBarTitle = 'Главная';
    if (_currentIndex == 1) appBarTitle = 'Клиенты'; 
    if (_currentIndex == 2) appBarTitle = 'Чаты';
    if (_currentIndex == 3) appBarTitle = 'Моя визитка';

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          title: Text(appBarTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          centerTitle: true,
          backgroundColor: Colors.transparent, 
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (_currentIndex == 3)
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
              ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(user.uid), 
            _buildClientsTab(user.uid), 
            const ChatListScreen(),      
            _buildPublicProfileTab(user.uid), 
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), border: const Border(top: BorderSide(color: Color(0xFF1C1C1E)))),
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent, 
            selectedItemColor: const Color(0xFF9CD600),
            unselectedItemColor: Colors.grey,
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: [
              BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/home.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/home.png', width: 30)), label: 'Главная'),
              BottomNavigationBarItem(activeIcon: _buildClientsIcon(user.uid, true), icon: _buildClientsIcon(user.uid, false), label: 'Клиенты'),
              BottomNavigationBarItem(activeIcon: _buildChatIcon(user.uid, true), icon: _buildChatIcon(user.uid, false), label: 'Чаты'),
              BottomNavigationBarItem(activeIcon: Image.asset('assets/icons/profile.png', width: 30), icon: Opacity(opacity: 0.5, child: Image.asset('assets/icons/profile.png', width: 30)), label: 'Профиль'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPublicProfileTab(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('coaches').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_off, size: 60, color: Colors.grey.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text("Ваш профиль еще не заполнен.\nНажмите на шестеренку в правом верхнем углу.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),
                
                ElevatedButton.icon(
                  icon: const Icon(Icons.swap_horiz, color: Colors.black),
                  label: const Text('В режим клиента', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9CD600),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('users').doc(uid).set({'activeRole': 'athlete'}, SetOptions(merge: true));
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  },
                ),
              ],
            )
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String name = data['name'] ?? 'Имя не указано';
        final String photoUrl = data['photoUrl'] ?? '';
        final String specialization = data['specialization'] ?? 'Специализация не указана';
        final String bio = data['bio'] ?? 'Расскажите о себе в настройках...';
        final String price = data['price']?.toString() ?? 'Не указана';
        
        final double rating = (data['rating'] ?? 5.0).toDouble();
        final int totalVotes = (data['totalVotes'] ?? 0).toInt();

        ImageProvider? bgImage;
        if (photoUrl.isNotEmpty) {
          if (photoUrl.startsWith('http')) bgImage = NetworkImage(photoUrl);
          else { try { bgImage = MemoryImage(base64Decode(photoUrl)); } catch (_) {} }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(radius: 65, backgroundColor: const Color(0xFF1C1C1E), backgroundImage: bgImage, child: bgImage == null ? const Icon(Icons.person, size: 60, color: Colors.grey) : null),
              const SizedBox(height: 20),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.swap_horiz, color: Colors.black),
                label: const Text('В режим клиента', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9CD600),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  await FirebaseFirestore.instance.collection('users').doc(uid).set({'activeRole': 'athlete'}, SetOptions(merge: true));
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                },
              ),
              const SizedBox(height: 24),

              if (totalVotes > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star, color: const Color(0xFF9CD600).withValues(alpha: 0.8), size: 24),
                    const SizedBox(width: 6),
                    Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('У вас пока нет оценок', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                
              const SizedBox(height: 40),
              
              Align(alignment: Alignment.centerLeft, child: const Text('Специализация', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF9CD600).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3))),
                child: Row(
                  children: [
                    const Icon(Icons.fitness_center, color: Color(0xFF9CD600), size: 28),
                    const SizedBox(width: 16),
                    Expanded(child: Text(specialization, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.3))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Align(alignment: Alignment.centerLeft, child: const Text('О себе', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: Text(bio, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
              ),
              const SizedBox(height: 24),

              Align(alignment: Alignment.centerLeft, child: const Text('Стоимость услуг', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
              const SizedBox(height: 12),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                child: Row(
                  children: [
                    const Icon(Icons.payments, color: Colors.grey, size: 24),
                    const SizedBox(width: 16),
                    Expanded(child: Text(price, style: const TextStyle(color: Color(0xFF9CD600), fontSize: 24, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      }
    );
  }

  Widget _buildHomeTab(String uid) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').where('currentCoachId', isEqualTo: uid).where('coachRequestStatus', isEqualTo: 'accepted').snapshots(),
            builder: (context, snapshot) {
              final activeClients = snapshot.hasData ? snapshot.data!.docs.length : 0;
              return Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.people_alt, color: Color(0xFF9CD600), size: 28),
                          const SizedBox(height: 12),
                          Text(activeClients.toString(), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          const Text("Активных клиентов", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.visibility, color: Colors.blueAccent, size: 28),
                          SizedBox(height: 12),
                          Text("PRO", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                          Text("Статус в маркете", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
          ),

          const SizedBox(height: 32),

          const Text("ПРОФЕССИОНАЛЬНЫЕ ИНСТРУМЕНТЫ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'coach_mentor'))),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), width: 1.5),
                boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.psychology, color: Color(0xFF8B5CF6), size: 36),
                  ),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("ИИ-Ментор PRO", style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.w900, fontSize: 18)),
                        SizedBox(height: 8),
                        Text("Консультации по биомеханике, травмам и анализам клиентов.", style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientsTab(String uid) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // НОВЫЕ ЗАЯВКИ
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('athlete_requests').where('status', isEqualTo: 'pending').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
              final requests = snapshot.data!.docs;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
                    child: Text('Новые заявки (${requests.length})', style: const TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  ListView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final reqDoc = requests[index];
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(reqDoc.id).get(),
                        builder: (context, userSnap) {
                          if (!userSnap.hasData || !userSnap.data!.exists) return const SizedBox.shrink();
                          final userData = userSnap.data!.data() as Map<String, dynamic>;
                          
                          // ЗАДАЧА 1: Достаем фото для новых заявок
                          final String photoUrl = userData['photoUrl'] ?? '';
                          ImageProvider? avatarProvider;
                          if (photoUrl.isNotEmpty) {
                            if (photoUrl.startsWith('http')) avatarProvider = NetworkImage(photoUrl);
                            else { try { avatarProvider = MemoryImage(base64Decode(photoUrl)); } catch (_) {} }
                          }
                          
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailsScreen(clientId: reqDoc.id, clientName: userData['name']?.toString() ?? 'Клиент'))),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF9CD600).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.5))),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22, backgroundColor: Colors.black, 
                                    backgroundImage: avatarProvider,
                                    child: avatarProvider == null ? const Icon(Icons.person, color: Colors.grey) : null
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(userData['name']?.toString() ?? 'Атлет', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                                  IconButton(icon: const Icon(Icons.check_circle, color: Color(0xFF9CD600), size: 32), onPressed: () => DatabaseService().acceptCoachRequest(reqDoc.id)),
                                  IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 32), onPressed: () => DatabaseService().rejectCoachRequest(reqDoc.id)),
                                ],
                              ),
                            ),
                          );
                        }
                      );
                    },
                  ),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Divider(color: Colors.white12)),
                ],
              );
            }
          ),
          
          // АКТИВНЫЕ КЛИЕНТЫ
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').where('currentCoachId', isEqualTo: uid).where('coachRequestStatus', isEqualTo: 'accepted').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.only(top: 50.0), child: Center(child: CircularProgressIndicator(color: Color(0xFF9CD600))));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Padding(padding: const EdgeInsets.only(top: 50.0), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_outline, size: 60, color: Colors.grey.withValues(alpha: 0.3)), const SizedBox(height: 16), const Text('Нет активных клиентов', style: TextStyle(color: Colors.white, fontSize: 16))])));
              
              final clients = snapshot.data!.docs;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 12),
                    child: Text('Активные (${clients.length})', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  ListView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: clients.length,
                    itemBuilder: (context, index) {
                      final doc = clients[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final clientName = data['name']?.toString() ?? 'Клиент';
                      
                      // ЗАДАЧА 1: Достаем фото для активных клиентов
                      final String photoUrl = data['photoUrl'] ?? '';
                      ImageProvider? avatarProvider;
                      if (photoUrl.isNotEmpty) {
                        if (photoUrl.startsWith('http')) avatarProvider = NetworkImage(photoUrl);
                        else { try { avatarProvider = MemoryImage(base64Decode(photoUrl)); } catch (_) {} }
                      }
                      
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailsScreen(clientId: doc.id, clientName: clientName))),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 25, 
                                backgroundColor: Colors.black, 
                                backgroundImage: avatarProvider,
                                child: avatarProvider == null 
                                    ? Text(clientName.isNotEmpty ? clientName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                                    : null
                              ),
                              const SizedBox(width: 16),
                              Expanded(child: Text(clientName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                              const Icon(Icons.chevron_right, color: Color(0xFF9CD600), size: 28),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}