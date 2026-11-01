// Экран «Статистика приложения» — только для владельца (a.eduardmail@gmail.com)
// и аккаунта поддержки. Данные считает функция adminStats на сервере:
// DAU/WAU/MAU по Firebase Auth (работает для всех версий приложения),
// путь до оплаты по Firestore и покупки RuStore.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';

class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  static const Map<String, String> _productNames = {
    'eva_sub_1_month': 'Месяц',
    'eva_sub_1_month_promo': 'Месяц (промо)',
    'eva_sub_1_year': 'Год',
    'eva_sub_1_year_promo': 'Год (промо)',
    'specialist_chat_monthly': 'Чат со специалистом',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('adminStats', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call();
      final dynamic raw = result.data;
      if (!mounted) return;
      setState(() {
        _data = raw is Map ? Map<String, dynamic>.from(raw) : null;
        _loading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('adminStats: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'permission-denied'
            ? 'Нет доступа. Статистика доступна только владельцу приложения.'
            : e.code == 'not-found'
                ? 'Функция adminStats ещё не выкачена. Выполните firebase deploy --only functions.'
                : 'Не удалось загрузить статистику (${e.code}). Попробуйте ещё раз.';
      });
    } catch (e) {
      debugPrint('adminStats: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить статистику. Проверьте соединение.';
      });
    }
  }

  Map<String, dynamic> _map(String key) =>
      _data?[key] is Map ? Map<String, dynamic>.from(_data![key] as Map) : <String, dynamic>{};

  List<Map<String, dynamic>> _list(String key) => _data?[key] is List
      ? (_data![key] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  /// null из сервера = «не удалось посчитать» → показываем «—».
  int? _n(Map<String, dynamic> m, String k) => m[k] == null ? null : evaInt(m[k]);

  String _fmt(int? v) => v == null ? '—' : NumberFormat.decimalPattern('ru').format(v);

  String _pct(int? part, int? whole) {
    if (part == null || whole == null || whole == 0) return '—';
    final double p = part * 100 / whole;
    return '${p < 10 ? p.toStringAsFixed(1) : p.round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Статистика'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Обновить', onPressed: _loading ? null : _load),
        ],
      ),
      body: EvaBackground(
        child: _loading
            ? _buildLoading()
            : _error != null && _data == null
                ? EvaEmptyState(icon: Icons.insights_rounded, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                      children: [
                        _buildActivity(theme),
                        const SizedBox(height: 16),
                        _buildUsers(theme),
                        const SizedBox(height: 16),
                        _buildFunnel(theme),
                        const SizedBox(height: 16),
                        _buildPurchases(theme),
                        const SizedBox(height: 16),
                        _buildBars(
                          theme,
                          title: 'Регистрации за 30 дней',
                          points: _list('registrations'),
                          valueKey: 'count',
                          color: EvaColors.rose,
                        ),
                        const SizedBox(height: 16),
                        _buildBars(
                          theme,
                          title: 'DAU по дням',
                          points: _list('history'),
                          valueKey: 'dau',
                          color: EvaColors.lavender,
                          emptyText: 'История копится с момента запуска: снимок сохраняется каждый день в 23:55 МСК и при каждом открытии этого экрана.',
                        ),
                        const SizedBox(height: 16),
                        _buildFooter(theme),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.all(EvaSpace.page),
      children: const [
        EvaSkeleton(height: 130, radius: 24),
        SizedBox(height: 16),
        EvaSkeleton(height: 110, radius: 24),
        SizedBox(height: 16),
        EvaSkeleton(height: 260, radius: 24),
      ],
    );
  }

  Widget _buildActivity(ThemeData theme) {
    final u = _map('users');
    final int? dau = _n(u, 'dau'), wau = _n(u, 'wau'), mau = _n(u, 'mau');
    const Color onHero = Colors.white;
    Widget metric(String label, int? v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fmt(v), style: theme.textTheme.headlineMedium?.copyWith(color: onHero, height: 1.1)),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: onHero.withValues(alpha: 0.85))),
            ],
          ),
        );
    return EvaCard(
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaOverline('Активные пользователи', color: onHero.withValues(alpha: 0.85)),
          const SizedBox(height: 12),
          Row(children: [metric('DAU · сутки', dau), metric('WAU · 7 дней', wau), metric('MAU · 30 дней', mau)]),
          const SizedBox(height: 14),
          Text(
            'Липкость DAU/MAU: ${_pct(dau, mau)}  ·  WAU/MAU: ${_pct(wau, mau)}',
            style: theme.textTheme.bodySmall?.copyWith(color: onHero.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }

  Widget _tile(ThemeData theme, String value, String label) {
    return Expanded(
      child: EvaCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildUsers(ThemeData theme) {
    final u = _map('users');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvaOverline('Регистрации'),
        const SizedBox(height: 8),
        Row(children: [
          _tile(theme, _fmt(_n(u, 'total')), 'всего'),
          const SizedBox(width: 10),
          _tile(theme, _fmt(_n(u, 'newToday')), 'сегодня'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _tile(theme, _fmt(_n(u, 'new7')), 'за 7 дней'),
          const SizedBox(width: 10),
          _tile(theme, _fmt(_n(u, 'new30')), 'за 30 дней'),
        ]),
      ],
    );
  }

  Widget _buildFunnel(ThemeData theme) {
    final f = _map('funnel');
    final int? base = _n(f, 'registered');
    final steps = <(String, int?, String)>[
      ('Зарегистрировались', base, ''),
      ('Прошли анкету', _n(f, 'onboarded'), ''),
      ('Написали Еве', _n(f, 'usedEva'), ''),
      ('Исчерпали 5 сообщений', _n(f, 'evaLimit'), 'видели пейвол'),
      ('Сканировали еду', _n(f, 'usedScan'), ''),
      ('Исчерпали 3 скана', _n(f, 'scanLimit'), 'видели пейвол'),
      ('Активировали START3', _n(f, 'trialStart3'), 'пробный период'),
      ('Premium когда-либо', _n(f, 'premiumEver'), 'включая промо'),
      ('Premium сейчас', _n(f, 'premiumActive'), ''),
    ];
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Путь до оплаты'),
          const SizedBox(height: 4),
          Text('Доля — от всех зарегистрированных', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          for (final s in steps) _funnelRow(theme, s.$1, s.$2, base, s.$3),
        ],
      ),
    );
  }

  Widget _funnelRow(ThemeData theme, String label, int? value, int? base, String hint) {
    final double share = (value == null || base == null || base == 0) ? 0 : (value / base).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: label, style: theme.textTheme.bodyMedium),
                if (hint.isNotEmpty)
                  TextSpan(text: '  $hint', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ])),
            ),
            Text(_fmt(value), style: theme.textTheme.titleSmall),
            SizedBox(
              width: 52,
              child: Text(_pct(value, base), textAlign: TextAlign.right, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 6,
              backgroundColor: context.eva.hairline,
              valueColor: const AlwaysStoppedAnimation<Color>(EvaColors.rose),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchases(ThemeData theme) {
    final p = _map('purchases');
    final Map<String, dynamic> byProduct = p['byProduct'] is Map ? Map<String, dynamic>.from(p['byProduct'] as Map) : {};
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Покупки RuStore'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _kv(theme, _fmt(_n(p, 'total')), 'всего')),
            Expanded(child: _kv(theme, _fmt(_n(p, 'last30')), 'за 30 дней')),
          ]),
          if (byProduct.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in byProduct.entries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Expanded(child: Text(_productNames[e.key] ?? e.key, style: theme.textTheme.bodyMedium)),
                  Text(_fmt(evaInt(e.value)), style: theme.textTheme.titleSmall),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _buildBars(
    ThemeData theme, {
    required String title,
    required List<Map<String, dynamic>> points,
    required String valueKey,
    required Color color,
    String? emptyText,
  }) {
    final values = points.map((p) => evaInt(p[valueKey])).toList();
    final int maxV = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);
    final int sum = values.fold(0, (a, b) => a + b);
    String label(int i) {
      final String d = points[i]['date']?.toString() ?? '';
      return d.length >= 10 ? '${d.substring(8, 10)}.${d.substring(5, 7)}' : d;
    }

    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: EvaOverline(title)),
            if (values.isNotEmpty)
              Text('макс. $maxV', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 14),
          if (values.length < 2 && emptyText != null)
            Text(emptyText, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else if (values.isEmpty || sum == 0)
            Text('Пока нет данных', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else ...[
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < values.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: '${label(i)}: ${values[i]}',
                        triggerMode: TooltipTriggerMode.tap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Container(
                            height: maxV == 0 ? 2 : (values[i] / maxV * 116).clamp(2, 116).toDouble(),
                            decoration: BoxDecoration(
                              color: i == values.length - 1 ? color : color.withValues(alpha: 0.55),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text(label(0), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text('нажмите на столбик', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text(label(values.length - 1), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    final int at = evaInt(_data?['generatedAt']);
    final String when = at == 0 ? '' : DateFormat('d MMMM, HH:mm', 'ru').format(DateTime.fromMillisecondsSinceEpoch(at));
    return Text(
      'Обновлено: $when\n'
      'Активность — по последнему входу/продлению сессии в Firebase Auth: пользователь считается активным, '
      'если открывал приложение за период. Воронка — по полям профиля в Firestore.',
      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}
