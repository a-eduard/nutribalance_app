import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/ai_service.dart';
import '../services/database_service.dart';
import '../widgets/shopping_list_widget.dart';
import '../widgets/ai_chat_parser.dart';

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
  File? _selectedImage;

  Color get themeColor => const Color(0xFFB76E79); // Единый цвет Rose Gold
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
    super.dispose();
  }

  Future<void> _initChatAndContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          // СТРОГИЙ ПРОМПТ: Запрещаем ИИ переспрашивать данные
          _fullUserContext =
              """
[БАЗОВЫЕ ДАННЫЕ ПОЛЬЗОВАТЕЛЯ]
Пол: ${d['gender'] ?? 'не указано'}
Возраст: ${d['age'] ?? 'не указано'}
Вес: ${d['weight'] ?? 'не указано'} кг
Рост: ${d['height'] ?? 'не указано'} см
Цель: ${d['goal'] ?? 'не указано'}
Активность: ${d['activityLevel'] ?? 'не указано'}

СТРОГОЕ ПРАВИЛО: Я уже передал тебе эти данные. НИКОГДА не проси пользователя заполнить анкету и не спрашивай его рост, вес, возраст или цель заново, если они здесь указаны (не равны 'не указано'). Сразу переходи к делу и отвечай на его запрос!
""";
        });
      }

      final historyCheck = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ai_chats_${widget.botType}')
          .limit(1)
          .get();

      if (historyCheck.docs.isEmpty) {
        String welcome =
            "Привет! Я Ева — твой личный ИИ-помощник, нутрициолог и подруга. ✨ Я здесь не для того, чтобы сажать тебя на жесткие диеты, а чтобы помочь обрести гармонию с телом. Хочешь, я расскажу, что я умею и как могу сделать твою жизнь легче?";

        if (widget.botType == 'trainer') {
          welcome = "Привет! Я твой ИИ-Тренер. 💪 Какая у тебя цель?";
        } else if (widget.botType == 'coach_mentor') {
          welcome =
              "Приветствую, коллега! 🧠 Я ИИ-Ментор по биомеханике, медицине и тренировкам. Какой сложный случай клиента разберем сегодня?";
        }

        await DatabaseService().saveBotChatMessage(
          widget.botType,
          welcome,
          'ai',
        );
      }
    } catch (e) {
      debugPrint("Ошибка инициализации: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 70,
      );
      if (pickedFile != null)
        setState(() => _selectedImage = File(pickedFile.path));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Ошибка выбора фото: $e")));
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title: const Text(
                'Сделать фото',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text(
                'Выбрать из галереи',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLongPressMenu(String docId, String text, bool isUser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white),
              title: const Text(
                'Копировать текст',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
              },
            ),
            if (isUser)
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.white),
                title: const Text(
                  'Редактировать',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _controller.text = text;
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text(
                'Удалить сообщение',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null)
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('ai_chats_${widget.botType}')
                      .doc(docId)
                      .delete();
              },
            ),
          ],
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
    if (text.isEmpty && _selectedImage == null) return;

    final File? imageToSend = _selectedImage;
    setState(() {
      _controller.clear();
      _selectedImage = null;
      _isTyping = true;
    });

    try {
      String? imageUrl;
      String? localBase64;

      if (imageToSend != null) {
        imageUrl = await DatabaseService().uploadChatImage(
          imageToSend,
          'ai_chat_${widget.botType}',
        );
        localBase64 = base64Encode(await imageToSend.readAsBytes());
      }

      await DatabaseService().saveBotChatMessage(
        widget.botType,
        text,
        'user',
        imageUrl: imageUrl,
      );

      String aiResponse = "";
      if (localBase64 != null && widget.botType == 'dietitian') {
        aiResponse = await AIService().sendMultimodalMessage(
          userMessage: text,
          base64Image: localBase64,
          userContext: _fullUserContext,
        );
      } else {
        final history = await DatabaseService().getChatHistoryForAI(
          widget.botType,
        );
        aiResponse = await AIService().sendChatMessage(
          botType: widget.botType,
          userMessage: text,
          userContext: _fullUserContext,
          chatHistory: history,
        );
      }

      await DatabaseService().saveBotChatMessage(
        widget.botType,
        aiResponse,
        'ai',
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Ошибка ИИ: $e")));
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      String jsonString = text;

      // 1. Извлекаем сырой текст
      final exp = RegExp(
        r"```(?:json)?\s*([\s\S]*?)\s*```",
        caseSensitive: false,
      );
      final match = exp.firstMatch(text);
      if (match != null) {
        jsonString = match.group(1)!;
      } else {
        final startIdx = text.indexOf('{');
        final endIdx = text.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
          jsonString = text.substring(startIdx, endIdx + 1);
        } else {
          return null;
        }
      }

      // 2. ХИРУРГИЧЕСКАЯ ОЧИСТКА ГАЛЛЮЦИНАЦИЙ ИИ
      // Убираем висячие запятые перед закрывающими скобками (частая ошибка Gemini)
      jsonString = jsonString.replaceAll(RegExp(r',\s*\}'), '}');
      jsonString = jsonString.replaceAll(RegExp(r',\s*\]'), ']');
      jsonString = jsonString.trim();

      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint("Parse Error: $e");
      return null;
    }
  }

  String _cleanText(String text, Map<String, dynamic>? jsonData) {
    if (jsonData == null) return text.trim();

    String stripped = text
        .replaceAll(
          RegExp(r"```(?:json)?\s*([\s\S]*?)\s*```", caseSensitive: false),
          '',
        )
        .trim();

    if (stripped.startsWith('{') && stripped.endsWith('}')) {
      stripped = '';
    }

    if (stripped.isEmpty &&
        jsonData.containsKey('coach_message') &&
        jsonData['coach_message'].toString().isNotEmpty) {
      return jsonData['coach_message'].toString().trim();
    }

    return stripped;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        image: DecorationImage(
          image: const AssetImage('assets/images/app_bg_silhouette.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.8),
            BlendMode.darken,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            botTitle,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: DatabaseService().getBotChatMessages(widget.botType),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return Center(
                      child: CircularProgressIndicator(color: themeColor),
                    );
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

                      // QA FIX: Читаем состояние из БД (State Management)
                      final bool isActionCompleted =
                          data['isActionCompleted'] == true;

                      final cleanRawText = rawText
                          .replaceAll(
                            RegExp(r'<thinking>[\s\S]*?<\/thinking>'),
                            '',
                          )
                          .trim();

                      final imageUrl = data['imageUrl'] as String?;
                      final jsonData = isUser
                          ? null
                          : _tryParseJson(cleanRawText);
                      final displayText = isUser
                          ? rawText
                          : _cleanText(cleanRawText, jsonData);

                      final Timestamp? ts = data['timestamp'] as Timestamp?;
                      final String timeStr = ts != null
                          ? DateFormat('HH:mm').format(ts.toDate())
                          : '';
                      final bool isEdited = data['isEdited'] == true;

                      return Column(
                        crossAxisAlignment: isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (displayText.isNotEmpty || imageUrl != null)
                            Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: GestureDetector(
                                onLongPress: () => _showLongPressMenu(
                                  doc.id,
                                  displayText,
                                  isUser,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.85,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? themeColor.withValues(alpha: 0.1)
                                        : const Color(
                                            0xFF1E1E1E,
                                          ).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isUser
                                          ? themeColor.withValues(alpha: 0.3)
                                          : themeColor.withValues(alpha: 0.1),
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isUser
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      if (imageUrl != null)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: displayText.isNotEmpty
                                                ? 8.0
                                                : 0,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              width: 200,
                                              fit: BoxFit.cover,
                                              placeholder: (c, u) =>
                                                  const CircularProgressIndicator(),
                                            ),
                                          ),
                                        ),
                                      if (displayText.isNotEmpty ||
                                          imageUrl == null)
                                        Wrap(
                                          alignment: WrapAlignment.end,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.end,
                                          children: [
                                            if (displayText.isNotEmpty)
                                              Text(
                                                displayText,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  height: 1.4,
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 2.0,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isEdited)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        right: 4,
                                                      ),
                                                      child: Text(
                                                        'изм.',
                                                        style: TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  Text(
                                                    timeStr,
                                                    style: const TextStyle(
                                                      color: Colors.white54,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          if (jsonData != null)
                            AIChatSaveCardWidget(
                              jsonData: jsonData,
                              msgId: doc.id,
                              botType: widget
                                  .botType, // Передаем botType для сохранения состояния
                              themeColor: themeColor,
                              // QA FIX: Связываем локальный кэш и базу данных
                              isInitiallySaved:
                                  isActionCompleted ||
                                  _savedMessageIds.contains(doc.id),
                              onSaveSuccess: (id) =>
                                  setState(() => _savedMessageIds.add(id)),
                              onSendMessage: _triggerSendMessage,
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_isTyping)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  "Бот печатает...",
                  style: TextStyle(color: themeColor, fontSize: 12),
                ),
              ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedImage != null)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      height: 80,
                      width: 80,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedImage = null),
                      child: const CircleAvatar(
                        radius: 10,
                        child: Icon(Icons.close, size: 12),
                      ),
                    ),
                  ),
                ],
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _showAttachmentOptions,
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _controller,
                      keyboardType: TextInputType.multiline,
                      maxLines: 5,
                      minLines: 1,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Сообщение...",
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
