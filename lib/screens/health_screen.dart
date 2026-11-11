// Health Connect: подключение, данные за неделю, отключение.
// Плюс компактная карточка «Активность» для экрана «Сегодня».

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';

import '../services/analytics_service.dart';
import '../services/health_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';

const int kStepsGoal = 8000;

String formatSleep(int minutes) {
  if (minutes <= 0) return '—';
  final int h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h ч' : '$h ч $m мин';
}

String formatSteps(int steps) => NumberFormat.decimalPattern('ru').format(steps);

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthAvailability? _availability;
  bool _connected = false;
  bool _busy = false;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    Analytics.event('health_screen_open');
    _check();
  }

  Future<void> _check() async {
    final a = await HealthService.instance.availability();
    final bool c = a == HealthAvailability.available && await HealthService.instance.hasPermissions();
    if (!mounted) return;
    setState(() {
      _availability = a;
      _connected = c;
    });
    if (c) HealthService.instance.sync();
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      if (_availability == HealthAvailability.notInstalled || _availability == HealthAvailability.needsUpdate) {
        Analytics.event('health_install_open');
        await HealthService.instance.install();
        return;
      }
      final bool ok = await HealthService.instance.connect();
      Analytics.event(ok ? 'health_connected' : 'health_denied');
      if (!mounted) return;
      if (ok) {
        EvaSnack.show(context, 'Подключено! Ева видит шаги и сон 💗', type: EvaSnackType.success);
      } else {
        EvaSnack.show(context, 'Доступ не выдан. Можно разрешить позже в Health Connect.', type: EvaSnackType.error);
      }
      await _check();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await HealthService.instance.sync(force: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _disconnect() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отключить Health Connect?'),
        content: const Text('Ева перестанет получать шаги, сон и вес. Уже загруженные данные останутся в дневнике.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отключить')),
        ],
      ),
    );
    if (ok != true) return;
    await HealthService.instance.disconnect();
    Analytics.event('health_disconnected');
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool android = !kIsWeb && Platform.isAndroid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Шаги, сон и вес'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [if (_connected) IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _busy ? null : _refresh)],
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            EvaCard(
              gradient: context.eva.hero,
              border: false,
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                EvaOverline('Health Connect', color: Colors.white.withValues(alpha: 0.85)),
                const SizedBox(height: 8),
                Text('Ева учтёт твою активность и сон', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Text(
                  'Шаги, сон, активные калории и вес подтянутся из фитнес-браслета или других приложений — Samsung Health, Mi Fitness, Google Fit и др. Только чтение: мы ничего не меняем в твоих данных.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            if (!android)
              const EvaEmptyState(icon: Icons.phone_android_rounded, title: 'Только на Android', subtitle: 'Health Connect доступен на Android-устройствах.')
            else if (_availability == null)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (!_connected) ...[
              if (_availability != HealthAvailability.available)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _availability == HealthAvailability.needsUpdate
                        ? 'Нужно обновить приложение Health Connect — это бесплатно и займёт минуту.'
                        : 'На телефоне нет Health Connect. Установи его — на Android 14 и новее он уже встроен в настройки.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              EvaPrimaryButton(
                label: _availability == HealthAvailability.available
                    ? 'Подключить'
                    : (_availability == HealthAvailability.needsUpdate ? 'Обновить Health Connect' : 'Установить Health Connect'),
                icon: PhosphorIconsLight.heart,
                loading: _busy,
                onPressed: _busy ? null : _connect,
              ),
              const SizedBox(height: 12),
              Text('В браслете или приложении часов включи синхронизацию с Health Connect — тогда данные появятся здесь.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ] else ...[
              _Week(uid: _uid),
              const SizedBox(height: 16),
              TextButton.icon(onPressed: _disconnect, icon: const Icon(PhosphorIconsLight.linkBreak), label: const Text('Отключить Health Connect')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Week extends StatelessWidget {
  final String? uid;
  const _Week({required this.uid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Сортировка по id по убыванию требует индекса в Firestore (без него запрос падал
      // и экран всегда показывал «Данных пока нет»). Берём последние 7 дней по возрастанию
      // и разворачиваем на клиенте.
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('health_daily')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: HealthService.dayKey(DateTime.now().subtract(const Duration(days: 6))))
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) debugPrint('health_daily: ${snap.error}');
        final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]).reversed.toList();
        if (docs.isEmpty) {
          return Text('Данных пока нет. Проверь, что браслет или приложение синхронизируется с Health Connect, и нажми «обновить» вверху.',
              style: theme.textTheme.bodyMedium);
        }
        final Map<String, dynamic> today = docs.first.data();
        final int maxSteps = docs.map((d) => evaInt(d.data()['steps'])).fold<int>(kStepsGoal, (a, b) => a > b ? a : b);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (today['weightKg'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: EvaCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  EvaIconBubble(icon: PhosphorIconsLight.scales, color: context.eva.lavender, size: 42),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Последний вес', style: theme.textTheme.titleSmall)),
                  Text('${today['weightKg']} кг', style: theme.textTheme.titleLarge),
                ]),
              ),
            ),
          EvaCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const EvaOverline('Последние 7 дней'),
              const SizedBox(height: 12),
              for (final d in docs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    SizedBox(
                      width: 54,
                      child: Text(DateFormat('E, d', 'ru').format(DateTime.parse(d.id)), style: theme.textTheme.labelMedium),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (evaInt(d.data()['steps']) / maxSteps).clamp(0.0, 1.0),
                          minHeight: 10,
                          color: evaInt(d.data()['steps']) >= kStepsGoal ? context.eva.success : theme.colorScheme.primary,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(width: 62, child: Text(formatSteps(evaInt(d.data()['steps'])), textAlign: TextAlign.right, style: theme.textTheme.labelMedium)),
                    SizedBox(
                      width: 70,
                      child: Text('😴 ${formatSleep(evaInt(d.data()['sleepMin']))}', textAlign: TextAlign.right, style: theme.textTheme.labelSmall),
                    ),
                  ]),
                ),
              Text('Цель — $kStepsGoal шагов. Зелёный — цель выполнена.', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]);
      },
    );
  }
}

/// Карточка «Активность» на «Сегодня»: шаги, сон, активные калории.
/// Если Health Connect не подключён — короткое приглашение подключить.
class ActivityCard extends StatefulWidget {
  final bool connected;
  const ActivityCard({super.key, required this.connected});

  @override
  State<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<ActivityCard> with WidgetsBindingObserver {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_uid != null) {
      _stream = FirebaseFirestore.instance.collection('users').doc(_uid).collection('health_daily').doc(HealthService.dayKey(DateTime.now())).snapshots();
    }
    if (widget.connected) HealthService.instance.sync();
  }

  @override
  void didUpdateWidget(covariant ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !oldWidget.connected) HealthService.instance.sync(force: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.connected) HealthService.instance.sync();
  }

  void _open() => Navigator.push(context, MaterialPageRoute(builder: (_) => const HealthScreen()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!HealthService.supported) return const SizedBox.shrink();
    if (!widget.connected) {
      return EvaCard(
        onTap: () {
          Analytics.event('health_promo_tap');
          _open();
        },
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const EvaIconBubble(icon: PhosphorIconsLight.personSimpleWalk, color: EvaColors.follicular, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Подключи шаги и сон', style: theme.textTheme.titleSmall),
              Text('Из браслета или Samsung Health — Ева учтёт активность', style: theme.textTheme.bodySmall),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
        ]),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final d = snap.data?.data() ?? const <String, dynamic>{};
        final int steps = evaInt(d['steps']);
        final int sleep = evaInt(d['sleepMin']);
        final int kcal = evaInt(d['activeKcal']);
        Widget cell(String emoji, String value, String label) => Expanded(
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(value, style: theme.textTheme.titleMedium),
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            );
        return EvaCard(
          onTap: _open,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              const Expanded(child: EvaOverline('Активность сегодня')),
              Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              cell('👟', formatSteps(steps), 'из $kStepsGoal шагов'),
              cell('😴', formatSleep(sleep), 'сон ночью'),
              cell('🔥', '$kcal', 'акт. ккал'),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (steps / kStepsGoal).clamp(0.0, 1.0),
                minHeight: 6,
                color: steps >= kStepsGoal ? context.eva.success : theme.colorScheme.primary,
              ),
            ),
          ]),
        );
      },
    );
  }
}
