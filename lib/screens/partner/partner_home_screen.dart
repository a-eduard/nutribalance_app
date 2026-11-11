// Главный экран партнёрского аккаунта: её фаза, подсказки, сигналы от неё.
// Данные приходят только с сервера (partnerLink view) — к её профилю доступа нет.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/home_widget_service.dart';
import '../../services/local_notification_service.dart';
import '../../services/push_notification_service.dart';
import '../../theme/eva_colors.dart';
import '../../widgets/eva_ui.dart';
import '../p2p_chat_screen.dart';
import 'partner_content.dart';
import 'partner_join_screen.dart';

class PartnerHomeScreen extends StatefulWidget {
  const PartnerHomeScreen({super.key});

  @override
  State<PartnerHomeScreen> createState() => _PartnerHomeScreenState();
}

class _PartnerHomeScreenState extends State<PartnerHomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _view;
  bool _loading = true;
  String? _error;
  bool _replying = false;

  HttpsCallable get _fn =>
      FirebaseFunctions.instance.httpsCallable('partnerLink', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.event('partner_home_open');
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _view == null;
      _error = null;
    });
    try {
      final res = await _fn.call({'action': 'view'});
      if (!mounted) return;
      setState(() {
        _view = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {'linked': false};
        _loading = false;
      });
      _updateWidget();
    } catch (e) {
      debugPrint('partner view: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить. Проверь соединение.';
      });
    }
  }

  void _updateWidget() {
    final v = _view;
    if (v == null || v['linked'] != true) {
      HomeWidgetService.updatePartner(name: 'Моя Ева', day: null, phase: 'связь не подключена', daysLeft: null);
      return;
    }
    final Map cycle = v['cycle'] is Map ? v['cycle'] as Map : const {};
    final String mode = (cycle['mode'] ?? '').toString();
    final PartnerPhaseInfo info = PartnerContent.forKey(mode, cycle['phaseKey']?.toString());
    final bool inCycle = mode == 'cycle';
    final bool period = cycle['phaseKey'] == 'menstruation';
    HomeWidgetService.updatePartner(
      name: (v['name'] ?? 'Она').toString(),
      day: inCycle ? evaInt(cycle['cycleDay']) : null,
      phase: info.title,
      daysLeft: inCycle && !period ? evaInt(cycle['daysToPeriod']) : null,
    );
  }

  void _openChat() {
    final String uid = (_view?['ownerUid'] ?? '').toString();
    if (uid.isEmpty) return;
    Analytics.event('partner_chat_open', {'by': 'partner'});
    Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: uid, otherUserName: (_view?['name'] ?? 'Она').toString())));
  }

  Future<void> _reply(String kind) async {
    setState(() => _replying = true);
    try {
      await _fn.call({'action': 'reply', 'kind': kind});
      Analytics.event('partner_reply_sent');
      if (mounted) EvaSnack.show(context, 'Отправлено 💗', type: EvaSnackType.success);
      await _load();
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось отправить', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _replying = false);
    }
  }

  Future<void> _logout() async {
    try {
      await PushNotificationService().clearToken();
      await LocalNotificationService().cancelAll();
    } catch (_) {}
    await AuthService().signOutEverywhere();
  }

  Future<void> _unlink() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключиться?'),
        content: const Text('Ты перестанешь видеть её фазу и получать подсказки. Подключиться снова можно будет по новому коду от неё.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отключиться')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _fn.call({'action': 'unlink'});
      Analytics.event('partner_unlink', {'by': 'partner'});
      await _load();
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось отключиться', type: EvaSnackType.error);
    }
  }

  void _menu() {
    final bool linked = _view?['linked'] == true;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (linked)
              ListTile(
                leading: const Icon(PhosphorIconsLight.linkBreak),
                title: const Text('Отключиться от неё'),
                onTap: () {
                  Navigator.pop(ctx);
                  _unlink();
                },
              ),
            ListTile(
              leading: const Icon(PhosphorIconsLight.signOut),
              title: const Text('Выйти из аккаунта'),
              onTap: () {
                Navigator.pop(ctx);
                _logout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool linked = _view?['linked'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя Ева · Партнёр'),
        actions: [IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: _menu)],
      ),
      body: EvaBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _view == null
                ? EvaEmptyState(icon: PhosphorIconsLight.heart, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : !linked
                    ? _buildNotLinked(theme)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                          children: [
                            _buildHero(theme),
                            const SizedBox(height: 12),
                            EvaPrimaryButton(
                              label: 'Написать ей',
                              icon: PhosphorIconsLight.chatCircleDots,
                              onPressed: _openChat,
                            ),
                            if (_view?['lastSignal'] is Map) ...[
                              const SizedBox(height: 16),
                              _buildSignal(theme),
                            ],
                            const SizedBox(height: 16),
                            _buildTips(theme),
                            const SizedBox(height: 16),
                            Text(
                              'Она видит только твои ответы на её сигналы. Её дневник, вес и питание тебе не видны — и это нормально 🤍',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
      ),
    );
  }

  Widget _buildNotLinked(ThemeData theme) {
    return EvaEmptyState(
      icon: PhosphorIconsLight.heart,
      title: 'Связь не подключена',
      subtitle: 'Попроси у неё код в «Моей Еве» (Профиль → «Режим партнёра») и введи его здесь.',
      actionLabel: 'Ввести код',
      onAction: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerJoinScreen()));
        _load();
      },
    );
  }

  Widget _buildHero(ThemeData theme) {
    final String name = (_view?['name'] ?? 'Она').toString();
    final Map cycle = _view?['cycle'] is Map ? _view!['cycle'] as Map : const {};
    final String? mode = cycle['mode']?.toString();
    final PartnerPhaseInfo info = PartnerContent.forKey(mode, cycle['phaseKey']?.toString());
    final int day = evaInt(cycle['cycleDay']);
    final int left = evaInt(cycle['daysToPeriod']);
    final int len = evaInt(cycle['cycleLength'], 28);
    final int week = evaInt(cycle['pregnancyWeek']);

    String sub = '';
    if (mode == 'cycle') {
      sub = 'День цикла $day';
      if (cycle['phaseKey'] != 'menstruation') sub += ' · до месячных $left ${PartnerContent.daysWord(left)}';
    } else if (mode == 'pregnancy' && week > 0) {
      sub = '$week-я неделя';
    }

    return EvaCard(
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaOverline('$name · сейчас', color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Text('${info.emoji} ${info.title}', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(sub, style: theme.textTheme.titleSmall?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
          ],
          if (mode == 'cycle' && len > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (day / len).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignal(ThemeData theme) {
    final Map s = _view!['lastSignal'] as Map;
    final Map? r = _view?['lastReply'] is Map ? _view!['lastReply'] as Map : null;
    final String name = (_view?['name'] ?? 'Она').toString();
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: EvaOverline('$name пишет')),
            Text(PartnerContent.ago(evaInt(s['at'])), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
          Text((s['text'] ?? '').toString(), style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          if (r != null)
            Text('Ты ответил: ${r['text']}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rep in PartnerContent.replies)
                  ActionChip(label: Text(rep.$2), onPressed: _replying ? null : () => _reply(rep.$1)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTips(ThemeData theme) {
    final Map cycle = _view?['cycle'] is Map ? _view!['cycle'] as Map : const {};
    final PartnerPhaseInfo info = PartnerContent.forKey(cycle['mode']?.toString(), cycle['phaseKey']?.toString());
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Как она может себя чувствовать'),
          const SizedBox(height: 8),
          Text(info.feel, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 18),
          const EvaOverline('Как поддержать'),
          const SizedBox(height: 10),
          for (final t in info.support)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: info.color, shape: BoxShape.circle),
                  ),
                  Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
