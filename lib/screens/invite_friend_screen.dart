// «Пригласи подругу» — неделя PRO обеим.
// Код подруги создаёт и проверяет сервер (getReferralInfo / redeemPromo):
// подруге +7 дней PRO, пригласившей +7 дней (до 10 наград) и пуш.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/analytics_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';

class InviteFriendScreen extends StatefulWidget {
  const InviteFriendScreen({super.key});

  @override
  State<InviteFriendScreen> createState() => _InviteFriendScreenState();
}

class _InviteFriendScreenState extends State<InviteFriendScreen> {
  static const String _storeUrl =
      'https://www.rustore.ru/catalog/app/com.eduard.nutribalance?utm_source=referral&utm_medium=app&utm_campaign=invite';

  Map<String, dynamic>? _info;
  bool _loading = true;
  String? _error;
  final TextEditingController _codeController = TextEditingController();
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    Analytics.event('invite_open');
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _info == null;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getReferralInfo', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call();
      if (!mounted) return;
      setState(() {
        _info = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('getReferralInfo: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить твой код. Проверь соединение и попробуй ещё раз.';
      });
    }
  }

  String get _code => (_info?['code'] ?? '').toString();
  int get _days => evaInt(_info?['days'], 7);

  String get _shareText =>
      'Я слежу за питанием и циклом в «Моей Еве» 🌸 Ева считает калории по фото и подсказывает, что есть в каждую фазу.\n\n'
      'Скачай по ссылке и введи мой код $_code — нам обеим неделя PRO бесплатно 💗\n$_storeUrl';

  Future<void> _share() async {
    if (_code.isEmpty) return;
    Analytics.event('invite_share');
    try {
      await Share.share(_shareText, subject: 'Неделя PRO в «Моей Еве»');
    } catch (e) {
      debugPrint('share: $e');
      _copy();
    }
  }

  void _copy() {
    if (_code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _shareText));
    HapticFeedback.selectionClick();
    EvaSnack.show(context, 'Приглашение с кодом скопировано', type: EvaSnackType.success);
  }

  Future<void> _applyFriendCode() async {
    final String code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _applying = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('redeemPromo', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call({'code': code});
      if (!mounted) return;
      final data = res.data is Map ? res.data as Map : const {};
      Analytics.event('invite_code_applied', {'referral': data['referral'] == true ? 1 : 0});
      EvaSnack.show(context, 'Код принят! PRO на ${data['days'] ?? 7} дн. 💗', type: EvaSnackType.success);
      _codeController.clear();
      _load();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final String msg = switch (e.code) {
        'not-found' => 'Такого кода нет. Проверь буквы и цифры.',
        'already-exists' => e.message ?? 'Этот код уже применён',
        'failed-precondition' => e.message ?? 'Этот код нельзя применить',
        _ => 'Не удалось проверить код. Попробуй позже.',
      };
      EvaSnack.show(context, msg, type: EvaSnackType.error);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Нет соединения. Попробуй позже.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пригласи подругу'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _info == null
                ? EvaEmptyState(icon: PhosphorIconsLight.gift, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                      children: [
                        _buildHero(theme),
                        const SizedBox(height: 16),
                        _buildCode(theme),
                        const SizedBox(height: 16),
                        _buildSteps(theme),
                        const SizedBox(height: 16),
                        _buildStats(theme),
                        if (_info?['canEnterCode'] == true) ...[
                          const SizedBox(height: 16),
                          _buildEnterCode(theme),
                        ],
                      ],
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
          EvaOverline('Подарок на двоих', color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 8),
          Text('Неделя PRO тебе и подруге 💗', style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white)),
          const SizedBox(height: 10),
          Text(
            'Безлимитные вопросы Еве, калории по фото, меню под фазу цикла — $_days дней бесплатно вам обеим.',
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
          const EvaOverline('Твой код'),
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
                style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),
          EvaPrimaryButton(label: 'Отправить подруге', icon: Icons.ios_share_rounded, onPressed: _share),
          const SizedBox(height: 4),
          TextButton.icon(onPressed: _copy, icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Скопировать приглашение')),
        ],
      ),
    );
  }

  Widget _buildSteps(ThemeData theme) {
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Text(n, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(t, style: theme.textTheme.bodyMedium))),
            ],
          ),
        );
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Как это работает'),
          const SizedBox(height: 14),
          step('1', 'Отправь подруге приглашение с кодом.'),
          step('2', 'Она скачивает «Мою Еву» и вводит код в разделе «Пригласи подругу» или в поле «Промокод».'),
          step('3', 'Вам обеим сразу начисляется $_days дней PRO, а тебе придёт уведомление 🎉'),
        ],
      ),
    );
  }

  Widget _buildStats(ThemeData theme) {
    final int invited = evaInt(_info?['invited']);
    final int rewards = evaInt(_info?['rewards']);
    final int maxRewards = evaInt(_info?['maxRewards'], 10);
    Widget cell(String v, String l) => Expanded(
          child: Column(
            children: [
              Text(v, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(l, textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        );
    return EvaCard(
      child: Column(
        children: [
          Row(children: [cell('$invited', 'подруг\nприсоединилось'), cell('${rewards * _days}', 'дней PRO\nполучено')]),
          if (rewards >= maxRewards) ...[
            const SizedBox(height: 10),
            Text('Ты получила максимум наград — спасибо, что делишься Евой! 💗',
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _buildEnterCode(ThemeData theme) {
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Тебя пригласила подруга?'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Код подруги, например EVA7K2PQ'),
                  onSubmitted: (_) => _applyFriendCode(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _applying ? null : _applyFriendCode,
                  child: _applying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Применить'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Код действует в первые 30 дней после регистрации.',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
