import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/calculation_service.dart';
import '../services/cycle_calculator.dart';
import '../services/database_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/dashboard/cycle_nutrition_card.dart';
import '../widgets/dashboard/nutrition_card.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';
import 'harmony/widgets/harmony_bottom_sheets.dart';
import 'harmony/widgets/harmony_meds_sheet.dart';
import 'harmony/widgets/harmony_mood_sheet.dart';
import 'harmony/widgets/harmony_symptoms_sheet.dart';
import 'meal_detail_screen.dart';
import 'shopping_list_screen.dart';
import 'weekly_insights_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  final Set<String> _optimisticDeletedIds = {};

  String? _uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _mealsStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _shoppingStream;
  String? _mealsDocId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(_uid);
      _userStream = userRef.snapshots();
      _shoppingStream = userRef.collection('shopping_list').doc('current').snapshots();
      _ensureMealsStream();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_selectedDate.year != now.year || _selectedDate.month != now.month || _selectedDate.day != now.day) {
        setState(() {
          _selectedDate = now;
          _ensureMealsStream();
        });
      }
    }
  }

  String get _docId =>
      "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

  void _ensureMealsStream() {
    if (_uid == null) return;
    if (_mealsStream != null && _mealsDocId == _docId) return;
    _mealsDocId = _docId;
    _mealsStream = FirebaseFirestore.instance.collection('users').doc(_uid).collection('meals').doc(_docId).snapshots();
  }

  static const List<String> _affirmations = [
    "Твой вес — это не твоя ценность",
    "Фокус на балансе и любви к себе",
    "Сегодня отличный день, чтобы выдохнуть",
    "Еда — это энергия, а не враг",
    "Ты прекрасна на любом этапе своего пути",
    "Каждый шаг к здоровью имеет значение",
    "Слушай своё тело — оно знает лучше",
  ];

  String get _affirmation => _affirmations[DateTime.now().weekday % _affirmations.length];

  String get _greeting {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Доброе утро';
    if (h >= 12 && h < 17) return 'Добрый день';
    if (h >= 17 && h < 23) return 'Добрый вечер';
    return 'Доброй ночи';
  }

  // ---------------------------------------------------------------------------
  // Трекер дня (симптомы, настроение и т.д.)
  // ---------------------------------------------------------------------------

  Future<void> _openDailyTracker(Map<String, dynamic> userData) async {
    final uid = _uid;
    if (uid == null) return;
    final String docId = _docId;
    final DateTime day = _selectedDate;
    final logRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId);

    Map<String, dynamic> data = {};
    try {
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await logRef.get(const GetOptions(source: Source.cache));
        if (!snap.exists) throw Exception('no cache');
      } catch (_) {
        snap = await logRef.get().timeout(const Duration(seconds: 6));
      }
      data = snap.data() ?? {};
    } catch (_) {}

    final Map<String, int> currentSymptoms = data['symptoms'] is Map
        ? (data['symptoms'] as Map).map((k, v) => MapEntry(k.toString(), evaInt(v)))
        : <String, int>{};
    final List<String> currentMoods = data['moods'] is List
        ? List<String>.from(data['moods'])
        : (data['mood'] is String && data['mood'].toString().isNotEmpty ? [data['mood'].toString()] : <String>[]);
    final List<String> currentMeds = List<String>.from(data['meds'] ?? const []);
    final List<String> currentSexData = List<String>.from(data['sex_data'] ?? const []);
    final int currentOrgasmCount = evaInt(data['orgasm_count']);
    final double? currentTemp = data['temperature'] != null ? evaDouble(data['temperature']) : null;
    final double globalWeight = userData['weight'] != null ? evaDouble(userData['weight'], 60) : 60.0;
    final double currentWeight = data['weight'] != null ? evaDouble(data['weight'], globalWeight) : globalWeight;

    if (!mounted) return;

    HarmonyBottomSheets.showDayActionSheet(
      context: context,
      day: day,
      userData: userData,
      onSymptomsTap: () => HarmonySymptomsSheet.show(context: context, selectedDay: day, currentSymptoms: currentSymptoms, onSave: (_) {}),
      onMoodTap: () => HarmonyMoodSheet.show(context: context, selectedDay: day, currentMoods: currentMoods, onSave: (_) {}),
      onTempTap: () => HarmonyBottomSheets.showTemperatureSheet(
        context: context,
        currentTemp: currentTemp,
        onSave: (val) {
          logRef.set({'temperature': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
        },
      ),
      onWeightTap: () => HarmonyBottomSheets.showWeightSheet(
        context: context,
        currentWeight: currentWeight,
        onSave: (val) async {
          final messenger = ScaffoldMessenger.of(context);
          final theme = Theme.of(context);
          logRef.set({'weight': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
          FirebaseFirestore.instance.collection('users').doc(uid).set({'weight': val}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));

          final int age = evaInt(userData['age']);
          final double height = evaDouble(userData['height']);
          final String goal = (userData['goal'] ?? 'Похудеть').toString();
          final String activity = (userData['activityLevel'] ?? 'Умеренная (1-2 тренировки)').toString();
          if (age > 0 && height > 0) {
            await CalculationService().recalculateAndSaveGoals(
              weight: val,
              height: height,
              age: age,
              goal: goal,
              activityLevel: activity,
              isPregnant: goal == 'Здоровая беременность',
            );
            EvaSnack.showOn(messenger, theme, 'Вес и норма КБЖУ обновлены ✨', type: EvaSnackType.success);
          }
        },
      ),
      onSexTap: () => HarmonyBottomSheets.showSexSheet(
        context: context,
        currentData: currentSexData,
        currentOrgasmCount: currentOrgasmCount,
        onSave: (list, orgasmCount) {
          logRef
              .set({'sex_data': list, 'orgasm_count': orgasmCount, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
              .catchError((e) => debugPrint('$e'));
        },
      ),
      onMedsTap: () => HarmonyMedsSheet.show(context: context, selectedDay: day, currentMeds: currentMeds, onSave: (_) {}),
    );
  }

  void _showEditWeightDialog(Map<String, dynamic> item) {
    final TextEditingController weightController = TextEditingController(text: '${evaInt(item['weight_g'], 100)}');
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Изменить порцию'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((item['name'] ?? 'Блюдо').toString(), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 14),
              TextField(
                controller: weightController,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: theme.textTheme.headlineMedium,
                decoration: const InputDecoration(labelText: 'Вес', suffixText: 'г'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                final newWeight = int.tryParse(weightController.text.trim());
                if (newWeight != null && newWeight > 0) {
                  DatabaseService().updateMealItemWeight(item, newWeight, dateDocId: _docId);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    if (_uid == null || _userStream == null) return const SizedBox.shrink();

    return EvaBackground(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return const EvaEmptyState(icon: Icons.cloud_off_rounded, title: 'Нет соединения', subtitle: 'Данные появятся, когда восстановится сеть.');
          }
          final Map<String, dynamic> userData = userSnapshot.data?.data() ?? <String, dynamic>{};
          final String name = (userData['name']?.toString().trim().isNotEmpty ?? false) ? userData['name'].toString().trim() : 'красотка';

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _mealsStream,
            builder: (context, mealsSnapshot) {
              final Map<String, dynamic>? mealsData = mealsSnapshot.data?.data();
              final CyclePhaseInfo phase = _phaseInfo(userData);

              return SafeArea(
                bottom: false,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(theme, name)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 18, EvaSpace.page, 0),
                      sliver: SliverList.list(
                        children: [
                          _buildCycleCard(theme, userData, phase),
                          const SizedBox(height: 14),
                          _buildEvaCard(theme),
                          const SizedBox(height: 14),
                          NutritionSummaryCard(
                            uid: _uid!,
                            docId: _docId,
                            optimisticDeletedIds: _optimisticDeletedIds,
                            mealsData: mealsData ?? const <String, dynamic>{},
                          ),
                          const SizedBox(height: 14),
                          _WaterCard(key: ValueKey('water_$_docId'), serverGlasses: evaInt(mealsData?['water_glasses'])),
                          const SizedBox(height: 14),
                          CycleNutritionCard(phaseType: phase.phaseType, phaseLabel: phase.title),
                          const SizedBox(height: 14),
                          _buildInsightsTeaser(theme),
                          const SizedBox(height: 28),
                          _buildDiaryHeader(theme, mealsData),
                          const SizedBox(height: 12),
                          _buildDiaryList(theme, mealsData),
                          const SizedBox(height: 130),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  CyclePhaseInfo _phaseInfo(Map<String, dynamic> userData) {
    final String appMode = (userData['appMode'] ?? (userData['isPregnant'] == true ? 'pregnancy' : 'standard')).toString();
    return CycleCalculator.getDayInfo(
      targetDate: _selectedDate,
      lastStartDate: (userData['lastPeriodStartDate'] as Timestamp?)?.toDate(),
      lastEndDate: (userData['lastPeriodEndDate'] as Timestamp?)?.toDate(),
      cycleLength: evaInt(userData['cycleLength'], 28).clamp(15, 60).toInt(),
      periodDuration: evaInt(userData['periodDuration'], 5).clamp(1, 20).toInt(),
      appMode: appMode,
      manualOvulationDay: userData['manualOvulationDay'] == null ? null : evaInt(userData['manualOvulationDay']),
      pregStartTs: userData['pregnancyStartDate'] as Timestamp?,
    );
  }

  Widget _buildHeader(ThemeData theme, String name) {
    final String date = DateFormat('EEEE, d MMMM', 'ru').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(EvaSpace.page, 14, EvaSpace.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EvaOverline(date),
                    const SizedBox(height: 6),
                    Text('$_greeting,', style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w400)),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.displaySmall),
                  ],
                ),
              ),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _shoppingStream,
                builder: (context, snap) {
                  final List<dynamic> cats = snap.data?.data()?['categories'] is List ? snap.data!.data()!['categories'] : const [];
                  final bool hasItems = cats.any((c) => c is Map && (c['items'] is List) && (c['items'] as List).isNotEmpty);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      EvaCircleButton(
                        icon: Icons.shopping_bag_outlined,
                        tooltip: 'Список покупок',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen())),
                      ),
                      if (hasItems)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 2)),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('✦', style: TextStyle(color: context.eva.gold, fontSize: 14)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _affirmation,
                  style: TextStyle(
                    fontFamily: EvaFonts.serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 17,
                    height: 1.3,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCycleCard(ThemeData theme, Map<String, dynamic> userData, CyclePhaseInfo phase) {
    final palette = context.eva;
    final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = evaInt(userData['cycleLength'], 28).clamp(15, 60).toInt();
    final int periodDuration = evaInt(userData['periodDuration'], 5).clamp(1, 20).toInt();
    final int? manualOv = userData['manualOvulationDay'] == null ? null : evaInt(userData['manualOvulationDay']);
    final String appMode = (userData['appMode'] ?? (userData['isPregnant'] == true ? 'pregnancy' : 'standard')).toString();

    if (appMode == 'pregnancy') {
      return EvaCard(
        padding: const EdgeInsets.all(22),
        gradient: LinearGradient(
          colors: [EvaColors.pregnancy.withValues(alpha: context.isDark ? 0.35 : 0.18), theme.colorScheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Row(
          children: [
            const EvaIconBubble(icon: Icons.child_friendly_rounded, color: EvaColors.pregnancy, size: 56, iconSize: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const EvaOverline('Беременность', color: EvaColors.pregnancy),
                  const SizedBox(height: 4),
                  Text(phase.title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(phase.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    int currentDay = 1;
    if (lastStartTs != null) {
      final s = lastStartTs.toDate();
      final start = DateTime(s.year, s.month, s.day);
      final now = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final int diff = now.difference(start).inDays;
      if (diff >= 0) currentDay = (diff % cycleLength) + 1;
    }
    final bool hasData = lastStartTs != null;

    return EvaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(132, 132),
                      painter: CycleRingPainter(
                        cycleLength: cycleLength,
                        periodDuration: periodDuration,
                        currentDay: currentDay,
                        ovulationDay: manualOv ?? max(1, cycleLength - 13),
                        hasData: hasData,
                        baseColor: palette.fieldFill,
                        primaryColor: EvaColors.menstruation,
                        ovulationColor: palette.lavender,
                        indicatorColor: theme.colorScheme.surface,
                        dotColor: theme.colorScheme.primary,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(hasData ? '$currentDay' : '—', style: theme.textTheme.displayMedium?.copyWith(height: 1)),
                        Text('день цикла', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EvaOverline('Мой цикл'),
                    const SizedBox(height: 4),
                    Text(hasData ? phase.title : 'Отметь начало цикла', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      hasData ? phase.description : 'Ева будет подсказывать питание и самочувствие по фазам.',
                      style: theme.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: EvaPrimaryButton(
                  label: 'Отметить день',
                  icon: Icons.edit_note_rounded,
                  height: 46,
                  onPressed: () => _openDailyTracker(userData),
                ),
              ),
              const SizedBox(width: 10),
              EvaCircleButton(
                icon: Icons.calendar_month_rounded,
                tooltip: 'Изменить дату начала цикла',
                size: 46,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: lastStartTs?.toDate() ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && _uid != null) {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(_uid)
                        .set({'lastPeriodStartDate': Timestamp.fromDate(picked), 'lastPeriodEndDate': FieldValue.delete()}, SetOptions(merge: true))
                        .catchError((e) => debugPrint('$e'));
                  }
                },
              ),
              const SizedBox(width: 8),
              EvaCircleButton(
                icon: Icons.info_outline_rounded,
                tooltip: 'Справка',
                size: 46,
                onTap: () => HarmonyBottomSheets.showInfoSheet(
                  context: context,
                  title: 'Твой цикл',
                  description: 'Розовая дуга — дни менструации, лавандовая — окно овуляции. Точка показывает сегодняшний день.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEvaCard(ThemeData theme) {
    return EvaCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian'))),
      gradient: context.eva.hero,
      border: false,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Спроси Еву', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text('Питание, самочувствие, анализы — 24/7', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildInsightsTeaser(ThemeData theme) {
    return EvaCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyInsightsScreen())),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          EvaIconBubble(icon: Icons.insights_rounded, color: context.eva.lavender, size: 46, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('Итоги недели от Евы', style: theme.textTheme.titleMedium)),
                    const SizedBox(width: 8),
                    EvaPill(text: 'Новое', color: context.eva.lavender),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Разбор питания и самочувствия + 3 совета', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _visibleItems(Map<String, dynamic>? mealsData) {
    final List<dynamic> raw = mealsData?['items'] is List ? mealsData!['items'] : const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .where((item) => !_optimisticDeletedIds.contains(item['id'].toString()))
        .toList();
  }

  Widget _buildDiaryHeader(ThemeData theme, Map<String, dynamic>? mealsData) {
    final items = _visibleItems(mealsData);
    final int total = items.fold<int>(0, (a, i) => a + evaInt(i['calories']));
    return EvaSectionHeader(
      title: 'Дневник питания',
      subtitle: items.isEmpty
          ? 'Сфотографируй тарелку — Ева всё посчитает'
          : '${items.length} ${EvaFormat.plural(items.length, 'приём', 'приёма', 'приёмов')} · ${EvaFormat.number(total)} ккал',
    );
  }

  Widget _buildDiaryList(ThemeData theme, Map<String, dynamic>? mealsData) {
    final items = _visibleItems(mealsData);
    if (items.isEmpty) {
      return EvaEmptyState(
        card: true,
        icon: Icons.restaurant_rounded,
        illustration: Image.asset('assets/images/empty_diary.png', width: 150, height: 150, fit: BoxFit.contain, cacheWidth: 450),
        title: 'Дневник пока пуст',
        subtitle: 'Нажми на камеру внизу, чтобы записать первый приём пищи',
      );
    }

    final List<dynamic> rawItems = mealsData?['items'] is List ? mealsData!['items'] : const [];
    return Column(
      children: items.reversed.map((item) {
        final bool isGrouped = item['is_grouped'] == true;
        final String timeStr = item['timestamp'] is Timestamp ? DateFormat('HH:mm').format((item['timestamp'] as Timestamp).toDate()) : '';
        final String? imageUrl = item['imageUrl']?.toString();
        final bool isValidUrl = imageUrl != null && imageUrl.startsWith('http') && imageUrl.length < 1000;
        final String id = (item['id'] ?? '').toString();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Dismissible(
            key: ValueKey('meal_$id'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(color: theme.colorScheme.error.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(EvaRadius.card)),
              child: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error, size: 26),
            ),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Удалить запись?'),
                      content: const Text('Этот приём пищи исчезнет из дневника.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Отмена')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Удалить'),
                        ),
                      ],
                    ),
                  ) ??
                  false;
            },
            onDismissed: (_) {
              setState(() => _optimisticDeletedIds.add(id));
              DatabaseService().deleteMealItem(item, List.from(rawItems), _docId).catchError((e) => debugPrint("delete meal: $e"));
              EvaSnack.show(context, 'Запись удалена', type: EvaSnackType.success);
            },
            child: EvaCard(
              padding: const EdgeInsets.all(14),
              onTap: () {
                if (isGrouped) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MealDetailScreen(mealData: item, dateDocId: _docId)));
                } else {
                  _showEditWeightDialog(item);
                }
              },
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 62,
                      height: 62,
                      child: isValidUrl
                          ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover, memCacheWidth: 200, errorWidget: (_, __, ___) => _mealPlaceholder(theme))
                          : (imageUrl != null && imageUrl.startsWith('assets/'))
                              ? Container(color: context.eva.fieldFill, padding: const EdgeInsets.all(10), child: Image.asset(imageUrl, fit: BoxFit.contain, cacheWidth: 150))
                              : _mealPlaceholder(theme),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text((item['name'] ?? 'Приём пищи').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                            ),
                            if (timeStr.isNotEmpty) Text(timeStr, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${evaInt(item['calories'])} ккал', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _MacroDot(letter: 'Б', value: evaInt(item['protein']), color: EvaColors.protein),
                            const SizedBox(width: 10),
                            _MacroDot(letter: 'Ж', value: evaInt(item['fat']), color: EvaColors.fat),
                            const SizedBox(width: 10),
                            _MacroDot(letter: 'У', value: evaInt(item['carbs']), color: EvaColors.carbs),
                            const SizedBox(width: 10),
                            _MacroDot(letter: 'К', value: evaInt(item['fiber']), color: EvaColors.fiber),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _mealPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary.withValues(alpha: 0.1),
      child: Icon(Icons.restaurant_rounded, color: theme.colorScheme.primary, size: 26),
    );
  }
}

class _MacroDot extends StatelessWidget {
  final String letter;
  final int value;
  final Color color;
  const _MacroDot({required this.letter, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$letter $value', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Трекер воды с мгновенным откликом (запись в Firestore — в фоне).
class _WaterCard extends StatefulWidget {
  final int serverGlasses;
  const _WaterCard({super.key, required this.serverGlasses});

  @override
  State<_WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends State<_WaterCard> {
  static const int _goal = 8;
  static const double _glassLiters = 0.3;
  int? _optimistic;

  @override
  void didUpdateWidget(covariant _WaterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_optimistic != null && widget.serverGlasses == _optimistic) _optimistic = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int glasses = _optimistic ?? widget.serverGlasses;
    return EvaCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: EvaOverline('Вода')),
              Text(
                '${(glasses * _glassLiters).toStringAsFixed(1)} л',
                style: theme.textTheme.titleMedium?.copyWith(color: EvaColors.water),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_goal, (index) {
              final bool filled = index < glasses;
              return Semantics(
                button: true,
                label: 'Стакан ${index + 1}',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final int newCount = filled && index == glasses - 1 ? index : index + 1;
                    setState(() => _optimistic = newCount);
                    DatabaseService().updateWaterGlasses(newCount);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    width: 32,
                    height: 40,
                    decoration: BoxDecoration(
                      color: filled ? EvaColors.water.withValues(alpha: 0.16) : context.eva.fieldFill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      filled ? Icons.water_drop_rounded : Icons.water_drop_outlined,
                      color: filled ? EvaColors.water : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                      size: 20,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text('$glasses из $_goal стаканов', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Тонкое кольцо цикла.
class CycleRingPainter extends CustomPainter {
  final int cycleLength;
  final int periodDuration;
  final int currentDay;
  final int ovulationDay;
  final bool hasData;
  final Color baseColor;
  final Color primaryColor;
  final Color ovulationColor;
  final Color indicatorColor;
  final Color dotColor;

  CycleRingPainter({
    required this.cycleLength,
    required this.periodDuration,
    required this.currentDay,
    required this.ovulationDay,
    required this.hasData,
    required this.baseColor,
    required this.primaryColor,
    this.ovulationColor = const Color(0xFF9A87B5),
    required this.indicatorColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 9.0;
    final radius = size.width / 2 - strokeWidth;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
    if (!hasData || cycleLength <= 0) return;

    final double perDay = (2 * pi) / cycleLength;
    const double startAngle = -pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      startAngle,
      perDay * periodDuration,
      false,
      Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      rect,
      startAngle + perDay * (ovulationDay - 2),
      perDay * 3,
      false,
      Paint()
        ..color = ovulationColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    final double angle = startAngle + perDay * (currentDay - 0.5);
    final Offset p = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
    canvas.drawCircle(
      p.translate(0, 2),
      11,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(p, 10, Paint()..color = indicatorColor);
    canvas.drawCircle(p, 4, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(covariant CycleRingPainter old) {
    return old.currentDay != currentDay ||
        old.cycleLength != cycleLength ||
        old.periodDuration != periodDuration ||
        old.ovulationDay != ovulationDay ||
        old.hasData != hasData ||
        old.baseColor != baseColor ||
        old.dotColor != dotColor;
  }
}
