import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/chat_service.dart';

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
  final ChatService _chatService = ChatService();
  
  String? _chatRoomId;
  bool _isSending = false;
  String? _editingMessageId; 
  
  // Новые цвета NutriBalance
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _bgColor = Color(0xFF1A1A1C);

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    _chatRoomId = await _chatService.getOrCreateChat(widget.otherUserId);
    await _chatService.resetUnreadCount(widget.otherUserId);
    if (mounted) setState(() {}); 
  }

  void _setEditingMode(String messageId, String text) {
    setState(() {
      _editingMessageId = messageId;
      _messageController.text = text;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  Future<void> _updateMessage() async {
    final newText = _messageController.text.trim();
    if (newText.isEmpty || _editingMessageId == null || _chatRoomId == null) return;

    final String msgId = _editingMessageId!;
    _cancelEditing(); 

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatRoomId)
          .collection('messages')
          .doc(msgId)
          .update({
        'text': newText,
        'isEdited': true,
        'editTimestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Ошибка обновления: $e");
    }
  }

  Future<void> _deleteMessage(String messageId, String? imageUrl) async {
    if (_chatRoomId == null) return;
    try {
      await _chatService.deleteMessage(_chatRoomId!, messageId, imageUrl: imageUrl);
    } catch (e) {
      debugPrint("Ошибка удаления: $e");
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF9F9F9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text('Сделать фото', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _pickAndSendImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Выбрать из галереи', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _pickAndSendImage(ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, imageQuality: 85, maxWidth: 1080, maxHeight: 1080);
    if (pickedFile != null) {
      setState(() => _isSending = true);
      try {
        final File imageFile = File(pickedFile.path);
        await _chatService.sendMessage(widget.otherUserId, "", imageFile: imageFile);
      } catch (e) {
      } finally {
        if (mounted) setState(() => _isSending = false);
      }
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _chatRoomId == null) return;

    setState(() { _messageController.clear(); _isSending = true; });

    try {
      await _chatService.sendMessage(widget.otherUserId, text);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showContextMenu(String messageId, String text, bool isMe, bool isTextOnly, String? imageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF9F9F9),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white),
              title: const Text('Копировать текст', style: TextStyle(color: Colors.white)),
              onTap: () { Clipboard.setData(ClipboardData(text: text)); Navigator.pop(ctx); },
            ),
            if (isMe && isTextOnly)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: const Text('Редактировать', style: TextStyle(color: Colors.white)),
                onTap: () { Navigator.pop(ctx); _setEditingMode(messageId, text); },
              ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text('Удалить у всех', style: TextStyle(color: Colors.redAccent)),
                onTap: () { Navigator.pop(ctx); _deleteMessage(messageId, imageUrl); },
              ),
          ],
        ),
      ),
    );
  }

  void _showImageFullScreen(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5, maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                placeholder: (context, url) => const CircularProgressIndicator(color: _accentColor),
                errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white, size: 50),
              ),
            ),
            Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Row(
          children: [
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(widget.otherUserId).get(),
              builder: (context, snapshot) {
                final photoUrl = (snapshot.hasData && snapshot.data!.exists) 
                    ? (snapshot.data!.data() as Map<String, dynamic>)['photoUrl'] as String? 
                    : null;

                ImageProvider? avatarProvider;
                if (photoUrl != null && photoUrl.isNotEmpty) {
                  if (photoUrl.startsWith('http')) avatarProvider = CachedNetworkImageProvider(photoUrl);
                  else { try { avatarProvider = MemoryImage(base64Decode(photoUrl)); } catch (_) {} }
                }

                return CircleAvatar(
                  radius: 18, backgroundColor: Colors.grey[800], backgroundImage: avatarProvider,
                  child: avatarProvider == null ? Text(widget.otherUserName.isNotEmpty ? widget.otherUserName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)) : null,
                );
              }
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.otherUserName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          ],
        ),
        backgroundColor: _bgColor,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _chatRoomId == null 
              ? const Center(child: CircularProgressIndicator(color: _accentColor))
              : StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats').doc(_chatRoomId)
                      .collection('messages').orderBy('timestamp', descending: true) 
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _accentColor));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text('Нет сообщений', style: TextStyle(color: Colors.white.withOpacity(0.3))));

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true, 
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final doc = snapshot.data!.docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final isMe = data['senderId'] == _chatService.currentUserId;
                        final String text = data['text'] ?? '';
                        final String? imageUrl = data['imageUrl'];
                        final bool isEdited = data['isEdited'] ?? false;
                        
                        final Timestamp? ts = data['timestamp'] as Timestamp?;
                        final String timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '...';

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _showContextMenu(doc.id, text, isMe, imageUrl == null, imageUrl),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? _accentColor : const Color(0xFFF9F9F9),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20), topRight: const Radius.circular(20),
                                  bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (imageUrl != null)
                                    GestureDetector(
                                      onTap: () => _showImageFullScreen(imageUrl),
                                      child: Padding(
                                        padding: EdgeInsets.only(bottom: text.isNotEmpty ? 8.0 : 0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(16),
                                          child: CachedNetworkImage(
                                            imageUrl: imageUrl, width: 200, fit: BoxFit.cover,
                                            placeholder: (context, url) => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator(color: _accentColor))),
                                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.white, size: 40),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (text.isNotEmpty || imageUrl == null)
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment: WrapCrossAlignment.end,
                                      children: [
                                        if (text.isNotEmpty)
                                          Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
                                        const SizedBox(width: 8),
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2.0),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isEdited)
                                                const Padding(
                                                  padding: EdgeInsets.only(right: 4),
                                                  child: Text('изм.', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                                                ),
                                              Text(timeStr, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: const BoxDecoration(color: Color(0xFF1A1A1C), border: Border(top: BorderSide(color: Colors.white10))),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_editingMessageId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.edit, color: _accentColor, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(child: Text('Редактирование', style: TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.bold))),
                          GestureDetector(onTap: _cancelEditing, child: const Icon(Icons.close, color: Colors.grey, size: 18)),
                        ],
                      ),
                    ),
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: _editingMessageId != null ? null : _showAttachmentOptions),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(20)),
                          child: TextField(
                            controller: _messageController,
                            keyboardType: TextInputType.multiline,
                            maxLines: 5, minLines: 1, textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(hintText: 'Сообщение...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)), border: InputBorder.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isSending ? null : (_editingMessageId != null ? _updateMessage : _sendMessage),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 2), 
                          decoration: const BoxDecoration(color: _accentColor, shape: BoxShape.circle),
                          child: _isSending 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Icon(_editingMessageId != null ? Icons.check : Icons.send, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
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