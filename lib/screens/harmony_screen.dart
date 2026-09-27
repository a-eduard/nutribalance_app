import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/cycle_calculator.dart';
import '../services/calculation_service.dart'; 
import 'harmony/widgets/harmony_calendar.dart';
import 'harmony/widgets/harmony_bottom_sheets.dart';
import 'harmony/widgets/harmony_symptoms_sheet.dart'; 
import 'harmony/widgets/harmony_mood_sheet.dart'; 
import 'harmony/widgets/harmony_meds_sheet.dart'; 
import 'ai_chat_screen.dart';
import 'harmony/widgets/harmony_overview_screen.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';

class HarmonyScreen extends StatefulWidget {
  const HarmonyScreen({super.key});

  @override
  State<HarmonyScreen> createState() => _HarmonyScreenState();
}

class _HarmonyScreenState extends State<HarmonyScreen> {
  DateTime _selectedDay = DateTime.now();
  
  Map<String, int> _currentDaySymptoms = {};
  List<String> _currentMoods = []; 
  List<String> _currentMeds = [];  
  double? _currentTemperature; 
  double? _currentWeight; 
  List<String> _currentSexData = []; 
  int _currentOrgasmCount = 0; 

  final Map<DateTime, Map<String, dynamic>> _cachedLogs = {};
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }
    _loadDayLogs(_selectedDay);
  }

  DateTime _key(DateTime d) => DateTime(d.year, d.month, d.day);

  String _docIdFor(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  /// ФИКС: после сохранения обновляем и локальный кэш дня — раньше при повторном
  /// выборе того же дня показывались старые данные.
  void _patchCache(DateTime day, Map<String, dynamic> patch) {
    final k = _key(day);
    _cachedLogs[k] = {...(_cachedLogs[k] ?? <String, dynamic>{}), ...patch};
  }

  Future<void> _loadDayLogs(DateTime date) async {
    final dateKey = DateTime(date.year, date.month, date.day);
    if (_cachedLogs.containsKey(dateKey)) {
      _applyDataToState(_cachedLogs[dateKey]!);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    final String docId = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref.get(const GetOptions(source: Source.cache));
        if (!doc.exists) throw Exception('no cache');
      } catch (_) {
        doc = await ref.get().timeout(const Duration(seconds: 6));
      }
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _cachedLogs[dateKey] = data; 
        _applyDataToState(data);
      } else {
        if (mounted) {
          _cachedLogs[dateKey] = {}; 
          setState(() { 
            _currentDaySymptoms = {}; 
            _currentMoods = []; 
            _currentMeds = [];
            _currentTemperature = null; 
            _currentWeight = null; 
            _currentSexData = [];
            _currentOrgasmCount = 0;
          });
        }
      }
    } catch (e) {
      debugPrint("Ошибка чтения cycle_logs: $e");
      if (mounted) {
        setState(() { 
          _currentDaySymptoms = {}; 
          _currentMoods = []; 
          _currentMeds = [];
          _currentTemperature = null; 
          _currentWeight = null; 
          _currentSexData = [];
          _currentOrgasmCount = 0;
        });
      }
    }
  }

  void _applyDataToState(Map<String, dynamic> data) {
    Map<String, int> parsedSymptoms = {};
    if (data['symptoms'] is Map) {
      parsedSymptoms = (data['symptoms'] as Map).map((k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0));
    }

    List<String> parsedMoods = [];
    if (data['moods'] is List) {
      parsedMoods = List<String>.from(data['moods']);
    } else if (data['mood'] is String && data['mood'].toString().isNotEmpty) {
      parsedMoods = [data['mood'].toString()];
    }

 if (!mounted) return;
    setState(() { 
      _currentDaySymptoms = parsedSymptoms; 
      _currentMoods = parsedMoods;
      _currentMeds = List<String>.from(data['meds'] ?? []);
      _currentTemperature = data['temperature'] != null ? (data['temperature'] as num).toDouble() : null;
      _currentWeight = data['weight'] != null ? (data['weight'] as num).toDouble() : null;
      _currentSexData = List<String>.from(data['sex_data'] ?? []);
      _currentOrgasmCount = data['orgasm_count'] != null ? (data['orgasm_count'] as num).toInt() : 0; 
    });
  }

  void _openEvaChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')),
    );
  }

  void _showSettingsSheet(Map<String, dynamic> userData, ThemeData theme) {
    final String appMode = (userData['appMode'] ?? (userData['isPregnant'] == true ? 'pregnancy' : 'standard')).toString();
    final int cycleLength = evaInt(userData['cycleLength'], 28);
    final int periodDuration = evaInt(userData['periodDuration'], 5);
    final int? manualOvDay = (userData['manualOvulationDay'] as num?)?.toInt();
    const modes = {'standard': 'Стандартный (фертильность)', 'simple': 'Простой (только месячные)', 'pregnancy': 'Беременность', 'menopause': 'Менопауза'};

    EvaSheet.show<void>(
      context,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: EvaSheetHeader(title: 'Настройки цикла')),
            EvaMenuTile(
              icon: Icons.tune_rounded,
              title: 'Режим приложения',
              subtitle: modes[appMode] ?? 'Стандартный',
              onTap: () {
                Navigator.pop(ctx);
                _showAppModePicker(appMode, theme);
              },
            ),
            if (appMode == 'standard' || appMode == 'simple') ...[
              EvaMenuTile(
                icon: Icons.loop_rounded,
                title: 'Длина цикла',
                subtitle: '$cycleLength ${EvaFormat.plural(cycleLength, 'день', 'дня', 'дней')}',
                onTap: () {
                  Navigator.pop(ctx);
                  HarmonyBottomSheets.showCycleSettingDialog(context: context, title: "Длина цикла", hintText: "Например: 28", currentValue: cycleLength, minVal: 15, maxVal: 60, updateField: 'cycleLength');
                },
              ),
              EvaMenuTile(
                icon: Icons.water_drop_outlined,
                title: 'Длина месячных',
                subtitle: '$periodDuration ${EvaFormat.plural(periodDuration, 'день', 'дня', 'дней')}',
                onTap: () {
                  Navigator.pop(ctx);
                  HarmonyBottomSheets.showCycleSettingDialog(context: context, title: "Длина месячных", hintText: "От 1 до 20 дней", currentValue: periodDuration, minVal: 1, maxVal: 20, updateField: 'periodDuration');
                },
              ),
            ],
            if (appMode == 'standard')
              EvaMenuTile(
                icon: Icons.auto_awesome_outlined,
                title: 'День овуляции',
                subtitle: manualOvDay != null ? '$manualOvDay-й день цикла' : 'Рассчитывается автоматически',
                onTap: () {
                  Navigator.pop(ctx);
                  _showOvulationDialog(theme);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAppModePicker(String currentMode, ThemeData theme) {
    const modes = {'standard': 'Стандартный (фертильность)', 'simple': 'Простой (только месячные)', 'pregnancy': 'Беременность', 'menopause': 'Менопауза'};
    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EvaSheetHeader(title: 'Режим приложения'),
            ...modes.entries.map((entry) => EvaOptionTile(
                  title: entry.value,
                  selected: currentMode == entry.key,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) return;
                    final Map<String, dynamic> updates = {'appMode': entry.key};
                    if (entry.key == 'pregnancy') {
                      final picked = await showDatePicker(
                        context: context,
                        helpText: 'Дата начала беременности',
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 300)),
                        lastDate: DateTime.now(),
                      );
                      if (picked == null) return;
                      updates['pregnancyStartDate'] = Timestamp.fromDate(picked);
                      updates['isPregnant'] = true;
                    } else {
                      updates['isPregnant'] = false;
                    }
                    FirebaseFirestore.instance.collection('users').doc(uid).set(updates, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showOvulationDialog(ThemeData theme) {
    final TextEditingController controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('День овуляции'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Оставь пустым для авторасчёта.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Например: 14')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                FirebaseFirestore.instance.collection('users').doc(uid).update({'manualOvulationDay': FieldValue.delete()}).catchError((e) => debugPrint('$e'));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Авторасчёт'),
          ),
          FilledButton(
            onPressed: () {
              final int? newDay = int.tryParse(controller.text);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (newDay != null && newDay > 0 && newDay < 60 && uid != null) {
                FirebaseFirestore.instance.collection('users').doc(uid).update({'manualOvulationDay': newDay}).catchError((e) => debugPrint('$e'));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<void> _onDaySelected(DateTime selectedDay, Map<String, dynamic> uData, String uid, double globalWeight) async {
    setState(() => _selectedDay = selectedDay);
    // ФИКС ГОНКИ: раньше шторка открывалась ДО загрузки данных выбранного дня
    // и показывала/сохраняла симптомы предыдущего дня.
    await _loadDayLogs(selectedDay);
    if (!mounted) return;

    final now = DateTime.now();
    final bool isToday = selectedDay.year == now.year && selectedDay.month == now.month && selectedDay.day == now.day;
    final cheatStatus = CycleCalculator.getCheatStatus(targetDate: selectedDay, userData: uData);
    if (isToday && cheatStatus == 'cheat_day') {
      EvaSnack.show(context, 'Сегодня можно побаловать себя любимой едой — без чувства вины ✨', duration: const Duration(seconds: 4));
    } else if (isToday && cheatStatus == 'cheat_meal') {
      EvaSnack.show(context, 'Воскресенье — день для души: любимые блюда без угрызений совести ✨', duration: const Duration(seconds: 4));
    }

    final String docId = _docIdFor(selectedDay);
    final logRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId);

    HarmonyBottomSheets.showDayActionSheet(
      context: context,
      day: selectedDay,
      userData: uData,
      onSymptomsTap: () => HarmonySymptomsSheet.show(
        context: context,
        selectedDay: selectedDay,
        currentSymptoms: _currentDaySymptoms,
        onSave: (map) {
          _patchCache(selectedDay, {'symptoms': map});
          if (mounted) setState(() => _currentDaySymptoms = map);
        },
      ),
      onMoodTap: () => HarmonyMoodSheet.show(
        context: context,
        selectedDay: selectedDay,
        currentMoods: _currentMoods,
        onSave: (list) {
          _patchCache(selectedDay, {'moods': list});
          if (mounted) setState(() => _currentMoods = list);
        },
      ),
      onTempTap: () => HarmonyBottomSheets.showTemperatureSheet(
        context: context,
        currentTemp: _currentTemperature,
        onSave: (val) {
          _patchCache(selectedDay, {'temperature': val});
          setState(() => _currentTemperature = val);
          logRef.set({'temperature': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
        },
      ),
      onWeightTap: () => HarmonyBottomSheets.showWeightSheet(
        context: context,
        currentWeight: _currentWeight ?? globalWeight,
        onSave: (val) async {
          final messenger = ScaffoldMessenger.of(context);
          final theme = Theme.of(context);
          _patchCache(selectedDay, {'weight': val});
          setState(() => _currentWeight = val);
          logRef.set({'weight': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
          FirebaseFirestore.instance.collection('users').doc(uid).set({'weight': val}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));

          final int age = evaInt(uData['age']);
          final double height = evaDouble(uData['height']);
          final String goal = (uData['goal'] ?? 'Похудеть').toString();
          final String activity = (uData['activityLevel'] ?? 'Умеренная (1-2 тренировки)').toString();
          if (age > 0 && height > 0) {
            await CalculationService().recalculateAndSaveGoals(weight: val, height: height, age: age, goal: goal, activityLevel: activity, isPregnant: goal == 'Здоровая беременность');
            EvaSnack.showOn(messenger, theme, 'Вес и норма КБЖУ обновлены ✨', type: EvaSnackType.success);
          }
        },
      ),
      onSexTap: () => HarmonyBottomSheets.showSexSheet(
        context: context,
        currentData: _currentSexData,
        currentOrgasmCount: _currentOrgasmCount,
        onSave: (list, orgasms) {
          _patchCache(selectedDay, {'sex_data': list, 'orgasm_count': orgasms});
          setState(() {
            _currentSexData = list;
            _currentOrgasmCount = orgasms;
          });
          logRef.set({'sex_data': list, 'orgasm_count': orgasms, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
        },
      ),
      onMedsTap: () => HarmonyMedsSheet.show(
        context: context,
        selectedDay: selectedDay,
        currentMeds: _currentMeds,
        onSave: (list) {
          _patchCache(selectedDay, {'meds': list});
          if (mounted) setState(() => _currentMeds = list);
        },
      ),
    );
  }

  Color _phaseColor(String phaseType) {
    switch (phaseType) {
      case 'menstruation':
        return EvaColors.menstruation;
      case 'ovulation':
      case 'fertile':
        return EvaColors.ovulation;
      case 'pms':
        return EvaColors.luteal;
      case 'follicular':
        return EvaColors.follicular;
      case 'pregnancy':
      case 'pregnancy_done':
        return EvaColors.pregnancy;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    if (uid == null || _userStream == null) {
      return const SizedBox.shrink();
    }

    return EvaBackground(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!.data() ?? <String, dynamic>{};
          final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
          final Timestamp? lastEndTs = userData['lastPeriodEndDate'] as Timestamp?;
          final Timestamp? pregStartTs = userData['pregnancyStartDate'] as Timestamp?;
          final int cycleLength = evaInt(userData['cycleLength'], 28).clamp(15, 60).toInt();
          final int periodDuration = evaInt(userData['periodDuration'], 5).clamp(1, 20).toInt();
          final int? manualOvulationDay = (userData['manualOvulationDay'] as num?)?.toInt();
          final bool isPregnantLegacy = userData['isPregnant'] == true;
          final String appMode = (userData['appMode'] ?? (isPregnantLegacy ? 'pregnancy' : 'standard')).toString();
          final double globalWeight = userData['weight'] != null ? evaDouble(userData['weight'], 60) : 60.0;

          final CyclePhaseInfo dayInfo = CycleCalculator.getDayInfo(
            targetDate: DateTime.now(),
            lastStartDate: lastStartTs?.toDate(),
            lastEndDate: lastEndTs?.toDate(),
            cycleLength: cycleLength,
            periodDuration: periodDuration,
            appMode: appMode,
            manualOvulationDay: manualOvulationDay,
            pregStartTs: pregStartTs,
          );
          final Color phaseColor = _phaseColor(dayInfo.phaseType);

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(EvaSpace.page, 14, EvaSpace.page, 130),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const EvaOverline('Женское здоровье'),
                          const SizedBox(height: 4),
                          Text('Гармония', style: theme.textTheme.displaySmall),
                        ],
                      ),
                    ),
                    EvaCircleButton(
                      icon: Icons.insights_rounded,
                      tooltip: 'Статистика и отчёт',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HarmonyOverviewScreen())),
                    ),
                    const SizedBox(width: 10),
                    EvaCircleButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Настройки цикла',
                      onTap: () => _showSettingsSheet(userData, theme),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                EvaCard(
                  padding: const EdgeInsets.all(22),
                  gradient: LinearGradient(
                    colors: [phaseColor.withValues(alpha: context.isDark ? 0.32 : 0.16), theme.colorScheme.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EvaOverline('Сегодня', color: phaseColor),
                      const SizedBox(height: 6),
                      Text(dayInfo.title, style: theme.textTheme.headlineLarge),
                      const SizedBox(height: 8),
                      Text(dayInfo.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                EvaCard(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: HarmonyCalendar(
                    userData: userData,
                    onDaySelected: (selectedDay, uData) => _onDaySelected(selectedDay, uData, uid, globalWeight),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Нажми на день в календаре, чтобы отметить самочувствие, настроение, вес или начало цикла.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 14),
                EvaCard(
                  onTap: _openEvaChat,
                  gradient: context.eva.hero,
                  border: false,
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Обсудить с Евой', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                            const SizedBox(height: 2),
                            Text('Симптомы, цикл, самочувствие — без стеснения', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
