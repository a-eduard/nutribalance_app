import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';
import 'p2p_chat_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with AutomaticKeepAliveClientMixin {
  final P2PChatService _chat = P2PChatService();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<PublicProfile?>> _profileFutures = {};

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream;
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<PublicProfile> _results = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _chatsStream = _chat.myChatsStream();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.replaceAll('@', '').length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final res = await _chat.search(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = res;
        _searching = false;
      });
    });
  }

  Future<PublicProfile?> _profileFor(String uid) => _profileFutures.putIfAbsent(uid, () => _chat.profile(uid));

  void _openChat(String otherUid, String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: otherUid, otherUserName: name)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final bool showSearch = _query.replaceAll('@', '').length >= 2;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: EvaBackground(
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(EvaSpace.page, 16, EvaSpace.page, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EvaOverline('Общение'),
                      const SizedBox(height: 4),
                      Text('Комьюнити', style: theme.textTheme.displaySmall),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Поиск по имени или @никнейму',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                    FocusScope.of(context).unfocus();
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!showSearch) _EvaPinnedCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')))),
                    ],
                  ),
                ),
              ),
              if (showSearch) _buildSearchResults(theme) else _buildChats(theme),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme) {
    if (_searching) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_results.isEmpty) {
      return const SliverToBoxAdapter(
        child: EvaEmptyState(
          icon: Icons.person_search_outlined,
          title: 'Никого не нашли',
          subtitle: 'Проверьте написание имени или никнейма.',
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: EvaSpace.page - 8),
      sliver: SliverList.builder(
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final p = _results[i];
          return _ChatTile(
            name: p.name,
            photoUrl: p.photoUrl,
            subtitle: p.nickname.isNotEmpty ? '@${p.nickname}' : 'Написать сообщение',
            onTap: () => _openChat(p.uid, p.name),
          );
        },
      ),
    );
  }

  Widget _buildChats(ThemeData theme) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const SliverToBoxAdapter(
            child: EvaEmptyState(icon: Icons.cloud_off_rounded, title: 'Нет соединения', subtitle: 'Диалоги загрузятся, когда появится сеть.'),
          );
        }
        if (!snapshot.hasData) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EvaSpace.page, vertical: 12),
              child: Column(
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      EvaSkeleton(width: 52, height: 52, radius: 26),
                      SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [EvaSkeleton(width: 140), SizedBox(height: 8), EvaSkeleton(width: 200, height: 12)])),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }

        final String me = _chat.uid;
        final docs = snapshot.data!.docs.where((d) {
          final users = List<dynamic>.from(d.data()['users'] ?? const []);
          return users.any((u) => u != me);
        }).toList();

        DateTime? timeOf(Map<String, dynamic> data) {
          final dynamic t = data['lastUpdated'] ?? data['lastMessageTime'];
          return t is Timestamp ? t.toDate() : null;
        }

        docs.sort((a, b) {
          final ta = timeOf(a.data());
          final tb = timeOf(b.data());
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });

        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: EvaEmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Пока нет диалогов',
              subtitle: 'Найдите подругу по никнейму или напишите Еве — она всегда на связи.',
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page - 8, 8, EvaSpace.page - 8, 0),
          sliver: SliverList.builder(
            itemCount: docs.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: EvaOverline('Диалоги'),
                );
              }
              final doc = docs[i - 1];
              final data = doc.data();
              final List<dynamic> users = List<dynamic>.from(data['users'] ?? const []);
              final String otherId = users.firstWhere((u) => u != me, orElse: () => '').toString();
              final int unread = evaInt(data['unread_$me']);
              final String last = (data['lastMessage'] ?? '').toString();
              final bool mine = data['lastSenderId'] == me;
              final String preview = last.isEmpty ? 'Нет сообщений' : (mine ? 'Вы: $last' : last);
              final Map<String, dynamic>? info = (data['participant_info'] is Map) ? Map<String, dynamic>.from((data['participant_info'] as Map)[otherId] ?? {}) : null;
              final String? infoName = (info?['name'] as String?)?.trim();

              // ВАЖНО: больше НИКОГДА не удаляем чат, если профиль не загрузился.
              return FutureBuilder<PublicProfile?>(
                future: _profileFor(otherId),
                initialData: _chat.cachedProfile(otherId),
                builder: (context, ps) {
                  final String name = ps.data?.name ?? (infoName != null && infoName.isNotEmpty ? infoName : 'Собеседник');
                  final String photo = ps.data?.photoUrl ?? (info?['photoUrl'] ?? '').toString();
                  return _ChatTile(
                    name: name,
                    photoUrl: photo,
                    subtitle: preview,
                    time: ChatTime.listLabel(timeOf(data)),
                    unread: unread,
                    onTap: () {
                      _chat.markRead(doc.id);
                      _openChat(otherId, name);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _EvaPinnedCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EvaPinnedCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvaCard(
      onTap: onTap,
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ева', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text('ИИ-нутрициолог и заботливая подруга · 24/7',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final String subtitle;
  final String? time;
  final int unread;
  final VoidCallback onTap;

  const _ChatTile({required this.name, required this.subtitle, required this.onTap, this.photoUrl, this.time, this.unread = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasUnread = unread > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            EvaAvatar(name: name, photoUrl: photoUrl, size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                      ),
                      if (time != null && time!.isNotEmpty)
                        Text(
                          time!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasUnread ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: hasUnread ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          constraints: const BoxConstraints(minWidth: 22),
                          decoration: BoxDecoration(gradient: context.eva.hero, borderRadius: BorderRadius.circular(100)),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
