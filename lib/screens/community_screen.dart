import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'p2p_chat_screen.dart';
import 'ai_chat_screen.dart';
import '../services/local_notification_service.dart';

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
        title: const Text('Комьюнити', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 1. Поиск пользователей
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

          // 2. Закрепленная карточка Евы
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFB76E79).withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB76E79).withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB6A6CA).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: Color(0xFFB76E79), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("Ева ✨", style: TextStyle(color: Color(0xFF2D2D2D), fontSize: 16, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text("Твой личный нутрициолог", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF8E8E93)),
                ],
              ),
            ),
          ),
          
          // 3. Список чатов
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