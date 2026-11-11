// Экран «Рассылка» в админ-разделе: сообщение всем пользователям в чат
// от аккаунта поддержки + пуш. Сервер: adminBroadcast → admin_broadcasts →
// processAdminBroadcast. Сначала «Проверить» (сколько получат), потом «Отправить».

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/eva_ui.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  int? _checkedTotal;
  String? _checkedText;
  List<Map<String, dynamic>> _history = const [];

  HttpsCallable get _fn =>
      FirebaseFunctions.instance.httpsCallable('adminBroadcast', options: HttpsCallableOptions(timeout: const Duration(seconds: 40)));

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _text.addListener(() {
      if (_checkedText != null && _checkedText != _text.text.trim()) setState(() => _checkedTotal = null);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await _fn.call({'action': 'list'});
      final items = (res.data is Map ? (res.data as Map)['items'] : null) as List? ?? const [];
      if (!mounted) return;
      setState(() => _history = items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (e) {
      debugPrint('broadcast list: $e');
    }
  }

  Future<void> _check() async {
    final String text = _text.text.trim();
    if (text.length < 5) {
      EvaSnack.show(context, 'Напишите текст сообщения', type: EvaSnackType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await _fn.call({'action': 'create', 'text': text, 'dryRun': true});
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (!mounted) return;
      if (data['status'] == 'dry_run') {
        setState(() {
          _checkedTotal = evaInt(data['total']);
          _checkedText = text;
        });
      } else {
        EvaSnack.show(context, data['error']?.toString() ?? 'Проверка ещё идёт — нажмите ещё раз через пару секунд', type: EvaSnackType.error);
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) EvaSnack.show(context, e.message ?? 'Ошибка: ${e.code}', type: EvaSnackType.error);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Нет соединения', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final String text = _text.text.trim();
    final int total = _checkedTotal ?? 0;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отправить рассылку?'),
        content: Text('Сообщение получат $total пользователей, каждому придёт пуш. Отменить отправку будет нельзя.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отправить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _fn.call({'action': 'create', 'text': text, 'dryRun': false});
      if (!mounted) return;
      EvaSnack.show(context, 'Рассылка запущена — статус обновится через минуту', type: EvaSnackType.success);
      _text.clear();
      setState(() => _checkedTotal = null);
      await Future.delayed(const Duration(seconds: 3));
      await _loadHistory();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) EvaSnack.show(context, e.message ?? 'Ошибка: ${e.code}', type: EvaSnackType.error);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Нет соединения', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canSend = _checkedTotal != null && _checkedText == _text.text.trim() && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рассылка'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadHistory)],
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            EvaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EvaOverline('Сообщение всем пользователям'),
                  const SizedBox(height: 6),
                  Text('Придёт в чат «Поддержка» и пушем. Ссылки кликабельны с версии 1.5.0.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _text,
                    minLines: 6,
                    maxLines: 14,
                    maxLength: 3000,
                    decoration: const InputDecoration(hintText: 'Здравствуйте! 👋 …'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _check,
                          child: const Text('Проверить'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: canSend ? _send : null,
                          child: Text(_checkedTotal == null ? 'Отправить' : 'Отправить ($_checkedTotal)'),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
                  if (_checkedTotal != null && !_busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Получат: $_checkedTotal пользователей', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const EvaOverline('История'),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              Text('Пока пусто', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            for (final h in _history) _historyItem(theme, h),
          ],
        ),
      ),
    );
  }

  Widget _historyItem(ThemeData theme, Map<String, dynamic> h) {
    final String status = (h['status'] ?? '').toString();
    final bool dry = h['dryRun'] == true || status == 'dry_run';
    final int at = evaInt(h['at']);
    final String when = at > 0 ? DateFormat('d MMM, HH:mm', 'ru').format(DateTime.fromMillisecondsSinceEpoch(at)) : '';
    final String label = switch (status) {
      'done' => 'Отправлено ${h['sent']} из ${h['total']}${evaInt(h['failed']) > 0 ? ', ошибок ${h['failed']}' : ''}',
      'sending' => 'Отправляется… ${h['sent']} из ${h['total']}',
      'dry_run' => 'Проверка: ${h['total']} получателей',
      'error' => 'Ошибка',
      _ => 'В очереди',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EvaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(dry ? Icons.fact_check_outlined : Icons.campaign_outlined, size: 18, color: dry ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              Text(when, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 6),
            Text((h['text'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
