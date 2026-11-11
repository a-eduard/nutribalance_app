// «Режим партнёра» для неё: код для партнёра, статус связи, сигналы, отключение.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/analytics_service.dart';
import '../../theme/eva_colors.dart';
import '../../widgets/eva_ui.dart';
import '../p2p_chat_screen.dart';
import 'partner_content.dart';

class PartnerShareScreen extends StatefulWidget {
  const PartnerShareScreen({super.key});

  @override
  State<PartnerShareScreen> createState() => _PartnerShareScreenState();
}

class _PartnerShareScreenState extends State<PartnerShareScreen> {
  static const String _storeUrl =
      'https://www.rustore.ru/catalog/app/com.eduard.nutribalance?utm_source=partner&utm_medium=app&utm_campaign=partner_mode';

  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;
  String? _sending;

  HttpsCallable get _fn =>
      FirebaseFunctions.instance.httpsCallable('partnerLink', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)));

  @override
  void initState() {
    super.initState();
    Analytics.event('partner_share_open');
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _info == null;
      _error = null;
    });
    try {
      final res = await _fn.call({'action': 'info'});
      if (!mounted) return;
      setState(() {
        _info = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('partner info: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить. Проверь соединение и попробуй ещё раз.';
      });
    }
  }

  String get _code => (_info?['code'] ?? '').toString();
  Map? get _partner => _info?['partner'] is Map ? _info!['partner'] as Map : null;

  String get _shareText =>
      'Хочу, чтобы ты понимал меня чуть лучше 💗 Поставь «Мою Еву», при входе нажми «Я партнёр» и введи код $_code.\n'
      'Ты будешь видеть мою фазу цикла и подсказки, как поддержать, а я смогу отправлять тебе сигналы вроде «обними меня» 🤗\n$_storeUrl';

  Future<void> _share() async {
    if (_code.isEmpty) return;
    Analytics.event('partner_share');
    try {
      await Share.share(_shareText, subject: 'Режим партнёра в «Моей Еве»');
    } catch (_) {
      _copy();
    }
  }

  void _copy() {
    if (_code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _shareText));
    HapticFeedback.selectionClick();
    EvaSnack.show(context, 'Приглашение с кодом скопировано', type: EvaSnackType.success);
  }

  Future<void> _signal(String kind) async {
    setState(() => _sending = kind);
    try {
      await _fn.call({'action': 'signal', 'kind': kind});
      Analytics.event('partner_signal_sent');
      HapticFeedback.lightImpact();
      if (mounted) EvaSnack.show(context, 'Отправлено 💌', type: EvaSnackType.success);
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) EvaSnack.show(context, e.message ?? 'Не удалось отправить', type: EvaSnackType.error);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Нет соединения', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  Future<void> _unlink() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить партнёра?'),
        content: const Text('Он перестанет видеть твою фазу и получать подсказки. Мы отправим ему короткое уведомление.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отключить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _fn.call({'action': 'unlink'});
      Analytics.event('partner_unlink', {'by': 'owner'});
      await _load();
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось отключить', type: EvaSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Режим партнёра'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _info == null
                ? EvaEmptyState(icon: PhosphorIconsLight.heart, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                      children: _partner == null
                          ? [_buildHero(theme), const SizedBox(height: 16), _buildCode(theme), const SizedBox(height: 16), _buildWhatSees(theme)]
                          : [_buildLinked(theme), const SizedBox(height: 16), _buildSignals(theme), const SizedBox(height: 16), _buildWhatSees(theme)],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHero(ThemeData theme) {
    return EvaCard(
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaOverline('Для двоих', color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Text('Пусть он понимает тебя без слов 💗', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 10),
          Text(
            'Партнёр увидит твою фазу цикла и подсказки, как поддержать, а за пару дней до месячных получит напоминание.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }

  Widget _buildCode(ThemeData theme) {
    return EvaCard(
      child: Column(
        children: [
          const EvaOverline('Код для партнёра'),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _copy,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: context.eva.fieldFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35), width: 1.5),
              ),
              child: Text(
                _code,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Он ставит «Мою Еву», при входе нажимает «Я партнёр» и вводит этот код.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          EvaPrimaryButton(label: 'Отправить партнёру', icon: Icons.ios_share_rounded, onPressed: _share),
          const SizedBox(height: 4),
          TextButton.icon(onPressed: _copy, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Скопировать приглашение')),
        ],
      ),
    );
  }

  Widget _buildLinked(ThemeData theme) {
    final String name = (_partner?['name'] ?? 'Партнёр').toString();
    final Map? reply = _info?['lastReply'] is Map ? _info!['lastReply'] as Map : null;
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EvaIconBubble(icon: PhosphorIconsLight.heart, color: EvaColors.rose, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleLarge),
                    Text('подключён', style: theme.textTheme.bodySmall?.copyWith(color: context.eva.success)),
                  ],
                ),
              ),
              TextButton(onPressed: _unlink, child: const Text('Отключить')),
            ],
          ),
          const SizedBox(height: 14),
          EvaPrimaryButton(
            label: 'Написать ему',
            icon: PhosphorIconsLight.chatCircleDots,
            onPressed: () {
              final String uid = (_partner?['uid'] ?? '').toString();
              if (uid.isEmpty) return;
              Analytics.event('partner_chat_open', {'by': 'owner'});
              Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: uid, otherUserName: name)));
            },
          ),
          if (reply != null) ...[
            const SizedBox(height: 12),
            Text('Ответ: ${reply['text']} · ${PartnerContent.ago(evaInt(reply['at']))}', style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }

  Widget _buildSignals(ThemeData theme) {
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Отправить сигнал'),
          const SizedBox(height: 6),
          Text('Придёт ему пушем — без лишних объяснений.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in PartnerContent.signals)
                EvaChoiceChip(
                  label: s.$3,
                  emoji: s.$2,
                  selected: _sending == s.$1,
                  onTap: _sending != null ? null : () => _signal(s.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhatSees(ThemeData theme) {
    Widget line(IconData icon, String text, bool yes) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: yes ? context.eva.success : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Что видит партнёр'),
          const SizedBox(height: 12),
          line(Icons.check_circle_rounded, 'Твоё имя, фазу и день цикла', true),
          line(Icons.check_circle_rounded, 'Сколько дней до месячных и советы, как поддержать', true),
          line(Icons.check_circle_rounded, 'Твои сигналы', true),
          line(Icons.block_rounded, 'Дневник, симптомы, настроение, вес и питание — нет', false),
          line(Icons.block_rounded, 'Чаты с Евой — нет', false),
        ],
      ),
    );
  }
}
