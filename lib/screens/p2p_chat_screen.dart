import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/chat_service.dart';
import '../services/local_notification_service.dart';
import '../services/push_notification_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/eva_ui.dart';
import '../widgets/image_viewer.dart';

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
  final P2PChatService _chat = P2PChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  late final String _chatId;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _chatDocStream;

  bool _isUploading = false;
  bool _offline = false;
  DateTime? _cacheSince;
  Timer? _staleTimer;
  Timer? _pollTimer;
  final Map<String, ChatMessage> _serverFallback = {};
  final Set<String> _deliveredViaServer = {};
  final Set<String> _failed = {};
  String _lastSeenIncomingId = '';
  PublicProfile? _other;

  String get _collection => widget.customCollection ?? 'chats';
  String get _me => _chat.uid;

  @override
  void initState() {
    super.initState();
    _chatId = P2PChatService.chatIdFor(_me, widget.otherUserId);
    _messagesStream = _chat.messagesStream(_chatId, collection: _collection);
    _chatDocStream = _chat.chatDocStream(_chatId, collection: _collection);
    PushNotificationService.currentActiveChatId = _chatId;
    LocalNotificationService().dismissDisplayed();
    _chat.markRead(_chatId, collection: _collection);
    _chat.profile(widget.otherUserId).then((p) {
      if (mounted && p != null) setState(() => _other = p);
    });
  }

  @override
  void dispose() {
    _chat.markRead(_chatId, collection: _collection);
    if (PushNotificationService.currentActiveChatId == _chatId) {
      PushNotificationService.currentActiveChatId = null;
    }
    _staleTimer?.cancel();
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Состояние соединения и резервный опрос сервера
  // ---------------------------------------------------------------------------

  void _onSnapshotMeta(bool fromCache) {
    if (!fromCache) {
      _cacheSince = null;
      _staleTimer?.cancel();
      _pollTimer?.cancel();
      _pollTimer = null;
      if (_offline) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _offline = false);
        });
      }
      return;
    }
    _cacheSince ??= DateTime.now();
    _staleTimer ??= Timer(const Duration(seconds: 6), () {
      _staleTimer = null;
      if (!mounted || _cacheSince == null) return;
      setState(() => _offline = true);
      _startPolling();
    });
  }

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollOnce();
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    try {
      final list = await _chat.fetchViaServer(_chatId, collection: _collection);
      if (!mounted) return;
      setState(() {
        for (final m in list) {
          _serverFallback[m.id] = m;
        }
      });
    } catch (e) {
      debugPrint('poll: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Отправка
  // ---------------------------------------------------------------------------

  void _send({String? imageUrl}) {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null) return;
    HapticFeedback.lightImpact();
    _messageController.clear();

    final result = _chat.sendMessage(otherUid: widget.otherUserId, text: text, imageUrl: imageUrl, collection: _collection);
    result.delivery.then((state) {
      if (!mounted) return;
      if (state == ChatDeliveryState.sent && _offline) {
        setState(() => _deliveredViaServer.add(result.messageId));
      } else if (state == ChatDeliveryState.failed) {
        setState(() => _failed.add(result.messageId));
        EvaSnack.show(context, 'Не удалось отправить сообщение. Проверьте соединение.', type: EvaSnackType.error);
      }
    });

    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final ImageSource? source = await EvaSheet.show<ImageSource>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EvaSheetHeader(title: 'Отправить фото'),
            EvaOptionTile(title: 'Сделать фото', icon: Icons.photo_camera_outlined, selected: false, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            EvaOptionTile(title: 'Выбрать из галереи', icon: Icons.photo_library_outlined, selected: false, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 72, maxWidth: 1600, maxHeight: 1600);
      if (picked == null) return;
      setState(() => _isUploading = true);
      final bytes = await picked.readAsBytes();
      final url = await _chat.uploadImage(otherUid: widget.otherUserId, bytes: bytes);
      if (url != null) _send(imageUrl: url);
    } catch (e) {
      if (!mounted) return;
      EvaSnack.show(context, 'Не удалось загрузить фото. Попробуйте ещё раз.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Действия с сообщением
  // ---------------------------------------------------------------------------

  void _showMessageActions(ChatMessage m) {
    final bool isMe = m.senderId == _me;
    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EvaSheetHandle(),
            if (m.text.isNotEmpty)
              EvaMenuTile(
                icon: Icons.copy_rounded,
                title: 'Копировать',
                trailing: const SizedBox.shrink(),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.text));
                  Navigator.pop(ctx);
                  EvaSnack.show(context, 'Текст скопирован', type: EvaSnackType.success);
                },
              ),
            if (isMe && !m.hasImage)
              EvaMenuTile(
                icon: Icons.edit_rounded,
                title: 'Редактировать',
                trailing: const SizedBox.shrink(),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(m);
                },
              ),
            if (isMe)
              EvaMenuTile(
                icon: Icons.delete_outline_rounded,
                title: 'Удалить',
                destructive: true,
                trailing: const SizedBox.shrink(),
                onTap: () {
                  Navigator.pop(ctx);
                  _chat.deleteMessage(_chatId, m.id, imageUrl: m.imageUrl, collection: _collection);
                  setState(() => _serverFallback.remove(m.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(ChatMessage m) {
    final controller = TextEditingController(text: m.text);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Редактировать'),
        content: TextField(controller: controller, maxLines: null, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isNotEmpty && t != m.text) {
                _chat.editMessage(_chatId, m.id, t, collection: _collection);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    final String name = _other?.name ?? widget.otherUserName;
    final String subtitle = _offline
        ? 'ожидание сети…'
        : (_other?.nickname.isNotEmpty == true ? '@${_other!.nickname}' : 'личные сообщения');
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      title: Row(
        children: [
          EvaAvatar(name: name, photoUrl: _other?.photoUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    style: theme.textTheme.bodySmall?.copyWith(color: _offline ? context.eva.warning : theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: _isUploading
          ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
          : null,
    );
  }

  Widget _statusIcon(ChatMessage m, DateTime? otherLastRead) {
    final Color c = Colors.white.withValues(alpha: 0.85);
    if (_failed.contains(m.id)) return const Icon(Icons.error_outline_rounded, size: 14, color: Colors.white);
    if (m.pending && !_deliveredViaServer.contains(m.id)) return Icon(Icons.schedule_rounded, size: 13, color: c);
    if (otherLastRead != null && !m.time.isAfter(otherLastRead)) return Icon(Icons.done_all_rounded, size: 15, color: c);
    return Icon(Icons.check_rounded, size: 15, color: c);
  }

  Widget _bubbleContent(ChatMessage m, bool isMe, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.hasImage)
          Padding(
            padding: EdgeInsets.only(bottom: m.text.isNotEmpty ? 8 : 2),
            child: GestureDetector(
              onTap: () => EvaImageViewer.open(context, m.imageUrl!, heroTag: 'p2p_${m.id}'),
              child: Hero(
                tag: 'p2p_${m.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: m.imageUrl!,
                    width: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const SizedBox(width: 220, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                    errorWidget: (_, __, ___) => const SizedBox(width: 220, height: 160, child: Center(child: Icon(Icons.broken_image_outlined, size: 36))),
                  ),
                ),
              ),
            ),
          ),
        if (m.text.isNotEmpty)
          Text(m.text, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.5, height: 1.35, color: isMe ? Colors.white : theme.colorScheme.onSurface)),
        if (m.edited)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('изменено', style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, color: isMe ? Colors.white70 : theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          EvaStatusBanner(
            visible: _offline,
            text: 'Нет связи с сервером. Сообщения сохранены и отправятся автоматически.',
            onTap: _pollOnce,
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _chatDocStream,
              builder: (context, chatSnap) {
                DateTime? otherLastRead;
                final dynamic lr = chatSnap.data?.data()?['lastRead_${widget.otherUserId}'];
                if (lr is Timestamp) otherLastRead = lr.toDate();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _messagesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return EvaEmptyState(
                        icon: Icons.lock_outline_rounded,
                        title: 'Не удалось открыть чат',
                        subtitle: 'Проверьте соединение и попробуйте ещё раз.',
                        actionLabel: 'Обновить',
                        onAction: () => setState(() {}),
                      );
                    }
                    if (!snapshot.hasData && _serverFallback.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasData) _onSnapshotMeta(snapshot.data!.metadata.isFromCache);

                    // Объединяем поток Firestore и резервные данные сервера.
                    final Map<String, ChatMessage> byId = Map.of(_serverFallback);
                    for (final d in snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
                      byId[d.id] = ChatMessage.fromDoc(d);
                    }
                    final List<ChatMessage> messages = byId.values.toList()..sort((a, b) => b.time.compareTo(a.time));

                    // Отмечаем прочитанным, если пришло новое входящее.
                    final Iterable<ChatMessage> incoming = messages.where((m) => m.senderId != _me);
                    final ChatMessage? newestIncoming = incoming.isEmpty ? null : incoming.first;
                    if (newestIncoming != null && newestIncoming.id != _lastSeenIncomingId) {
                      _lastSeenIncomingId = newestIncoming.id;
                      _chat.markRead(_chatId, collection: _collection);
                    }

                    if (messages.isEmpty) {
                      return EvaEmptyState(
                        icon: Icons.waving_hand_outlined,
                        title: 'Начните диалог',
                        subtitle: 'Напишите первое сообщение — ${widget.otherUserName} получит уведомление.',
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final bool isMe = m.senderId == _me;
                        final ChatMessage? older = index + 1 < messages.length ? messages[index + 1] : null;
                        final bool newDay = older == null || !ChatTime.sameDay(older.time, m.time);
                        final bool compact = older != null && !newDay && older.senderId == m.senderId && m.time.difference(older.time).inMinutes < 3;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (newDay) ChatDaySeparator(day: m.time),
                            GestureDetector(
                              onLongPress: () {
                                HapticFeedback.mediumImpact();
                                _showMessageActions(m);
                              },
                              child: ChatBubble(
                                isMe: isMe,
                                compactTop: compact,
                                time: DateFormat('HH:mm').format(m.time),
                                status: isMe ? _statusIcon(m, otherLastRead) : null,
                                padding: m.hasImage && m.text.isEmpty ? const EdgeInsets.fromLTRB(6, 6, 10, 6) : const EdgeInsets.fromLTRB(14, 10, 14, 8),
                                child: _bubbleContent(m, isMe, theme),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          ChatInputBar(
            controller: _messageController,
            onSend: () => _send(),
            onAttach: _pickAndUploadImage,
            busy: _isUploading,
          ),
        ],
      ),
    );
  }
}
