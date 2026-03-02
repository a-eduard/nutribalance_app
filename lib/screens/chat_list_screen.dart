import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/chat_service.dart';
import 'p2p_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    setState(() => _searchQuery = query);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.trim().isEmpty) {
        setState(() { _searchResults = []; _isSearching = false; });
        return;
      }
      setState(() => _isSearching = true);
      final results = await _chatService.searchUsers(query);
      if (mounted) setState(() { _searchResults = results; _isSearching = false; });
    });
  }

  ImageProvider? _getAvatarProvider(String photoUrl) {
    if (photoUrl.isEmpty) return null;
    if (photoUrl.startsWith('http')) return CachedNetworkImageProvider(photoUrl);
    try { return MemoryImage(base64Decode(photoUrl)); } catch (_) { return null; }
  }

  Widget _buildSearchResultItem(Map<String, dynamic> user) {
    final String otherUserId = user['uid'];
    final String name = user['name'] ?? 'Пользователь';
    final String lastName = user['lastName'] ?? '';
    final String nickname = user['nickname'] != null && user['nickname'].toString().isNotEmpty ? '@${user['nickname']}' : '';
    final String fullName = "$name $lastName".trim();
    final ImageProvider? avatarProvider = _getAvatarProvider(user['photoUrl'] ?? '');

    // ЗАДАЧА 1: Скрываем удаленных из поиска
    if (name.trim() == 'Пользователь' || name.trim().isEmpty) return const SizedBox.shrink();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[800],
        backgroundImage: avatarProvider,
        child: avatarProvider == null ? Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white)) : null,
      ),
      title: Text(fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      subtitle: nickname.isNotEmpty ? Text(nickname, style: const TextStyle(color: Color(0xFF9CD600))) : null,
      onTap: () async {
        _searchController.clear();
        setState(() { _searchQuery = ''; _searchResults = []; });
        await _chatService.getOrCreateChat(otherUserId);
        if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: otherUserId, otherUserName: fullName)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _chatService.currentUserId;

    return Scaffold(
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        title: const Text('Сообщения', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Поиск по никнейму или имени...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null,
                filled: true,
                fillColor: const Color(0xFF1C1C1E).withValues(alpha: 0.8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Expanded(
            child: _searchQuery.isNotEmpty
              ? (_isSearching 
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)))
                  : _searchResults.isEmpty
                      ? const Center(child: Text('Пользователи не найдены', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(itemCount: _searchResults.length, itemBuilder: (context, index) => _buildSearchResultItem(_searchResults[index])))
              : StreamBuilder<QuerySnapshot>(
                  stream: _chatService.getUserChats(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 16),
                            const Text('У вас пока нет диалогов', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      );
                    }

                    var docs = snapshot.data!.docs.toList();
                    docs.sort((a, b) {
                      var timeA = (a.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                      var timeB = (b.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
                      if (timeA == null && timeB == null) return 0;
                      if (timeA == null) return 1;
                      if (timeB == null) return -1;
                      return timeB.compareTo(timeA); 
                    });

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final chatData = docs[index].data() as Map<String, dynamic>;
                        final String lastMessage = (chatData['lastMessage'] == null || chatData['lastMessage'].toString().isEmpty) ? 'Нет сообщений' : chatData['lastMessage'].toString();
                        List<dynamic> chatUsers = chatData['users'] ?? [];
                        String otherUserId = chatUsers.firstWhere((id) => id != currentUserId, orElse: () => '');
                        if (otherUserId.isEmpty) return const SizedBox.shrink();
                        final int unreadCount = chatData['unread_$currentUserId'] ?? 0;
                        final Timestamp? timeTimestamp = chatData['lastMessageTime'];
                        String timeStr = timeTimestamp != null ? DateFormat('HH:mm').format(timeTimestamp.toDate()) : '';

                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
                          builder: (context, userSnapshot) {
                            // ЗАДАЧА 1: Скрываем чаты с удаленными аккаунтами
                            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                              return const SizedBox.shrink(); 
                            }
                            
                            final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                            final String name = userData['name']?.toString().trim() ?? '';
                            
                            // Если имя пустое или равно "Пользователь" (дефолт удаленного) - не рендерим
                            if (name.isEmpty || name == 'Пользователь') {
                              return const SizedBox.shrink();
                            }

                            final String lastName = userData['lastName'] ?? '';
                            final String fullName = "$name $lastName".trim();
                            final ImageProvider? avatarProvider = _getAvatarProvider(userData['photoUrl'] ?? '');

                            return GestureDetector(
                              onTap: () async {
                                await _chatService.resetUnreadCount(otherUserId);
                                if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: otherUserId, otherUserName: fullName)));
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.8), borderRadius: BorderRadius.circular(16), border: unreadCount > 0 ? Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.5)) : Border.all(color: Colors.transparent)),
                                child: Row(
                                  children: [
                                    CircleAvatar(radius: 28, backgroundColor: Colors.grey[800], backgroundImage: avatarProvider, child: avatarProvider == null ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)) : null),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(fullName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Text(lastMessage, style: TextStyle(color: unreadCount > 0 ? Colors.white : Colors.grey, fontSize: 13, fontStyle: lastMessage == 'Нет сообщений' ? FontStyle.italic : FontStyle.normal, fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(timeStr, style: TextStyle(color: unreadCount > 0 ? const Color(0xFF9CD600) : Colors.grey, fontSize: 12)),
                                        const SizedBox(height: 6),
                                        if (unreadCount > 0) Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: Text(unreadCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}