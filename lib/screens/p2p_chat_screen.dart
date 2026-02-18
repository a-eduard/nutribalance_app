import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import '../services/push_notification_service.dart';

class P2PChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;

  const P2PChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<P2PChatScreen> createState() => _P2PChatScreenState();
}

class _P2PChatScreenState extends State<P2PChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _chatRoomId {
    List<String> ids = [_currentUserId, widget.otherUserId];
    ids.sort(); // Сортируем для создания уникального и неизменного ID комнаты
    return ids.join('_');
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      // 1. Сохраняем сообщение в базу
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add({
        'senderId': _currentUserId,
        'receiverId': widget.otherUserId,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Скроллим вниз
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      // --- БЛОК ОТПРАВКИ PUSH-УВЕДОМЛЕНИЯ (ЧАТ) С ЛОГАМИ ---
      try {
        debugPrint('--- НАЧАЛО ОТПРАВКИ ПУША (ЧАТ) ---');
        final receiverDoc = await FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).get();
        
        if (receiverDoc.exists) {
          debugPrint('FCM: Документ собеседника найден!');
          if (receiverDoc.data()!.containsKey('fcmToken')) {
            String receiverToken = receiverDoc.data()!['fcmToken'];
            String senderName = FirebaseAuth.instance.currentUser?.displayName ?? 'Пользователь';
            
            debugPrint('FCM: Токен собеседника: $receiverToken');
            PushNotificationService.sendPushMessage(
              token: receiverToken,
              title: 'Новое сообщение от $senderName',
              body: text,
            ).then((_) {
              debugPrint('FCM: Пуш для чата отправлен на сервер!');
            });
          } else {
            debugPrint('FCM ОШИБКА: У собеседника нет fcmToken');
          }
        } else {
          debugPrint('FCM ОШИБКА: Документ собеседника не найден');
        }
      } catch (e) {
        debugPrint('FCM: Ошибка отправки пуша из чата: $e');
      }
      // ------------------------------------------------------

    } catch (e) {
      debugPrint("Ошибка отправки сообщения: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.otherUserName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1C1C1E),
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Нет сообщений', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFFCCFF00) : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 0),
                            bottomRight: Radius.circular(isMe ? 0 : 16),
                          ),
                        ),
                        child: Text(
                          data['text'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.black : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Поле ввода сообщения
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Введите сообщение...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFCCFF00),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.black, size: 20),
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
}