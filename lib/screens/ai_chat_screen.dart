import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../paywall_screen.dart';
import '../services/ai_service.dart';
import '../services/database_service.dart';
import '../services/push_notification_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/ai_chat_parser.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/eva_ui.dart';
import '../widgets/image_viewer.dart';
import 'shopping_list_screen.dart';

class AIChatScreen extends StatefulWidget {
  final String botType;
  final String? initialDisplayMessage;
  final String? initialTechnicalPrompt;

  const AIChatScreen({
    super.key,
    required this.botType,
    this.initialDisplayMessage,
    this.initialTechnicalPrompt,
  });

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _ParsedAiMessage {
  final String displayText;
  final Map<String, dynamic>? shoppingListData;
  final Map<String, dynamic>? jsonData;
  const _ParsedAiMessage(this.displayText, this.shoppingListData, this.jsonData);
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _savedMessageIds = {};
  final ImagePicker _picker = ImagePicker();
  static const int _maxImages = 5;

  bool _isTyping = false;
  List<File> _selectedImages = [];
  File? _selectedPdf;
  String? _pdfFileName;
  int _limit = 30;
  late Stream<QuerySnapshot> _chatStream;
  final Map<String, _ParsedAiMessage> _parsedCache = {};

  String? _lastFailedPrompt;

  @override
  void initState() {
    super.initState();
    _chatStream = _buildStream();
    _initChatAndContext();
  }

  Stream<QuerySnapshot> _buildStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('ai_chats_${widget.botType}')
        .orderBy('timestamp', descending: true)
        .limit(_limit)
        .snapshots();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    if (PushNotificationService.currentActiveChatId == widget.botType) {
      PushNotificationService.currentActiveChatId = null;
    }
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats_${widget.botType}');
  }

  Future<void> _initChatAndContext() async {
    PushNotificationService.currentActiveChatId = widget.botType;
    PushNotificationService().clearAllNotifications();
    final col = _col;
    if (col == null) return;

    try {
      QuerySnapshot<Map<String, dynamic>> historyCheck;
      try {
        historyCheck = await col.limit(1).get(const GetOptions(source: Source.cache));
        if (historyCheck.docs.isEmpty) throw Exception('empty cache');
      } catch (_) {
        historyCheck = await col.limit(1).get().timeout(const Duration(seconds: 8));
      }

      if (historyCheck.docs.isEmpty) {
        const String welcome = '''Привет! 🥰 Я Ева — твой личный ИИ-нутрициолог и заботливая подруга ✨

Вот что я умею:
- **Фото тарелки** — посчитаю калории и БЖУ.
- **Результаты анализов (PDF)** — объясню простым языком, без паники.
- **Любой вопрос** — поддержу, когда тревожно или нужен совет.

С чего начнём? 😉''';
        DatabaseService().saveBotChatMessage(widget.botType, welcome, 'ai');
      }
    } catch (e) {
      debugPrint("Ошибка инициализации чата: $e");
    }

    if (widget.initialDisplayMessage != null && widget.initialTechnicalPrompt != null) {
      _sendToEva(displayText: widget.initialDisplayMessage!, technicalPrompt: widget.initialTechnicalPrompt!);
    }
  }

  // ---------------------------------------------------------------------------
  // Вложения
  // ---------------------------------------------------------------------------

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(imageQuality: 72, maxWidth: 1600, maxHeight: 1600);
      if (pickedFiles.isEmpty || !mounted) return;
      if (pickedFiles.length > _maxImages) {
        EvaSnack.show(context, 'Можно выбрать максимум $_maxImages фото за раз', type: EvaSnackType.info);
      }
      setState(() {
        _selectedPdf = null;
        _pdfFileName = null;
        _selectedImages = pickedFiles.take(_maxImages).map((f) => File(f.path)).toList();
      });
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Не удалось открыть галерею', type: EvaSnackType.error);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 72, maxWidth: 1600, maxHeight: 1600);
      if (photo != null && mounted) {
        setState(() {
          _selectedPdf = null;
          _pdfFileName = null;
          _selectedImages = [File(photo.path)];
        });
      }
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Нет доступа к камере', type: EvaSnackType.error);
    }
  }

  Future<void> _pickPdf() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result == null || result.files.single.path == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 8 * 1024 * 1024) {
        EvaSnack.show(context, 'Файл слишком большой — максимум 8 МБ', type: EvaSnackType.error);
        return;
      }
      setState(() {
        _selectedPdf = File(file.path!);
        _pdfFileName = file.name;
        _selectedImages = [];
      });
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Не удалось открыть файл', type: EvaSnackType.error);
    }
  }

  void _showAttachmentOptions() {
    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EvaSheetHeader(title: 'Что отправим Еве?', subtitle: 'Фото блюда, этикетки или результаты анализов'),
            EvaOptionTile(title: 'Сделать фото', icon: Icons.photo_camera_outlined, selected: false, onTap: () {
              Navigator.pop(ctx);
              Future.delayed(const Duration(milliseconds: 250), _takePhoto);
            }),
            EvaOptionTile(title: 'Выбрать из галереи', subtitle: 'До $_maxImages фото', icon: Icons.photo_library_outlined, selected: false, onTap: () {
              Navigator.pop(ctx);
              Future.delayed(const Duration(milliseconds: 250), _pickImages);
            }),
            EvaOptionTile(title: 'Анализы (PDF)', subtitle: 'Расшифрую простым языком', icon: Icons.picture_as_pdf_outlined, selected: false, onTap: () {
              Navigator.pop(ctx);
              Future.delayed(const Duration(milliseconds: 250), _pickPdf);
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Отправка
  // ---------------------------------------------------------------------------

  void _triggerSendMessage(String text) {
    _controller.text = text;
    _sendMessage();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImages.isEmpty && _selectedPdf == null) return;
    if (_isTyping) return;

    final List<File> imagesToSend = List.of(_selectedImages);
    final File? pdfToSend = _selectedPdf;
    final String? pdfName = _pdfFileName;

    HapticFeedback.lightImpact();
    setState(() {
      _controller.clear();
      _selectedImages = [];
      _selectedPdf = null;
      _pdfFileName = null;
    });

    await _sendToEva(displayText: text, technicalPrompt: text, images: imagesToSend, pdf: pdfToSend, pdfName: pdfName);
  }

  Future<void> _sendToEva({
    required String displayText,
    required String technicalPrompt,
    List<File> images = const [],
    File? pdf,
    String? pdfName,
    bool addUserMessage = true,
  }) async {
    final col = _col;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (col == null || uid == null) return;

    setState(() => _isTyping = true);
    _scrollToBottom();

    try {
      final int serverVersion = await AIService.serverVersion();
      final int ts = DateTime.now().millisecondsSinceEpoch;
      final List<String> imageUrls = [];
      final List<String> imagePaths = [];
      final List<String> imagesBase64 = [];
      String? pdfUrl;
      String? pdfPath;
      String? pdfBase64;

      // Загружаем файлы в личную папку пользователя. Порядок фото сохраняется.
      if (images.isNotEmpty) {
        final results = await Future.wait(images.asMap().entries.map((entry) async {
          final path = 'users/$uid/ai_chat/${ts}_${entry.key}.jpg';
          final ref = FirebaseStorage.instance.ref().child(path);
          final bytes = await entry.value.readAsBytes();
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')).timeout(const Duration(seconds: 90));
          final url = await ref.getDownloadURL();
          return (path: path, url: url, b64: serverVersion >= 2 ? '' : base64Encode(bytes));
        }));
        for (final r in results) {
          imagePaths.add(r.path);
          imageUrls.add(r.url);
          if (r.b64.isNotEmpty) imagesBase64.add(r.b64);
        }
      }

      if (pdf != null) {
        final safeName = (pdfName ?? 'document.pdf').replaceAll(RegExp(r'[^a-zA-Z0-9.\-_]'), '_');
        pdfPath = 'users/$uid/ai_chat/${ts}_$safeName';
        final ref = FirebaseStorage.instance.ref().child(pdfPath);
        final bytes = await pdf.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'application/pdf')).timeout(const Duration(seconds: 90));
        pdfUrl = await ref.getDownloadURL();
        if (serverVersion < 2) pdfBase64 = base64Encode(bytes);
      }

      if (addUserMessage) {
        // Не ждём подтверждения сервера — сообщение сразу появляется в чате.
        col.add({
          'text': displayText,
          'role': 'user',
          'imageUrls': imageUrls,
          'pdfUrl': pdfUrl,
          'fileName': pdfName,
          'timestamp': FieldValue.serverTimestamp(),
          'isActionCompleted': false,
        }).then((_) {}, onError: (e) => debugPrint('user msg: $e'));
      }

      List<Map<String, String>> history = const [];
      try {
        history = await DatabaseService().getChatHistoryForAI(widget.botType).timeout(const Duration(seconds: 4));
      } catch (_) {}

      final reply = await AIService().ask(
        prompt: technicalPrompt.isEmpty ? (pdf != null ? 'Расшифруй мои анализы' : 'Посмотри фото') : technicalPrompt,
        botType: widget.botType,
        history: history,
        imagePaths: imagePaths,
        imagesBase64: imagesBase64,
        pdfPath: pdfPath,
        pdfBase64: pdfBase64,
        quota: 'message',
        saveReply: true,
      );

      if (!reply.savedByServer) {
        DatabaseService().saveBotChatMessage(widget.botType, reply.text, 'ai');
      }
      _lastFailedPrompt = null;
    } on EvaQuotaException {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true)));
    } catch (e) {
      debugPrint('Eva error: $e');
      _lastFailedPrompt = technicalPrompt;
      if (!mounted) return;
      EvaSnack.show(
        context,
        e is EvaUnavailableException ? e.message : 'Не удалось связаться с Евой. Проверь соединение.',
        type: EvaSnackType.error,
        duration: const Duration(seconds: 6),
        action: technicalPrompt.isEmpty
            ? null
            : SnackBarAction(
                label: 'Повторить',
                onPressed: () {
                  final p = _lastFailedPrompt;
                  if (p != null) _sendToEva(displayText: p, technicalPrompt: p, addUserMessage: false);
                },
              ),
      );
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  // ---------------------------------------------------------------------------
  // Разбор ответа Евы (JSON-действия, список покупок)
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      String jsonString = text;
      final String tripleTick = String.fromCharCode(96) * 3;
      final exp = RegExp(tripleTick + r"(?:json)?\s*([\s\S]*?)\s*" + tripleTick, caseSensitive: false);
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
      final decoded = jsonDecode(jsonString);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      return null;
    }
  }

  String _cleanText(String text, Map<String, dynamic>? jsonData) {
    if (jsonData == null) return text.trim();

    final String tripleTick = String.fromCharCode(96) * 3;
    String stripped = text.replaceAll(RegExp(tripleTick + r"(?:json)?\s*([\s\S]*?)\s*" + tripleTick, caseSensitive: false), '').trim();

    final startIdx = stripped.indexOf('{');
    final endIdx = stripped.lastIndexOf('}');
    if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
      final String possibleJson = stripped.substring(startIdx, endIdx + 1);
      try {
        jsonDecode(possibleJson);
        stripped = stripped.replaceRange(startIdx, endIdx + 1, '').trim();
      } catch (_) {}
    }

    if (stripped.isEmpty && jsonData['coach_message'] != null && jsonData['coach_message'].toString().isNotEmpty) {
      return jsonData['coach_message'].toString().trim();
    }
    return stripped;
  }

  _ParsedAiMessage _parse(String id, String rawText, bool isUser) {
    final cached = _parsedCache[id];
    if (cached != null && !id.startsWith('_')) return cached;
    if (isUser) return _ParsedAiMessage(rawText, null, null);

    String clean = rawText.replaceAll(RegExp(r'<thinking>[\s\S]*?<\/thinking>'), '').trim();
    Map<String, dynamic>? shopping;

    final shopExp = RegExp(r'\[SHOPP?ING_LIST\]([\s\S]*?)(?:\[\/SHOPP?ING_LIST\]|$)', caseSensitive: false);
    final shopMatch = shopExp.firstMatch(clean);
    if (shopMatch != null) {
      String jsonStr = shopMatch.group(1) ?? '';
      final String tick = String.fromCharCode(96);
      jsonStr = jsonStr.replaceAll(RegExp(tick + tick + tick + r'(?:json)?|' + tick + tick + tick), '').trim();
      final jsonBlockMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonBlockMatch != null) jsonStr = jsonBlockMatch.group(0)!;
      if (jsonStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic>) shopping = decoded;
        } catch (e) {
          debugPrint('Ошибка парсинга корзины Евы: $e');
        }
      }
      clean = clean.replaceAll(shopExp, '').trim();
    }
    final String tick = String.fromCharCode(96);
    clean = clean.replaceAll(RegExp(tick + tick + tick + r'(?:json)?\s*'), '').trim();
    clean = clean.replaceAll(RegExp(r'\[\/?SHOPP?ING_LIST\]', caseSensitive: false), '').trim();

    final jsonData = _tryParseJson(clean);
    final parsed = _ParsedAiMessage(_cleanText(clean, jsonData), shopping, jsonData);
    _parsedCache[id] = parsed;
    return parsed;
  }

  // ---------------------------------------------------------------------------
  // Действия с сообщением
  // ---------------------------------------------------------------------------

  void _showMessageActions(String docId, String text, String? firstImage) {
    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EvaSheetHandle(),
            if (text.isNotEmpty)
              EvaMenuTile(
                icon: Icons.copy_rounded,
                title: 'Копировать текст',
                trailing: const SizedBox.shrink(),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  EvaSnack.show(context, 'Скопировано', type: EvaSnackType.success);
                },
              ),
            EvaMenuTile(
              icon: Icons.delete_outline_rounded,
              title: 'Удалить сообщение',
              destructive: true,
              trailing: const SizedBox.shrink(),
              onTap: () {
                Navigator.pop(ctx);
                DatabaseService().deleteBotChatMessage(widget.botType, docId, firstImage).catchError((e) => debugPrint('$e'));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        title: Row(
          children: [
            const _EvaAvatar(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ева', style: theme.textTheme.titleLarge),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _isTyping ? 'печатает…' : 'ИИ-нутрициолог · на связи',
                      key: ValueKey(_isTyping),
                      style: theme.textTheme.bodySmall?.copyWith(color: _isTyping ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Список покупок',
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: EvaBackground(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _chatStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EvaEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Не удалось загрузить чат',
                      subtitle: 'Проверьте соединение.',
                      actionLabel: 'Обновить',
                      onAction: () => setState(() => _chatStream = _buildStream()),
                    );
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final docs = snapshot.data!.docs;
                  final bool showSuggestions = docs.length <= 1 && !_isTyping;
                  final int extra = (_isTyping ? 1 : 0) + (docs.length >= _limit ? 1 : 0);

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                    itemCount: docs.length + extra + (showSuggestions ? 1 : 0),
                    itemBuilder: (context, rawIndex) {
                      int index = rawIndex;
                      if (showSuggestions) {
                        if (index == 0) return _buildSuggestions(theme);
                        index -= 1;
                      }
                      if (_isTyping) {
                        if (index == 0) return _buildTypingBubble(theme);
                        index -= 1;
                      }
                      if (index >= docs.length) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              _limit += 30;
                              _chatStream = _buildStream();
                            }),
                            icon: const Icon(Icons.history_rounded, size: 18),
                            label: const Text('Показать ранние сообщения'),
                          ),
                        );
                      }
                      return _buildMessage(docs, index, theme);
                    },
                  );
                },
              ),
            ),
            ChatInputBar(
              controller: _controller,
              onSend: _sendMessage,
              onAttach: _showAttachmentOptions,
              busy: _isTyping,
              hint: 'Спроси Еву…',
              allowEmptySend: _selectedImages.isNotEmpty || _selectedPdf != null,
              top: _buildAttachmentPreview(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(List<QueryDocumentSnapshot> docs, int index, ThemeData theme) {
    final doc = docs[index];
    final data = doc.data() as Map<String, dynamic>;
    final bool isUser = data['role'] == 'user';
    final String rawText = (data['text'] ?? '').toString();
    final bool isActionCompleted = data['isActionCompleted'] == true;
    final parsed = _parse(doc.id, rawText, isUser);

    final List<String> imageUrls = (data['imageUrls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? <String>[];
    final String? oldImageUrl = data['imageUrl'] as String?;
    if (imageUrls.isEmpty && oldImageUrl != null && oldImageUrl.isNotEmpty) imageUrls.add(oldImageUrl);
    final String? pdfUrl = data['pdfUrl'] as String?;
    final String pdfName = data['fileName'] as String? ?? 'Анализы.pdf';

    final Timestamp? ts = data['timestamp'] as Timestamp?;
    final DateTime time = ts?.toDate() ?? DateTime.now();

    final QueryDocumentSnapshot? older = index + 1 < docs.length ? docs[index + 1] : null;
    DateTime? olderTime;
    if (older != null) {
      final dynamic ot = (older.data() as Map<String, dynamic>)['timestamp'];
      if (ot is Timestamp) olderTime = ot.toDate();
    }
    final bool newDay = olderTime == null || !ChatTime.sameDay(olderTime, time);
    final bool hasBubble = parsed.displayText.isNotEmpty || imageUrls.isNotEmpty || pdfUrl != null;
    final bool isError = data['isError'] == true;

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (newDay && ts != null) ChatDaySeparator(day: time),
        if (hasBubble)
          GestureDetector(
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _showMessageActions(doc.id, parsed.displayText, imageUrls.isNotEmpty ? imageUrls.first : null);
            },
            child: Row(
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  const Padding(padding: EdgeInsets.only(bottom: 2), child: _EvaAvatar(size: 28)),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: ChatBubble(
                    isMe: isUser,
                    time: ts != null ? DateFormat('HH:mm').format(time) : '',
                    maxWidthFactor: 0.8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (imageUrls.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(bottom: parsed.displayText.isNotEmpty ? 8 : 2),
                            child: imageUrls.length == 1 ? _buildSingleImage(imageUrls.first, doc.id) : _buildImageGrid(imageUrls),
                          ),
                        if (pdfUrl != null)
                          Container(
                            margin: EdgeInsets.only(bottom: parsed.displayText.isNotEmpty ? 8 : 0),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isUser ? Colors.white.withValues(alpha: 0.18) : context.eva.fieldFill,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded, color: isUser ? Colors.white : theme.colorScheme.error, size: 26),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(pdfName,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelLarge?.copyWith(color: isUser ? Colors.white : theme.colorScheme.onSurface)),
                                ),
                              ],
                            ),
                          ),
                        if (parsed.displayText.isNotEmpty)
                          isUser
                              ? Text(parsed.displayText, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, fontSize: 15.5, height: 1.4))
                              : EvaMarkdownText(
                                  parsed.displayText,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: 15.5,
                                    color: isError ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (parsed.shoppingListData != null)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: RecipeShoppingCardWidget(data: parsed.shoppingListData!, msgId: doc.id),
          ),
        if (parsed.jsonData != null)
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: AIChatSaveCardWidget(
              jsonData: parsed.jsonData!,
              msgId: doc.id,
              botType: widget.botType,
              themeColor: theme.colorScheme.primary,
              imageUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
              isInitiallySaved: isActionCompleted || _savedMessageIds.contains(doc.id),
              onSaveSuccess: (id) => setState(() => _savedMessageIds.add(id)),
              onSendMessage: _triggerSendMessage,
            ),
          ),
      ],
    );
  }

  Widget _buildTypingBubble(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _EvaAvatar(size: 28),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: context.eva.hairline),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(6),
              ),
            ),
            child: const EvaTypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(ThemeData theme) {
    final suggestions = <(String, String, String)>[
      ('🥗', 'Что приготовить на ужин?', 'Предложи лёгкий и сытный ужин на сегодня с учётом моей нормы'),
      ('🌸', 'Питание в мою фазу цикла', 'Что мне лучше есть в текущей фазе цикла и почему?'),
      ('😴', 'Как улучшить сон?', 'Какие продукты и привычки помогут мне лучше спать?'),
      ('📸', 'Посчитать калории по фото', ''),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 10), child: EvaOverline('Можно начать с этого')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((s) {
              return EvaChoiceChip(
                label: s.$2,
                emoji: s.$1,
                selected: false,
                onTap: () {
                  if (s.$3.isEmpty) {
                    _showAttachmentOptions();
                  } else {
                    _triggerSendMessage(s.$3);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget? _buildAttachmentPreview(ThemeData theme) {
    if (_selectedImages.isEmpty && _selectedPdf == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _selectedPdf != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: context.eva.fieldFill, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_pdfFileName ?? 'Документ.pdf', overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _selectedPdf = null;
                      _pdfFileName = null;
                    }),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(_selectedImages[i], width: 78, height: 78, fit: BoxFit.cover, cacheWidth: 240),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedImages.removeAt(i)),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSingleImage(String url, String id) {
    return GestureDetector(
      onTap: () => EvaImageViewer.open(context, url, heroTag: 'ai_$id'),
      child: Hero(
        tag: 'ai_$id',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: url,
            width: 220,
            fit: BoxFit.cover,
            memCacheWidth: 660,
            placeholder: (c, u) => const SizedBox(width: 220, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorWidget: (c, u, e) => const SizedBox(width: 220, height: 160, child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<String> urls) {
    return SizedBox(
      width: 232,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: urls.length == 2 || urls.length == 4 ? 2 : 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: urls.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => EvaImageViewer.open(context, urls[index]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: urls[index],
              fit: BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (c, u) => Container(color: Colors.black12),
            ),
          ),
        ),
      ),
    );
  }
}

class _EvaAvatar extends StatelessWidget {
  final double size;
  const _EvaAvatar({this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: context.eva.hero, shape: BoxShape.circle),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5),
    );
  }
}

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
    final theme = Theme.of(context);
    final items = widget.data['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(4).toList();
    final extraCount = items.length - displayItems.length;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4, right: 24),
      child: EvaCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EvaIconBubble(icon: Icons.shopping_bag_outlined, color: context.eva.gold, size: 38, iconSize: 19),
                const SizedBox(width: 12),
                Expanded(child: Text('Ингредиенты для рецепта', style: theme.textTheme.titleMedium)),
              ],
            ),
            const SizedBox(height: 14),
            ...displayItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${item is Map ? item['name'] : item}', style: theme.textTheme.bodyMedium)),
                    if (item is Map && (item['amount'] ?? '').toString().isNotEmpty)
                      Text('${item['amount']}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            if (extraCount > 0)
              Text('…и ещё $extraCount', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 14),
            _isAdded
                ? EvaSecondaryButton(
                    label: 'Открыть список покупок',
                    icon: Icons.check_rounded,
                    height: 48,
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen())),
                  )
                : EvaPrimaryButton(
                    label: 'Добавить в «Мой список»',
                    icon: Icons.add_rounded,
                    height: 48,
                    loading: _isLoading,
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _isLoading = true);
                      try {
                        await DatabaseService().addIngredientsToShoppingList(items);
                        if (!mounted) return;
                        setState(() => _isAdded = true);
                        EvaSnack.showOn(messenger, theme, 'Ингредиенты добавлены в список покупок 🛒', type: EvaSnackType.success);
                      } catch (e) {
                        if (mounted) EvaSnack.showOn(messenger, theme, 'Не удалось добавить. Попробуйте ещё раз.', type: EvaSnackType.error);
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
