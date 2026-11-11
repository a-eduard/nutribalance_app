// «Сканер состава»: фото этикетки продукта или косметики → разбор Евы.
// Сервер: scanLabel (Gemini, строгий JSON), история — users/{uid}/label_scans.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';
import 'cosmetic_shelf_screen.dart';
import 'skin_analysis_screen.dart';

class LabelScannerScreen extends StatefulWidget {
  /// 'food' или 'cosmetic' — с какой вкладки открыть.
  final String initialKind;
  const LabelScannerScreen({super.key, this.initialKind = 'food'});

  @override
  State<LabelScannerScreen> createState() => _LabelScannerScreenState();
}

class _LabelScannerScreenState extends State<LabelScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  late String _kind = widget.initialKind == 'cosmetic' ? 'cosmetic' : 'food';
  bool _busy = false;
  String? _skinType;

  static const List<String> _skinTypes = ['сухая', 'нормальная', 'комбинированная', 'жирная', 'чувствительная'];

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    Analytics.event('label_scanner_open', {'kind': _kind});
    _loadSkinType();
  }

  Future<void> _loadSkinType() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final String? v = d.data()?['skinType']?.toString();
      if (mounted && v != null && v.isNotEmpty) setState(() => _skinType = v);
    } catch (_) {}
  }

  void _setSkinType(String v) {
    final uid = _uid;
    setState(() => _skinType = v);
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).set({'skinType': v}, SetOptions(merge: true)).catchError((e) => debugPrint('skinType: $e'));
    }
  }

  Future<void> _scan(ImageSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    } catch (e) {
      debugPrint('pickImage: $e');
      if (mounted) EvaSnack.show(context, 'Не получилось открыть камеру. Попробуй ещё раз.', type: EvaSnackType.error);
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _analyze(base64Encode(await file.readAsBytes()), allowSwitch: true);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Нет соединения. Попробуй ещё раз.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Разбор фото. Если фото снято не в том режиме (крем в «Продуктах» и наоборот),
  /// сервер сообщает об этом, и мы один раз повторяем разбор в правильном режиме.
  Future<void> _analyze(String b64, {required bool allowSwitch}) async {
    Analytics.event('label_scan_start', {'kind': _kind});
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('scanLabel', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({'kind': _kind, 'imageBase64': b64});
      if (!mounted) return;
      final Map<String, dynamic> data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      final String wrong = (data['wrongKind'] ?? '').toString();
      if (data['ok'] != true && allowSwitch && (wrong == 'food' || wrong == 'cosmetic') && wrong != _kind) {
        Analytics.event('label_scan_switch', {'to': wrong});
        setState(() => _kind = wrong);
        EvaSnack.show(context, wrong == 'cosmetic' ? 'Похоже, это косметика — разбираю как косметику' : 'Похоже, это продукт — разбираю как продукт');
        await _analyze(b64, allowSwitch: false);
        return;
      }
      if (data['ok'] != true) {
        Analytics.event('label_scan_unreadable', {'kind': _kind});
        EvaSnack.show(context, (data['reason'] ?? 'Не получилось прочитать этикетку').toString(), type: EvaSnackType.error, duration: const Duration(seconds: 5));
        return;
      }
      Analytics.event('label_scan_done', {'kind': _kind, 'score': (data['score'] ?? '').toString()});
      Navigator.push(context, MaterialPageRoute(builder: (_) => LabelResultScreen(data: data)));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'resource-exhausted') {
        Analytics.event('label_scan_limit');
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true, source: 'scan_limit')));
      } else {
        EvaSnack.show(context, e.message ?? 'Не удалось разобрать фото', type: EvaSnackType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool food = _kind == 'food';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканер состава'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'food', label: Text('Продукт'), icon: Icon(Icons.shopping_basket_outlined)),
                ButtonSegment(value: 'cosmetic', label: Text('Косметика'), icon: Icon(PhosphorIconsLight.flowerLotus)),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            EvaCard(
              gradient: context.eva.hero,
              border: false,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EvaOverline(food ? 'В магазине' : 'Уход', color: Colors.white.withValues(alpha: 0.85)),
                  const SizedBox(height: 8),
                  Text(food ? 'Сфотографируй состав или таблицу КБЖУ' : 'Сфотографируй состав средства (INCI)',
                      style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    food
                        ? 'Ева скажет, стоит ли брать, найдёт скрытый сахар и добавки и подскажет порцию под твою норму.'
                        : 'Ева разберёт компоненты, скажет, подойдёт ли твоей коже и безопасно ли при беременности.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_busy)
              EvaCard(
                child: Column(children: [
                  const SizedBox(height: 6),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text('Ева читает этикетку…', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Обычно 10–20 секунд', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                ]),
              )
            else ...[
              EvaPrimaryButton(label: 'Сфотографировать', icon: PhosphorIconsLight.camera, onPressed: () => _scan(ImageSource.camera)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _scan(ImageSource.gallery),
                icon: const Icon(PhosphorIconsLight.images),
                label: const Text('Выбрать из галереи'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ],
            if (!food) ...[
              const SizedBox(height: 18),
              EvaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EvaOverline('Мой тип кожи'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _skinTypes) EvaChoiceChip(label: t, selected: _skinType == t, onTap: () => _setSkinType(t)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SkinAnalysisScreen())),
                      icon: const Icon(PhosphorIconsLight.scanSmiley, size: 18),
                      label: const Text('Определить тип кожи по селфи'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CosmeticShelfScreen())),
                      icon: const Icon(PhosphorIconsLight.drop, size: 18),
                      label: const Text('Моя полка косметики'),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'cosmetologist'))),
                      icon: const Icon(PhosphorIconsLight.chatCircleDots, size: 18),
                      label: const Text('Чат с Евой-косметологом'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _History(kind: _kind),
          ],
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  final String kind;
  const _History({required this.kind});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('label_scans').orderBy('at', descending: true).limit(30).snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? []).where((d) => d.data()['kind'] == kind).take(10).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EvaOverline('Недавние'),
            const SizedBox(height: 8),
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: EvaCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LabelResultScreen(data: d.data()))),
                  child: Row(children: [
                    _ScoreDot(score: (d.data()['score'] ?? 'ok').toString()),
                    const SizedBox(width: 12),
                    Expanded(child: Text((d.data()['productName'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall)),
                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScoreDot extends StatelessWidget {
  final String score;
  const _ScoreDot({required this.score});
  @override
  Widget build(BuildContext context) =>
      Container(width: 12, height: 12, decoration: BoxDecoration(color: scoreColor(score), shape: BoxShape.circle));
}

Color scoreColor(String s) => switch (s) {
      'good' => EvaColors.success,
      'limit' => EvaColors.error,
      _ => EvaColors.warning,
    };

// ---------------------------------------------------------------------------
// Экран результата
// ---------------------------------------------------------------------------

class LabelResultScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const LabelResultScreen({super.key, required this.data});

  bool get _food => data['kind'] != 'cosmetic';

  List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const [];
  List<Map> _maps(dynamic v) => v is List ? v.whereType<Map>().toList() : const [];

  String get _scoreText => switch ((data['score'] ?? 'ok').toString()) {
        'good' => _food ? 'Хороший выбор' : 'Хороший состав',
        'limit' => _food ? 'Лучше нечасто' : 'Есть нюансы',
        _ => _food ? 'Можно, в меру' : 'Нормальный состав',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String score = (data['score'] ?? 'ok').toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(_food ? 'Разбор продукта' : 'Разбор средства'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            EvaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_food && (data['productType'] ?? '').toString().isNotEmpty) EvaOverline(data['productType'].toString()),
                  Text((data['productName'] ?? '').toString(), style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  EvaPill(text: _scoreText, color: scoreColor(score), solid: true),
                  if ((data['verdict'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(data['verdict'].toString(), style: theme.textTheme.bodyLarge),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            ...(_food ? _foodBlocks(context, theme) : _cosmeticBlocks(context, theme)),
            const SizedBox(height: 12),
            Text('Ева — ИИ-помощница, а не врач. При аллергии и болезнях ориентируйся на рекомендации специалиста.',
                textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: EvaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [EvaOverline(title), const SizedBox(height: 10), ...children]),
        ),
      );

  Widget _bullet(ThemeData theme, String text, Color color, {String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(margin: const EdgeInsets.only(top: 7, right: 10), width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: sub == null ? null : FontWeight.w600)),
              if (sub != null && sub.isNotEmpty) Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      );

  String _num(dynamic v) {
    if (v == null) return '—';
    final double d = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
  }

  List<Widget> _foodBlocks(BuildContext context, ThemeData theme) {
    final Map p = data['per100'] is Map ? data['per100'] as Map : const {};
    Widget cell(String v, String l, Color c) => Expanded(
          child: Column(children: [
            Text(v, style: theme.textTheme.titleLarge?.copyWith(color: c)),
            const SizedBox(height: 2),
            Text(l, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        );
    final flags = _strings(data['flags']);
    final pros = _strings(data['pros']);
    final cons = _strings(data['cons']);
    final adds = _maps(data['additives']);
    return [
      _section(theme, 'На 100 г', [
        Row(children: [
          cell(_num(p['kcal']), 'ккал', theme.colorScheme.primary),
          cell(_num(p['protein']), 'белки', EvaColors.protein),
          cell(_num(p['fat']), 'жиры', EvaColors.fat),
          cell(_num(p['carbs']), 'углеводы', EvaColors.carbs),
        ]),
        if (p['sugar'] != null || p['fiber'] != null || p['salt'] != null) ...[
          const SizedBox(height: 12),
          Text(
            [
              if (p['sugar'] != null) 'сахар ${_num(p['sugar'])} г',
              if (p['fiber'] != null) 'клетчатка ${_num(p['fiber'])} г',
              if (p['salt'] != null) 'соль ${_num(p['salt'])} г',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if ((data['portionTip'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('🍽 ${data['portionTip']}', style: theme.textTheme.bodyMedium),
        ],
      ]),
      if (flags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Wrap(spacing: 8, runSpacing: 8, children: [for (final f in flags) EvaPill(text: f, color: EvaColors.warning)]),
        ),
      if (pros.isNotEmpty || cons.isNotEmpty)
        _section(theme, 'Плюсы и минусы', [
          for (final t in pros) _bullet(theme, t, EvaColors.success),
          for (final t in cons) _bullet(theme, t, EvaColors.error),
        ]),
      if (adds.isNotEmpty)
        _section(theme, 'Добавки', [
          for (final a in adds) _bullet(theme, '${a['code']} ${a['name']}'.trim(), EvaColors.lavender, sub: (a['note'] ?? '').toString()),
        ]),
      if ((data['phaseTip'] ?? '').toString().isNotEmpty) _section(theme, 'В твою фазу', [Text(data['phaseTip'].toString(), style: theme.textTheme.bodyMedium)]),
      if (p['kcal'] != null) _AddToDiary(data: data),
    ];
  }

  List<Widget> _cosmeticBlocks(BuildContext context, ThemeData theme) {
    final good = _maps(data['good']);
    final watch = _maps(data['watch']);
    final skin = _strings(data['skinTypes']);
    final String preg = (data['pregnancy'] ?? 'caution').toString();
    final (String pregText, Color pregColor) = switch (preg) {
      'ok' => ('Можно при беременности', EvaColors.success),
      'avoid' => ('Не рекомендуется при беременности', EvaColors.error),
      _ => ('При беременности — с осторожностью', EvaColors.warning),
    };
    final String name = (data['productName'] ?? 'это средство').toString();
    return [
      if (good.isNotEmpty) _section(theme, 'Полезные компоненты', [for (final g in good) _bullet(theme, (g['name'] ?? '').toString(), EvaColors.success, sub: (g['why'] ?? '').toString())]),
      if (watch.isNotEmpty) _section(theme, 'На что обратить внимание', [for (final w in watch) _bullet(theme, (w['name'] ?? '').toString(), EvaColors.warning, sub: (w['why'] ?? '').toString())]),
      if (skin.isNotEmpty)
        _section(theme, 'Кому подходит', [Wrap(spacing: 8, runSpacing: 8, children: [for (final s in skin) EvaPill(text: s)])]),
      _section(theme, 'Беременность и кормление', [
        EvaPill(text: pregText, color: pregColor),
        if ((data['pregnancyNote'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(data['pregnancyNote'].toString(), style: theme.textTheme.bodySmall),
        ],
      ]),
      if ((data['howToUse'] ?? '').toString().isNotEmpty) _section(theme, 'Как использовать', [Text(data['howToUse'].toString(), style: theme.textTheme.bodyMedium)]),
      if ((data['phaseTip'] ?? '').toString().isNotEmpty) _section(theme, 'В твою фазу', [Text(data['phaseTip'].toString(), style: theme.textTheme.bodyMedium)]),
      // Средство есть дома — кладём на полку, Ева учтёт его в советах.
      ShelfButton(data: data),
      const SizedBox(height: 10),
      EvaPrimaryButton(
        label: 'Спросить Еву-косметолога',
        icon: PhosphorIconsLight.chatCircleDots,
        onPressed: () {
          Analytics.event('cosmetologist_from_scan');
          final String summary = [
            'Я отсканировала средство «$name» (${data['productType'] ?? ''}).',
            if (good.isNotEmpty) 'Полезное: ${good.map((g) => g['name']).join(', ')}.',
            if (watch.isNotEmpty) 'Обратить внимание: ${watch.map((w) => w['name']).join(', ')}.',
            'Подскажи, как встроить его в мой уход и с чем не сочетать.',
          ].join(' ');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AIChatScreen(
                botType: 'cosmetologist',
                initialDisplayMessage: 'Как встроить «$name» в мой уход?',
                initialTechnicalPrompt: summary,
              ),
            ),
          );
        },
      ),
    ];
  }
}

class _AddToDiary extends StatefulWidget {
  final Map<String, dynamic> data;
  const _AddToDiary({required this.data});

  @override
  State<_AddToDiary> createState() => _AddToDiaryState();
}

class _AddToDiaryState extends State<_AddToDiary> {
  late final TextEditingController _grams;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final dynamic pkg = widget.data['packageG'];
    final int g = pkg is num && pkg > 0 && pkg <= 500 ? pkg.round() : 100;
    _grams = TextEditingController(text: '$g');
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  int _scaled(String key, double grams) {
    final Map p = widget.data['per100'] is Map ? widget.data['per100'] as Map : const {};
    final dynamic v = p[key];
    final double d = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return (d * grams / 100).round();
  }

  Future<void> _add() async {
    final double grams = double.tryParse(_grams.text.replaceAll(',', '.')) ?? 0;
    if (grams <= 0 || grams > 3000) {
      EvaSnack.show(context, 'Укажи вес порции в граммах', type: EvaSnackType.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final String name = (widget.data['productName'] ?? 'Продукт').toString();
    final int score = switch ((widget.data['score'] ?? 'ok').toString()) { 'good' => 8, 'limit' => 3, _ => 6 };
    try {
      await DatabaseService().logMeal({
        'meal_name': name,
        'items': [
          {
            'meal_name': name,
            'weight_g': grams,
            'calories': _scaled('kcal', grams),
            'protein': _scaled('protein', grams),
            'fat': _scaled('fat', grams),
            'carbs': _scaled('carbs', grams),
            'fiber': _scaled('fiber', grams),
            'health_score': score,
          }
        ],
      });
      Analytics.event('label_scan_logged');
      if (mounted) EvaSnack.show(context, 'Добавила в дневник 🌸', type: EvaSnackType.success);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось добавить', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EvaOverline('Съела? Добавь в дневник'),
          const SizedBox(height: 10),
          Row(children: [
            SizedBox(
              width: 120,
              child: TextField(
                controller: _grams,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(suffixText: 'г'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '≈ ${_scaled('kcal', double.tryParse(_grams.text.replaceAll(',', '.')) ?? 0)} ккал',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          EvaPrimaryButton(label: 'Добавить в дневник', icon: Icons.add_rounded, loading: _saving, onPressed: _saving ? null : _add),
        ],
      ),
    );
  }
}
