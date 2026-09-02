import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/database_service.dart';
import '../services/local_notification_service.dart';

class P2PChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? customCollection;

  const P2PChatScreen({
    super.key, 
    required this.otherUserId, 
    required this.otherUserName,
    this.customCollection, 
  });

  @override
  State<P2PChatScreen> createState() => _P2PChatScreenState();
}

class _P2PChatScreenState extends State<P2PChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker(); 
  
  bool _isUploading = false; 

  String get currentUserId => FirebaseAuth.instance.currentUser!.uid;
  String get _collectionName => widget.customCollection ?? 'chats';

  String get _chatId {
    return currentUserId.compareTo(widget.otherUserId) < 0
        ? '${currentUserId}_${widget.otherUserId}'
        : '${widget.otherUserId}_$currentUserId';
  }

  @override
  void initState() {
    super.initState();
    _resetMyUnreadCount();
    LocalNotificationService().cancelAll();
  }

  @override
  void dispose() {
    _resetMyUnreadCount(); 
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _resetMyUnreadCount() async {
    await FirebaseFirestore.instance.collection(_collectionName).doc(_chatId).set({
      'unread_$currentUserId': 0,
    }, SetOptions(merge: true));
  }

  Future<void> _pickAndUploadImage() async {
    final theme = Theme.of(context);
    final String? action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.camera_alt, color: theme.colorScheme.onSurface, size: 28), 
                  title: Text("Сделать фото", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500)), 
                  onTap: () => Navigator.pop(ctx, 'camera')
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: theme.colorScheme.onSurface, size: 28), 
                  title: Text("Выбрать из галереи", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500)), 
                  onTap: () => Navigator.pop(ctx, 'gallery')
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) return; 
    final ImageSource source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;

    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1200);
      if (pickedFile == null) return;
      setState(() => _isUploading = true); 

      final File imageFile = File(pickedFile.path);
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference storageRef = FirebaseStorage.instance.ref().child('chats_media').child(_chatId).child(fileName);

      final UploadTask uploadTask = storageRef.putFile(imageFile);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      _sendMessage(imageUrl: downloadUrl);

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isUploading = false); 
    }
  }

  void _sendMessage({String? imageUrl}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return; 

    _messageController.clear();
    final lastMessageText = imageUrl != null ? '📷 Изображение' : text;

    await FirebaseFirestore.instance.collection(_collectionName).doc(_chatId).collection('messages').add({
      if (text.isNotEmpty) 'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl, 
      'senderId': currentUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection(_collectionName).doc(_chatId).set({
      'lastMessage': lastMessageText,
      'lastUpdated': FieldValue.serverTimestamp(),
      'users': [currentUserId, widget.otherUserId],
      'unread_${widget.otherUserId}': FieldValue.increment(1), 
    }, SetOptions(merge: true));
  }

  void _showOptionsSheet(String docId, String currentText, bool hasMedia, String? mediaUrl) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasMedia)
                ListTile(
                  leading: Icon(Icons.edit_rounded, color: theme.colorScheme.onSurface, size: 26),
                  title: Text("Редактировать", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditDialog(docId, currentText);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: Colors.redAccent, size: 26),
                title: const Text("Удалить", style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await DatabaseService().deleteP2PMessage(_chatId, docId, mediaUrl);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка удаления'), backgroundColor: Colors.redAccent));
                  }
                },
              ),
            ],
          ),
        ),
      )
    );
  }

  void _showEditDialog(String docId, String currentText) {
    final theme = Theme.of(context);
    final TextEditingController editController = TextEditingController(text: currentText);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Редактировать", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: editController,
          maxLines: null,
          style: TextStyle(color: theme.colorScheme.onSurface),
          decoration: InputDecoration(
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(Radius.circular(12)), 
              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)
            ),
          ),
          cursorColor: theme.colorScheme.primary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: Text("Отмена", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
              elevation: 0
            ),
            onPressed: () async {
              final newText = editController.text.trim();
              if (newText.isNotEmpty && newText != currentText) {
                await DatabaseService().updateP2PMessage(_chatId, docId, newText);
              }
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: Text("Сохранить", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.otherUserName, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 20)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        actions: _isUploading 
            ? [Padding(padding: const EdgeInsets.only(right: 16.0), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)))] 
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection(_collectionName).doc(_chatId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                }
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.waving_hand, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text("Напишите первое сообщение ✨", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  );
                }

                final messages = snapshot.data!.docs;
                if (messages.isNotEmpty && messages.first['senderId'] != currentUserId) _resetMyUnreadCount();

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, 
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final bool isMe = data['senderId'] == currentUserId;
                    final Timestamp? ts = data['timestamp'] as Timestamp?;
                    final String timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';
                    
                    final String textMessage = data['text'] ?? '';
                    final String? imageUrlMessage = data['imageUrl'];
                    final bool hasImage = imageUrlMessage != null && imageUrlMessage.isNotEmpty;

                    return GestureDetector(
                      onLongPress: () {
                        if (isMe) _showOptionsSheet(messages[index].id, textMessage, hasImage, imageUrlMessage);
                      },
                      child: Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), 
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMe ? theme.colorScheme.primary : theme.colorScheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                              bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                            ),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (hasImage) 
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: GestureDetector(
                                      onTap: () { 
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)), body: Center(child: Hero(tag: imageUrlMessage, child: Image.network(imageUrlMessage)))))); 
                                      },
                                      child: Hero(
                                        tag: imageUrlMessage,
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrlMessage, fit: BoxFit.cover,
                                          placeholder: (context, url) => SizedBox(width: 200, height: 150, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary, strokeWidth: 2))),
                                          errorWidget: (context, url, error) => const SizedBox(width: 200, height: 150, child: Center(child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey))),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              
                              if (textMessage.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2),
                                  child: Text(textMessage, style: TextStyle(color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w500, height: 1.3)),
                                ),
                              
                              const SizedBox(height: 2),
                              Padding(
                                padding: const EdgeInsets.only(right: 2.0, bottom: 0),
                                child: Text(timeStr, style: TextStyle(color: isMe ? theme.colorScheme.onPrimary.withValues(alpha: 0.7) : theme.colorScheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.bold)),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface, 
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, -8))]
            ),
            child: SafeArea(
              bottom: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0), 
                    child: GestureDetector(
                      onTap: _isUploading ? null : _pickAndUploadImage, 
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        child: Icon(Icons.attach_file_rounded, color: theme.colorScheme.primary, size: 26),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4, minLines: 1,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: "Сообщение...", 
                        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide.none),
                        filled: true, 
                        fillColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isUploading ? null : () => _sendMessage(), 
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                      child: Icon(Icons.send_rounded, color: theme.colorScheme.onPrimary, size: 22),
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