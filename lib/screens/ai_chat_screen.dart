import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/ai_service.dart';
import '../services/database_service.dart';
import '../widgets/shopping_list_widget.dart';
import '../widgets/ai_chat_parser.dart';
import '../services/push_notification_service.dart';
import 'shopping_list_screen.dart';

class AIChatScreen extends StatefulWidget {
  final String botType;
  const AIChatScreen({super.key, required this.botType});
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _savedMessageIds = {};
  bool _isTyping = false;
  String _fullUserContext = "";

  List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  static const int _maxImages = 5;

  File? _selectedPdf;
  String? _pdfFileName;

  static const Color _themeColor = Color(0xFFB76E79);
  static const Color _bgColor = Color(0xFFF9F9F9);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  String get botTitle => 'Eva — твой помощник';

  @override
  void initState() {
    super.initState();
    _initChatAndContext();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    PushNotificationService.currentActiveChatId = null;
    super.dispose();
  }

  Future<void> _initChatAndContext() async {
    PushNotificationService.currentActiveChatId = widget.botType;
    PushNotificationService().clearAllNotifications();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      _fullUserContext = await DatabaseService().getAIContextSummary();

      final historyCheck = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ai_chats_${widget.botType}')
          .limit(1)
          .get();

      if (historyCheck.docs.isEmpty) {
        String welcome =
            '''Привет! 🥰 Я Ева — твой личный ИИ-нутрициолог и заботливая подруга.✨
Ты можешь скидывать мне всё, что касается твоего здоровья. Например:
📸 Фото твоей тарелки — я сама посчитаю калории и БЖУ.
📑 Результаты анализов — я объясню их простым языком без паники.
❤️ Любой вопрос — я поддержу, когда тревожно или нужен совет.
Хочешь, я расскажу подробнее, с чего начать? 😉''';

        await DatabaseService().saveBotChatMessage(widget.botType, welcome, 'ai');
      }
    } catch (e) {
      debugPrint("Ошибка инициализации контекста: $e");
    }
  }

  Future<void> _pickImages() async {
    try {
      if (_selectedPdf != null) setState(() { _selectedPdf = null; _pdfFileName = null; });
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1024, maxHeight: 1024);

      if (pickedFiles.isNotEmpty) {
        if (pickedFiles.length > _maxImages) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ой, многовато! 😅 Можно выбрать максимум 5 фото за раз.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.orangeAccent));
          setState(() => _selectedImages = pickedFiles.take(_maxImages).map((file) => File(file.path)).toList());
        } else {
          setState(() => _selectedImages = pickedFiles.map((file) => File(file.path)).toList());
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка выбора фото: $e")));
    }
  }

  Future<void> _pickPdf() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result != null) {
        final file = result.files.single;
        if (file.size > 5 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Файл слишком большой 🙅‍♀️ Максимум 5 МБ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent));
          return;
        }
        setState(() { _selectedPdf = File(file.path!); _pdfFileName = file.name; _selectedImages = []; });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: _textColor, size: 28),
                title: const Text('Сделать фото', style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 1024, maxHeight: 1024);
                  if (photo != null) setState(() { _selectedPdf = null; _pdfFileName = null; _selectedImages = [File(photo.path)]; });
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: _textColor, size: 28),
                title: const Text('Выбрать из галереи (до 5 шт.)', style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)),
                onTap: () { Navigator.pop(ctx); _pickImages(); },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 28),
                title: const Text('Медицинские анализы (PDF)', style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)),
                onTap: () { Navigator.pop(ctx); _pickPdf(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerSendMessage(String text) {
    _controller.text = text;
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedPdf == null) return;

    final List<File> imagesToSend = List.from(_selectedImages);
    final File? pdfToSend = _selectedPdf;
    final String? pdfName = _pdfFileName;

    setState(() {
      _controller.clear();
      _selectedImages = [];
      _selectedPdf = null;
      _pdfFileName = null;
      _isTyping = true;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      List<String> imageUrls = [];
      List<String> localImagesBase64 = [];
      String? pdfUrl;
      String? localPdfBase64;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (imagesToSend.isNotEmpty) {
        List<Future<void>> uploadTasks = imagesToSend.asMap().entries.map((entry) async {
          int index = entry.key;
          File file = entry.value;
          final path = 'chats/ai_chat_${widget.botType}/${timestamp}_${uid}_$index.jpg';
          final ref = FirebaseStorage.instance.ref().child(path);
          await Future.wait([
            ref.putFile(file),
            file.readAsBytes().then((bytes) => localImagesBase64.add(base64Encode(bytes))),
          ]);
          String url = await ref.getDownloadURL();
          imageUrls.add(url);
        }).toList();
        await Future.wait(uploadTasks);
      }

      if (pdfToSend != null) {
        final safePdfName = pdfName?.replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_') ?? 'document.pdf';
        final path = 'chats/ai_chat_${widget.botType}/${timestamp}_$safePdfName';
        final ref = FirebaseStorage.instance.ref().child(path);
        await ref.putFile(pdfToSend);
        pdfUrl = await ref.getDownloadURL();
        localPdfBase64 = base64Encode(await pdfToSend.readAsBytes());
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats_${widget.botType}').add({
        'text': text,
        'role': 'user',
        'imageUrls': imageUrls,
        'pdfUrl': pdfUrl,
        'fileName': pdfName,
        'timestamp': FieldValue.serverTimestamp(),
        'isActionCompleted': false,
      });

      final history = await DatabaseService().getChatHistoryForAI(widget.botType);
      _fullUserContext = await DatabaseService().getAIContextSummary();
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('askDietitian');

      String promptToSend = text;
      if (localImagesBase64.isNotEmpty) {
        promptToSend = text.isEmpty
            ? "Распознай еду на этом фото максимально точно, оцени КБЖУ и напиши конкретное название блюда"
            : "$text\n[Скрытый промпт для ИИ: Распознай еду на этом фото максимально точно, оцени КБЖУ и напиши конкретное название блюда]";
      }

      final result = await callable.call({
        'prompt': promptToSend,
        'history': history,
        'userContext': _fullUserContext,
        'imagesBase64': localImagesBase64,
        'pdfBase64': localPdfBase64,
      });

      final String aiResponse = result.data['text'] as String;
      await DatabaseService().saveBotChatMessage(widget.botType, aiResponse, 'ai');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка ИИ: $e", style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      String jsonString = text;
      final String tick = String.fromCharCode(96);
      final String tripleTick = tick + tick + tick;
      final exp = RegExp(tripleTick + r"(?:json)?\s*([\s\S]*?)\s*" + tripleTick, caseSensitive: false);
      final match = exp.firstMatch(text);
      if (match != null) {
        jsonString = match.group(1)!;
      } else {
        final startIdx = text.indexOf('{');
        final endIdx = text.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) jsonString = text.substring(startIdx, endIdx + 1);
        else return null;
      }
      return jsonDecode(jsonString);
    } catch (e) { return null; }
  }

  String _cleanText(String text, Map<String, dynamic>? jsonData) {
    if (jsonData == null) return text.trim();
    final String tick = String.fromCharCode(96);
    final String tripleTick = tick + tick + tick;
    String stripped = text.replaceAll(RegExp(tripleTick + r"(?:json)?\s*([\s\S]*?)\s*" + tripleTick, caseSensitive: false), '').trim();
    final startIdx = stripped.indexOf('{');
    final endIdx = stripped.lastIndexOf('}');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      String possibleJson = stripped.substring(startIdx, endIdx + 1);
      try { jsonDecode(possibleJson); stripped = stripped.replaceRange(startIdx, endIdx + 1, '').trim(); } catch (_) {}
    }
    if (stripped.isEmpty && jsonData.containsKey('coach_message') && jsonData['coach_message'].toString().isNotEmpty) {
      return jsonData['coach_message'].toString().trim();
    }
    return stripped;
  }

  // === ОБНОВЛЕННОЕ МЕНЮ (LONG PRESS) ===
  void _showOptionsSheet(String docId, String currentText, bool hasMedia, String? mediaUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasMedia)
                ListTile(
                  leading: const Icon(Icons.edit_rounded, color: _textColor, size: 26),
                  title: const Text("Редактировать", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)),
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
                    await DatabaseService().deleteBotChatMessage(widget.botType, docId, mediaUrl);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка удаления'), backgroundColor: Colors.redAccent));
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
    final TextEditingController editController = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Редактировать", style: TextStyle(color: _textColor, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: editController,
          maxLines: null,
          style: const TextStyle(color: _textColor),
          decoration: const InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: _themeColor, width: 2)),
          ),
          cursorColor: _themeColor,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Отмена", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            onPressed: () async {
              final newText = editController.text.trim();
              if (newText.isNotEmpty && newText != currentText) {
                await DatabaseService().updateBotChatMessage(widget.botType, docId, newText);
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text("Сохранить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor, // Светлый премиальный фон
      appBar: AppBar(
        title: Text(botTitle, style: const TextStyle(fontWeight: FontWeight.w900, color: _textColor)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textColor),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService().getBotChatMessages(widget.botType),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _themeColor));
                final docs = snapshot.data?.docs ?? [];
                
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isUser = data['role'] == 'user';
                    final rawText = data['text'] ?? '';
                    final bool isActionCompleted = data['isActionCompleted'] == true;

                    String cleanRawText = rawText.replaceAll(RegExp(r'<thinking>[\s\S]*?<\/thinking>'), '').trim();
                    Map<String, dynamic>? shoppingListData;

                    if (!isUser) {
                      final shopExp = RegExp(r'\[SHOPP?ING_LIST\]([\s\S]*?)\[\/SHOPP?ING_LIST\]', caseSensitive: false);
                      final shopMatch = shopExp.firstMatch(cleanRawText);

                      if (shopMatch != null) {
                        String jsonStr = shopMatch.group(1) ?? '';
                        final String tick = String.fromCharCode(96);
                        final String tripleTick = tick + tick + tick;
                        final RegExp mdRegex = RegExp(tripleTick + r'(?:json)?|' + tripleTick);
                        jsonStr = jsonStr.replaceAll(mdRegex, '').trim();
                        if (jsonStr.isNotEmpty) {
                          try { shoppingListData = jsonDecode(jsonStr); } catch (_) {}
                        }
                        cleanRawText = cleanRawText.replaceAll(shopExp, '').trim();
                      }
                      cleanRawText = cleanRawText.replaceAll(RegExp(r'\[\/?SHOPP?ING_LIST\]', caseSensitive: false), '').trim();
                    }

                    final rawImageUrls = data['imageUrls'] as List<dynamic>?;
                    final List<String> imageUrls = rawImageUrls?.map((e) => e.toString()).toList() ?? [];
                    final oldImageUrl = data['imageUrl'] as String?;
                    if (imageUrls.isEmpty && oldImageUrl != null) imageUrls.add(oldImageUrl);

                    final pdfUrl = data['pdfUrl'] as String?;
                    final pdfName = data['fileName'] as String? ?? 'Анализы.pdf';

                    final jsonData = isUser ? null : _tryParseJson(cleanRawText);
                    final displayText = isUser ? rawText : _cleanText(cleanRawText, jsonData);
                    final Timestamp? ts = data['timestamp'] as Timestamp?;
                    final String timeStr = ts != null ? DateFormat('HH:mm').format(ts.toDate()) : '';

                    String? attachedImageUrl;
                    if (!isUser) {
                      // Ищем фото в последних 3-х сообщениях (на случай, если был дослан текст)
                      for (int i = index + 1; i < docs.length && i <= index + 3; i++) {
                        final prevDoc = docs[i].data() as Map<String, dynamic>;
                        if (prevDoc['role'] == 'user') {
                          final prevImages = prevDoc['imageUrls'] as List<dynamic>?;
                          final oldPrevImage = prevDoc['imageUrl'] as String?;
                          if (prevImages != null && prevImages.isNotEmpty) {
                            attachedImageUrl = prevImages.first.toString();
                            break;
                          } else if (oldPrevImage != null) {
                            attachedImageUrl = oldPrevImage;
                            break;
                          }
                          // Если дошли до сообщения только с текстом - дальше не ищем
                          if ((prevDoc['text'] ?? '').toString().isNotEmpty) break;
                        }
                      }
                    }

                    return GestureDetector(
                      onLongPress: () {
                        if (isUser) {
                          final bool hasMedia = imageUrls.isNotEmpty || pdfUrl != null;
                          String? mediaToDelete = imageUrls.isNotEmpty ? imageUrls.first : pdfUrl;
                          _showOptionsSheet(doc.id, displayText, hasMedia, mediaToDelete);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (displayText.isNotEmpty || imageUrls.isNotEmpty || pdfUrl != null)
                            Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                                decoration: BoxDecoration(
                                  color: isUser ? _themeColor : Colors.white, // Акцентный розовый для нас, белый для ИИ
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
                                    bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
                                  ),
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4))],
                                ),
                                child: Column(
                                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    if (imageUrls.isNotEmpty)
                                      Padding(padding: EdgeInsets.only(bottom: displayText.isNotEmpty ? 8.0 : 0), child: imageUrls.length == 1 ? _buildSingleImage(imageUrls.first) : _buildImageGrid(imageUrls)),
                                    if (pdfUrl != null)
                                      Container(
                                        margin: EdgeInsets.only(bottom: displayText.isNotEmpty ? 8.0 : 0),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: isUser ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(12)),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 28),
                                            const SizedBox(width: 12),
                                            Flexible(child: Text(pdfName, style: TextStyle(color: isUser ? Colors.white : _textColor, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                          ],
                                        ),
                                      ),
                                    if (displayText.isNotEmpty)
                                      Wrap(
                                        alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.end,
                                        children: [
                                          Text(displayText, style: TextStyle(color: isUser ? Colors.white : _textColor, fontSize: 15, height: 1.4, fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 8),
                                          Padding(padding: const EdgeInsets.only(bottom: 2.0), child: Text(timeStr, style: TextStyle(color: isUser ? Colors.white.withValues(alpha: 0.7) : _subTextColor, fontSize: 10, fontWeight: FontWeight.bold))),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (shoppingListData != null) RecipeShoppingCardWidget(data: shoppingListData, msgId: doc.id),
                          if (jsonData != null) AIChatSaveCardWidget(jsonData: jsonData, msgId: doc.id, botType: widget.botType, themeColor: _themeColor, isInitiallySaved: isActionCompleted || _savedMessageIds.contains(doc.id), onSaveSuccess: (id) => setState(() => _savedMessageIds.add(id)), onSendMessage: _triggerSendMessage),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_isTyping) Padding(padding: const EdgeInsets.all(8.0), child: Text("Ева печатает...", style: TextStyle(color: _themeColor, fontSize: 12, fontWeight: FontWeight.w600))),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildSingleImage(String url) {
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: url, width: 200, fit: BoxFit.cover, placeholder: (c, u) => const CircularProgressIndicator()));
  }

  Widget _buildImageGrid(List<String> urls) {
    int crossAxisCount = urls.length >= 2 ? 2 : 1;
    if (urls.length >= 3) crossAxisCount = 3;
    if (urls.length == 4) crossAxisCount = 2;
    double gridHeight = urls.length <= 3 ? 100 : 200;
    return SizedBox(
      width: 250, height: gridHeight,
      child: GridView.builder(padding: EdgeInsets.zero, physics: const NeverScrollableScrollPhysics(), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 4, mainAxisSpacing: 4, childAspectRatio: 1.0), itemCount: urls.length, itemBuilder: (context, index) { return ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: urls[index], fit: BoxFit.cover, placeholder: (c, u) => Container(color: const Color(0xFFF2F2F7)))); }),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, -8))],
      ),
      child: SafeArea(
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedImages.isNotEmpty)
              Container(
                height: 80, margin: const EdgeInsets.only(bottom: 12),
                child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _selectedImages.length, itemBuilder: (context, index) { return Stack(children: [Container(margin: const EdgeInsets.only(right: 8, top: 8), width: 70, height: 70, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), image: DecorationImage(image: FileImage(_selectedImages[index]), fit: BoxFit.cover))), Positioned(right: 0, top: 0, child: GestureDetector(onTap: () => setState(() => _selectedImages.removeAt(index)), child: const CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Icon(Icons.close, size: 14, color: Colors.black))))]); }),
              ),
            if (_selectedPdf != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(16)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 24), const SizedBox(width: 8), Expanded(child: Text(_pdfFileName ?? 'Документ.pdf', style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)), GestureDetector(onTap: () => setState(() { _selectedPdf = null; _pdfFileName = null; }), child: const Icon(Icons.close, color: _subTextColor, size: 24))]),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: GestureDetector(
                    onTap: _showAttachmentOptions, 
                    child: Container(padding: const EdgeInsets.all(14), child: const Icon(Icons.attach_file_rounded, color: _themeColor, size: 26)),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 4, minLines: 1,
                    style: const TextStyle(color: _textColor),
                    decoration: const InputDecoration(
                      hintText: "Спроси Еву...", hintStyle: TextStyle(color: Color(0xFFC7C7CC)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide.none),
                      filled: true, fillColor: Color(0xFFF2F2F7),
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 2), decoration: const BoxDecoration(color: _themeColor, shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.white, size: 22)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// === RecipeShoppingCardWidget остается прежним (розовый градиент вписывается в светлую тему идеально) ===
class RecipeShoppingCardWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final String msgId;
  const RecipeShoppingCardWidget({super.key, required this.data, required this.msgId});
  @override
  State<RecipeShoppingCardWidget> createState() => _RecipeShoppingCardWidgetState();
}

class _RecipeShoppingCardWidgetState extends State<RecipeShoppingCardWidget> {
  bool _isLoading = false;
  bool _isAdded = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.data['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(3).toList();
    final extraCount = items.length - 3;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFFB76E79).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              const Text("Ингредиенты для рецепта", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 16),
          ...displayItems.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.white, size: 6),
                const SizedBox(width: 8),
                Expanded(child: Text("${item['name']} - ${item['amount']}", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
              ],
            ),
          )),
          if (extraCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text("...и еще $extraCount", style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontStyle: FontStyle.italic, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isAdded ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                foregroundColor: const Color(0xFFB76E79),
                elevation: _isAdded ? 0 : 4,
                shadowColor: Colors.black.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_isAdded || _isLoading) ? null : () async {
                setState(() => _isLoading = true);
                try {
                  await DatabaseService().addIngredientsToShoppingList(items);
                  if (mounted) {
                    setState(() => _isAdded = true);
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.showSnackBar(
                      SnackBar(
                        content: const Text("Ингредиенты добавлены в «Мой список» 🛒", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.teal,
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                        action: SnackBarAction(
                          label: 'Перейти', textColor: Colors.white,
                          onPressed: () {
                            messenger.hideCurrentSnackBar();
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen()));
                          },
                        ),
                      ),
                    );
                    Future.delayed(const Duration(seconds: 2), () { messenger.hideCurrentSnackBar(); });
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFB76E79), strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_isAdded ? Icons.check : Icons.add, color: _isAdded ? Colors.white : const Color(0xFFB76E79), size: 18),
                        const SizedBox(width: 8),
                        Text(_isAdded ? "Добавлено ✓" : "Добавить в Мой список", style: TextStyle(color: _isAdded ? Colors.white : const Color(0xFFB76E79), fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}