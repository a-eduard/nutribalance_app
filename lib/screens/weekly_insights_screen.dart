// Новая функция: «Итоги недели от Евы».
// Сервер (weeklyInsights) собирает питание, воду, настроение и симптомы за 7 дней,
// а Ева пишет тёплый разбор и 3 персональных совета. Результат кэшируется на неделю.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';

class WeeklyInsightsScreen extends StatefulWidget {
  const WeeklyInsightsScreen({super.key});

  @override
  State<WeeklyInsightsScreen> createState() => _WeeklyInsightsScreenState();
}

class _WeeklyInsightsScreenState extends State<WeeklyInsightsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('weeklyInsights', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({'force': force, 'tzOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes});
      final dynamic raw = result.data;
      if (!mounted) return;
      setState(() {
        _data = raw is Map ? Map<String, dynamic>.from(raw) : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('weeklyInsights: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось подготовить итоги. Проверьте соединение и попробуйте ещё раз.';
      });
    }
  }

  Map<String, dynamic> get _stats => _data?['stats'] is Map ? Map<String, dynamic>.from(_data!['stats']) : <String, dynamic>{};
  Map<String, dynamic>? get _ai => _data?['ai'] is Map ? Map<String, dynamic>.from(_data!['ai']) : null;

  List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() : <String>[];

  void _discussWithEva() {
    final s = _stats;
    final ai = _ai;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatScreen(
          botType: 'dietitian',
          initialDisplayMessage: 'Давай обсудим мои итоги недели',
          initialTechnicalPrompt:
              'Вот мои итоги недели: дней с записями ${s['daysLogged'] ?? 0} из 7, в среднем ${s['avgCalories'] ?? 0} ккал '
              '(цель ${s['targetCalories'] ?? 0}), белок ${s['avgProtein'] ?? 0} г, вода ${s['avgWater'] ?? 0} стаканов. '
              '${ai != null ? 'Твои советы были: ${_strings(ai['tips']).join('; ')}. ' : ''}'
              'Помоги мне составить простой план на следующую неделю, чтобы я следовала этим советам.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Итоги недели'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: _loading
            ? _buildLoading(theme)
            : _error != null
                ? EvaEmptyState(icon: Icons.cloud_off_rounded, title: 'Ой…', subtitle: _error, actionLabel: 'Повторить', onAction: _load)
                : RefreshIndicator(
                    onRefresh: () => _load(force: true),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                      children: [
                        _buildHero(theme),
                        const SizedBox(height: 16),
                        _buildStatsGrid(theme),
                        const SizedBox(height: 16),
                        _buildCaloriesChart(theme),
                        ..._buildLists(theme),
                        const SizedBox(height: 24),
                        EvaPrimaryButton(label: 'Обсудить с Евой', icon: Icons.auto_awesome_rounded, onPressed: _discussWithEva),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(EvaSpace.page),
      children: [
        EvaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const EvaTypingDots(),
                const SizedBox(width: 12),
                Text('Ева подводит итоги недели…', style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 18),
              const EvaSkeleton(width: 220, height: 22),
              const SizedBox(height: 12),
              const EvaSkeleton(height: 14),
              const SizedBox(height: 8),
              const EvaSkeleton(width: 260, height: 14),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const EvaSkeleton(height: 160, radius: 24),
      ],
    );
  }

  Widget _buildHero(ThemeData theme) {
    final ai = _ai;
    final int score = ai == null ? 0 : evaInt(ai['score']).clamp(0, 10).toInt();
    return EvaCard(
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EvaOverline('Итоги 7 дней', color: Colors.white.withValues(alpha: 0.85)),
                const SizedBox(height: 6),
                Text(
                  ai?['headline']?.toString() ?? 'Твоя неделя',
                  style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  ai?['summary']?.toString() ??
                      'Ева пока не смогла написать разбор — но статистика ниже уже готова. Потяни вниз, чтобы обновить.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                ),
              ],
            ),
          ),
          if (score > 0) ...[
            const SizedBox(width: 14),
            EvaProgressRing(
              progress: score / 10,
              size: 76,
              stroke: 7,
              colors: const [Colors.white, Colors.white],
              trackColor: Colors.white.withValues(alpha: 0.25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$score', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, height: 1)),
                  Text('из 10', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statTile(ThemeData theme, IconData icon, Color color, String value, String label) {
    return EvaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaIconBubble(icon: icon, color: color, size: 34, iconSize: 18),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(ThemeData theme) {
    final s = _stats;
    final int days = evaInt(s['daysLogged']);
    final int avgCal = evaInt(s['avgCalories']);
    final int targetCal = evaInt(s['targetCalories']);
    return Column(
      children: [
        Row(children: [
          Expanded(child: _statTile(theme, Icons.event_available_rounded, context.eva.sage, '$days из 7', 'дней с записями')),
          const SizedBox(width: 12),
          Expanded(
            child: _statTile(theme, Icons.local_fire_department_rounded, EvaColors.protein, EvaFormat.number(avgCal),
                targetCal > 0 ? 'ккал в среднем · цель ${EvaFormat.number(targetCal)}' : 'ккал в среднем'),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statTile(theme, Icons.egg_alt_rounded, EvaColors.fat, '${evaInt(s['avgProtein'])} г', 'белка в день')),
          const SizedBox(width: 12),
          Expanded(child: _statTile(theme, Icons.water_drop_rounded, EvaColors.water, '${s['avgWater'] ?? 0}', 'стаканов воды в день')),
        ]),
      ],
    );
  }

  Widget _buildCaloriesChart(ThemeData theme) {
    final List<dynamic> days = _stats['days'] is List ? _stats['days'] : const [];
    if (days.isEmpty) return const SizedBox.shrink();
    final int target = evaInt(_stats['targetCalories']);
    int maxVal = target;
    for (final d in days) {
      if (d is Map) maxVal = evaInt(d['calories']) > maxVal ? evaInt(d['calories']) : maxVal;
    }
    if (maxVal <= 0) maxVal = 1;

    return EvaCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Калории по дням', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((d) {
                final Map m = d is Map ? d : const {};
                final int cal = evaInt(m['calories']);
                final DateTime? date = DateTime.tryParse((m['date'] ?? '').toString());
                final double h = (cal / maxVal).clamp(0.0, 1.0).toDouble() * 96;
                final bool over = target > 0 && cal > target;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (cal > 0)
                        Text(cal >= 1000 ? '${(cal / 1000).toStringAsFixed(1)}к' : '$cal',
                            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9.5, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: h < 4 ? 4 : h),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => Container(
                          width: 18,
                          height: v,
                          decoration: BoxDecoration(
                            gradient: cal > 0
                                ? LinearGradient(
                                    colors: over ? [context.eva.lavender, context.eva.lavender] : context.eva.heroGradient,
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  )
                                : null,
                            color: cal > 0 ? null : context.eva.fieldFill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        date == null ? '' : EvaFormat.capitalize(DateFormat('EE', 'ru').format(date)),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLists(ThemeData theme) {
    final ai = _ai;
    final List<String> wins = ai == null ? const [] : _strings(ai['wins']);
    final List<String> tips = ai == null ? const [] : _strings(ai['tips']);
    final List<String> moods = _strings(_stats['topMoods']);
    final List<String> symptoms = _strings(_stats['topSymptoms']);
    final List<Widget> out = [];

    if (wins.isNotEmpty) {
      out.addAll([
        const SizedBox(height: 22),
        const EvaSectionHeader(title: 'Чем гордиться'),
        const SizedBox(height: 10),
        EvaCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: wins
                .map((w) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.check_circle_rounded, color: context.eva.sage, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(w, style: theme.textTheme.bodyMedium)),
                      ]),
                    ))
                .toList(),
          ),
        ),
      ]);
    }

    if (tips.isNotEmpty) {
      out.addAll([
        const SizedBox(height: 22),
        const EvaSectionHeader(title: 'Советы на неделю'),
        const SizedBox(height: 10),
        ...tips.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: EvaCard(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: context.eva.hero, shape: BoxShape.circle),
                    child: Text('${e.key + 1}', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.value, style: theme.textTheme.bodyMedium)),
                ]),
              ),
            )),
      ]);
    }

    if (moods.isNotEmpty || symptoms.isNotEmpty) {
      out.addAll([
        const SizedBox(height: 12),
        const EvaSectionHeader(title: 'Самочувствие'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...moods.map((m) => EvaPill(text: m, color: context.eva.lavender, icon: Icons.mood_rounded)),
            ...symptoms.map((s) => EvaPill(text: s, color: context.eva.warning, icon: Icons.bolt_rounded)),
          ],
        ),
      ]);
    }
    return out;
  }
}
