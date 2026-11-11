// Челленджи с подругами: готовые челленджи на 7 дней, вход по коду,
// ежедневная отметка и таблица участниц. Сервер — callable `challenge`.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/analytics_service.dart';
import '../../theme/eva_colors.dart';
import '../../widgets/eva_ui.dart';

HttpsCallable get _fn => FirebaseFunctions.instance.httpsCallable('challenge', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)));

String _errorText(Object e) {
  if (e is FirebaseFunctionsException) {
    return switch (e.code) {
      'not-found' => e.message ?? 'Не найдено',
      'failed-precondition' || 'already-exists' => e.message ?? 'Не получилось',
      _ => 'Не удалось связаться с сервером. Попробуй позже.',
    };
  }
  return 'Нет соединения. Попробуй позже.';
}

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> _templates = const [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  final TextEditingController _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    Analytics.event('challenges_open');
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty && _templates.isEmpty;
      _error = null;
    });
    try {
      final res = await _fn.call({'action': 'list'});
      final Map data = res.data is Map ? res.data as Map : const {};
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _templates = (data['templates'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  Future<void> _run(Map<String, dynamic> payload, String event) async {
    setState(() => _busy = true);
    try {
      final res = await _fn.call(payload);
      final Map<String, dynamic> c = Map<String, dynamic>.from(res.data as Map);
      Analytics.event(event, {'template': (c['template'] ?? '').toString()});
      if (!mounted) return;
      _code.clear();
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ChallengeDetailScreen(initial: c, justCreated: event == 'challenge_create')));
      _load();
    } catch (e) {
      if (mounted) EvaSnack.show(context, _errorText(e), type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createCustom() async {
    final Map<String, dynamic>? params = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _CustomChallengeSheet(),
    );
    if (params == null || !mounted) return;
    _run({'action': 'create', 'template': 'custom', ...params}, 'challenge_create');
  }

  void _confirmCreate(Map<String, dynamic> t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${t['emoji']} ${t['title']}'),
        content: Text('7 дней, каждый день: ${t['task']}.\n\nПосле создания поделись кодом с подругами — вы будете отмечаться и видеть успехи друг друга.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _run({'action': 'create', 'template': t['key']}, 'challenge_create');
            },
            child: const Text('Начать сегодня'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _items.where((c) => c['status'] != 'finished').toList();
    final finished = _items.where((c) => c['status'] == 'finished').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Челленджи'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _templates.isEmpty
                ? EvaEmptyState(icon: PhosphorIconsLight.trophy, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                      children: [
                        EvaCard(
                          gradient: context.eva.hero,
                          border: false,
                          padding: const EdgeInsets.all(22),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            EvaOverline('С подругами веселее', color: Colors.white.withValues(alpha: 0.85)),
                            const SizedBox(height: 8),
                            Text('Одна полезная привычка каждый день 💪', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                            const SizedBox(height: 8),
                            Text('Выбери челлендж, позови подруг по коду и отмечайтесь каждый день.',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                          ]),
                        ),
                        if (active.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          const EvaOverline('Мои челленджи'),
                          const SizedBox(height: 8),
                          for (final c in active) _myTile(theme, c),
                        ],
                        const SizedBox(height: 20),
                        const EvaOverline('Подруга позвала? Введи код'),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _code,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(hintText: 'Например, CH7K2PQX'),
                              onSubmitted: (_) => _join(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _join, child: const Text('Войти'))),
                        ]),
                        const SizedBox(height: 22),
                        const EvaOverline('Начать новый'),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: EvaCard(
                            onTap: _busy ? null : _createCustom,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            child: Row(children: [
                              EvaIconBubble(icon: PhosphorIconsLight.pencilSimpleLine, color: theme.colorScheme.primary, size: 40, iconSize: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Свой челлендж', style: theme.textTheme.titleMedium),
                                  Text('Придумай привычку, срок и позови подруг', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                ]),
                              ),
                              Icon(PhosphorIconsLight.plusCircle, color: theme.colorScheme.primary),
                            ]),
                          ),
                        ),
                        for (final t in _templates)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: EvaCard(
                              onTap: _busy ? null : () => _confirmCreate(t),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Row(children: [
                                Text('${t['emoji']}', style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${t['title']}', style: theme.textTheme.titleMedium),
                                    Text('${t['task']}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  ]),
                                ),
                                Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary),
                              ]),
                            ),
                          ),
                        if (finished.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const EvaOverline('Завершённые'),
                          const SizedBox(height: 8),
                          for (final c in finished) _myTile(theme, c),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  void _join() {
    final String code = _code.text.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    _run({'action': 'join', 'code': code}, 'challenge_join');
  }

  Widget _myTile(ThemeData theme, Map<String, dynamic> c) {
    final bool active = c['status'] == 'active';
    final String sub = switch ((c['status'] ?? '').toString()) {
      'finished' => 'Завершён',
      'soon' => 'Скоро старт',
      _ => 'День ${c['dayNum']} из ${c['days']} · ${(c['members'] as List?)?.length ?? 1} участн.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: EvaCard(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ChallengeDetailScreen(initial: c)));
          _load();
        },
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          Text('${c['emoji']}', style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['title']}', style: theme.textTheme.titleMedium),
              Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          if (active && c['checkedToday'] == true)
            Icon(Icons.check_circle_rounded, color: context.eva.success)
          else if (active)
            EvaPill(text: 'отметиться', color: theme.colorScheme.primary),
        ]),
      ),
    );
  }
}

class ChallengeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initial;
  final bool justCreated;
  const ChallengeDetailScreen({super.key, required this.initial, this.justCreated = false});

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  late Map<String, dynamic> _c = widget.initial;
  bool _busy = false;

  String get _id => (_c['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final res = await _fn.call({'action': 'get', 'id': _id});
      if (mounted) setState(() => _c = Map<String, dynamic>.from(res.data as Map));
    } catch (_) {}
  }

  Future<void> _checkin() async {
    setState(() => _busy = true);
    try {
      final res = await _fn.call({'action': 'checkin', 'id': _id});
      Analytics.event('challenge_checkin', {'template': (_c['template'] ?? '').toString()});
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _c = Map<String, dynamic>.from(res.data as Map));
      EvaSnack.show(context, 'Отмечено! Так держать 💪', type: EvaSnackType.success);
    } catch (e) {
      if (mounted) EvaSnack.show(context, _errorText(e), type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _invite =>
      'Давай вместе! ${_c['emoji']} Челлендж «${_c['title']}» на ${evaInt(_c['days'], 7)} дней в «Моей Еве».\n'
      'Открой Еву → вкладка «Ева» → «Челленджи» и введи код ${_c['code']}\n'
      'https://www.rustore.ru/catalog/app/com.eduard.nutribalance?utm_source=challenge&utm_medium=app&utm_campaign=challenge';

  Future<void> _share() async {
    Analytics.event('challenge_share');
    try {
      await Share.share(_invite, subject: 'Челлендж в «Моей Еве»');
    } catch (_) {
      Clipboard.setData(ClipboardData(text: _invite));
      if (mounted) EvaSnack.show(context, 'Приглашение скопировано', type: EvaSnackType.success);
    }
  }

  Future<void> _leave() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти из челленджа?'),
        content: const Text('Твои отметки удалятся. Вернуться можно будет по коду, пока челлендж идёт.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _fn.call({'action': 'leave', 'id': _id});
      Analytics.event('challenge_leave');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) EvaSnack.show(context, _errorText(e), type: EvaSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String status = (_c['status'] ?? '').toString();
    final bool active = status == 'active';
    final bool checked = _c['checkedToday'] == true;
    final List members = _c['members'] as List? ?? const [];
    final int days = evaInt(_c['days'], 7);
    return Scaffold(
      appBar: AppBar(
        title: Text('${_c['emoji']} ${_c['title']}'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [IconButton(icon: const Icon(PhosphorIconsLight.signOut), tooltip: 'Выйти', onPressed: _leave)],
      ),
      body: EvaBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
            children: [
              EvaCard(
                gradient: context.eva.hero,
                border: false,
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EvaOverline(active ? 'День ${_c['dayNum']} из $days' : (status == 'finished' ? 'Челлендж завершён' : 'Скоро старт'),
                      color: Colors.white.withValues(alpha: 0.85)),
                  const SizedBox(height: 8),
                  Text('${_c['task']}', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                ]),
              ),
              const SizedBox(height: 14),
              if (active)
                EvaPrimaryButton(
                  label: checked ? 'Сегодня отмечено ✓' : 'Я сделала это сегодня',
                  icon: checked ? null : Icons.check_rounded,
                  loading: _busy,
                  onPressed: checked || _busy ? null : _checkin,
                ),
              if (widget.justCreated) ...[
                const SizedBox(height: 14),
                Text('Челлендж создан! Позови подруг — вместе проще дойти до конца.', style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 14),
              EvaCard(
                child: Column(children: [
                  const EvaOverline('Код для подруг'),
                  const SizedBox(height: 8),
                  SelectableText('${_c['code']}',
                      style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Позвать подруг')),
                ]),
              ),
              const SizedBox(height: 14),
              EvaCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EvaOverline('Участницы · ${members.length}'),
                  const SizedBox(height: 12),
                  for (int i = 0; i < members.length; i++) _memberRow(theme, Map<String, dynamic>.from(members[i] as Map), i, days),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberRow(ThemeData theme, Map<String, dynamic> m, int place, int days) {
    final List marks = m['marks'] as List? ?? const [];
    final String medal = place == 0 && evaInt(m['done']) > 0 ? '👑 ' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Expanded(
          child: Text('$medal${m['name']}${m['me'] == true ? ' (ты)' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: m['me'] == true ? FontWeight.w700 : null)),
        ),
        if (days > 7)
          // Длинный челлендж: вместо 14–30 точек — полоска прогресса.
          Container(
            margin: const EdgeInsets.only(left: 8),
            width: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: days == 0 ? 0 : (evaInt(m['done']) / days).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          )
        else
        for (int d = 0; d < days; d++)
          Container(
            margin: const EdgeInsets.only(left: 4),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: d < marks.length && marks[d] == true ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
        const SizedBox(width: 8),
        SizedBox(width: 28, child: Text('${m['done']}/$days', textAlign: TextAlign.right, style: theme.textTheme.labelSmall)),
      ]),
    );
  }
}

/// Шторка «Свой челлендж»: эмодзи, название, задание на день и срок.
class _CustomChallengeSheet extends StatefulWidget {
  const _CustomChallengeSheet();

  @override
  State<_CustomChallengeSheet> createState() => _CustomChallengeSheetState();
}

class _CustomChallengeSheetState extends State<_CustomChallengeSheet> {
  static const List<String> _emojis = ['⭐', '💪', '🧘‍♀️', '📚', '🥗', '🏃‍♀️', '💧', '🌿', '😴', '🍎', '✨', '❤️'];
  static const List<int> _durations = [7, 14, 21, 30];
  final TextEditingController _title = TextEditingController();
  final TextEditingController _task = TextEditingController();
  String _emoji = '⭐';
  int _days = 7;

  @override
  void dispose() {
    _title.dispose();
    _task.dispose();
    super.dispose();
  }

  bool get _valid => _title.text.trim().length >= 3 && _task.text.trim().length >= 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EvaSheetHeader(title: 'Свой челлендж', subtitle: 'Одна привычка каждый день — с подругами веселее'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in _emojis)
                    GestureDetector(
                      onTap: () => setState(() => _emoji = e),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: e == _emoji ? theme.colorScheme.primary.withValues(alpha: 0.22) : theme.colorScheme.onSurface.withValues(alpha: 0.05),
                          border: Border.all(color: e == _emoji ? theme.colorScheme.primary : Colors.transparent, width: 1.5),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Название', hintText: 'Например, «Утренняя растяжка»', counterText: ''),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _task,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Что делаем каждый день', hintText: 'Например, «10 минут растяжки после сна»', counterText: ''),
              ),
              const SizedBox(height: 16),
              const EvaOverline('Сколько дней'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in _durations)
                    ChoiceChip(
                      label: Text(d == 21 ? '21 день' : '$d дней'),
                      selected: d == _days,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              EvaPrimaryButton(
                label: 'Начать сегодня',
                onPressed: _valid
                    ? () => Navigator.pop(context, {'title': _title.text.trim(), 'task': _task.text.trim(), 'emoji': _emoji, 'days': _days})
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
