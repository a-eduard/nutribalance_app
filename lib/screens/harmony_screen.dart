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

  @override
  void initState() {
    super.initState();
    _loadDayLogs(_selectedDay);
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
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).get();
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
      parsedSymptoms = (data['symptoms'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }

    List<String> parsedMoods = [];
    if (data['moods'] is List) {
      parsedMoods = List<String>.from(data['moods']);
    } else if (data['mood'] is String && data['mood'].toString().isNotEmpty) {
      parsedMoods = [data['mood'].toString()];
    }

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
    final String appMode = userData['appMode'] ?? (userData['isPregnant'] == true ? 'pregnancy' : 'standard');
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
    final int? manualOvDay = userData['manualOvulationDay'] as int?;
    
    final modes = {'standard': 'Стандартный (фертильность)', 'simple': 'Простой (только месячные)', 'pregnancy': 'Беременность', 'menopause': 'Менопауза'};

    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Настройки календаря", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero, 
                  title: Text("Режим приложения", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)), 
                  subtitle: Text(modes[appMode] ?? 'Стандартный', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)), 
                  trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), 
                  onTap: () { 
                    Navigator.pop(ctx); 
                    _showAppModePicker(appMode, theme); 
                  }
                ),
                if (appMode == 'standard' || appMode == 'simple') ...[
                  Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                  ListTile(
                    contentPadding: EdgeInsets.zero, 
                    title: Text("Длина цикла", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)), 
                    subtitle: Text("$cycleLength дн.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)), 
                    trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), 
                    onTap: () { 
                      Navigator.pop(ctx); 
                      HarmonyBottomSheets.showCycleSettingDialog(context: context, title: "Длина цикла", hintText: "Например: 28", currentValue: cycleLength, minVal: 15, maxVal: 60, updateField: 'cycleLength'); 
                    }
                  ),
                  Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                  ListTile(
                    contentPadding: EdgeInsets.zero, 
                    title: Text("Длина месячных", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)), 
                    subtitle: Text("$periodDuration дн.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)), 
                    trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), 
                    onTap: () { 
                      Navigator.pop(ctx); 
                      HarmonyBottomSheets.showCycleSettingDialog(context: context, title: "Длина месячных", hintText: "От 1 до 20 дней", currentValue: periodDuration, minVal: 1, maxVal: 20, updateField: 'periodDuration'); 
                    }
                  ),
                ],
                if (appMode == 'standard') ...[
                  Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                  ListTile(
                    contentPadding: EdgeInsets.zero, 
                    title: Text("День овуляции", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600)), 
                    subtitle: Text(manualOvDay != null ? "$manualOvDay день цикла" : "Автоматически", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)), 
                    trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), 
                    onTap: () { 
                      Navigator.pop(ctx); 
                      _showOvulationDialog(theme); 
                    }
                  ),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAppModePicker(String currentMode, ThemeData theme) {
    final modes = {'standard': 'Стандартный (фертильность)', 'simple': 'Простой (только месячные)', 'pregnancy': 'Беременность', 'menopause': 'Менопауза'};
    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Выберите режим", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              ...modes.entries.map((entry) => ListTile(
                title: Text(entry.value, style: TextStyle(fontWeight: currentMode == entry.key ? FontWeight.bold : FontWeight.normal, color: currentMode == entry.key ? theme.colorScheme.primary : theme.colorScheme.onSurface)),
                trailing: currentMode == entry.key ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    Map<String, dynamic> updates = {'appMode': entry.key};
                    if (entry.key == 'pregnancy') {
                      final picked = await showDatePicker(
                        context: context, 
                        initialDate: DateTime.now(), 
                        firstDate: DateTime.now().subtract(const Duration(days: 300)), 
                        lastDate: DateTime.now(), 
                        builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: theme.colorScheme.primary, onPrimary: theme.colorScheme.onPrimary, surface: theme.colorScheme.surface, onSurface: theme.colorScheme.onSurface)), child: child!)
                      );
                      
                      if (picked != null) { 
                        updates['pregnancyStartDate'] = Timestamp.fromDate(picked); 
                        updates['isPregnant'] = true; 
                      } else { 
                        return; 
                      }
                    } else { 
                      updates['isPregnant'] = false; 
                    }
                    await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);
                  }
                },
              )),
            ],
          ),
        ),
      )
    );
  }

  void _showOvulationDialog(ThemeData theme) {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), 
        backgroundColor: theme.colorScheme.surface,
        title: Text("День овуляции", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Оставьте пустым для авторасчета.", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
            TextField(
              controller: controller, 
              keyboardType: TextInputType.number, 
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: "Например: 14", 
                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary))
              ), 
              cursorColor: theme.colorScheme.primary
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () { 
              final uid = FirebaseAuth.instance.currentUser?.uid; 
              if (uid != null) {
                FirebaseFirestore.instance.collection('users').doc(uid).update({'manualOvulationDay': FieldValue.delete()}); 
              }
              Navigator.pop(ctx); 
            }, 
            child: Text("Авторасчет", style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () {
              final int? newDay = int.tryParse(controller.text);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (newDay != null && newDay > 0 && newDay < 60 && uid != null) {
                FirebaseFirestore.instance.collection('users').doc(uid).update({'manualOvulationDay': newDay});
              }
              Navigator.pop(ctx);
            },
            child: Text("Сохранить", style: TextStyle(color: theme.colorScheme.onPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    if (uid == null) {
      return Scaffold(backgroundColor: theme.scaffoldBackgroundColor);
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Гармония', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)), 
            const SizedBox(width: 8), 
            Icon(Icons.spa, color: theme.colorScheme.primary, size: 28)
          ]
        ),
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.bar_chart_rounded, color: theme.colorScheme.primary, size: 28), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HarmonyOverviewScreen())),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (context, snapshot) {
              final userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              return IconButton(icon: Icon(Icons.settings, color: theme.colorScheme.primary), onPressed: () => _showSettingsSheet(userData, theme));
            }
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
          }
          
          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          
          final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
          final Timestamp? lastEndTs = userData['lastPeriodEndDate'] as Timestamp?;
          final Timestamp? pregStartTs = userData['pregnancyStartDate'] as Timestamp?;
          final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
          final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
          final int? manualOvulationDay = userData['manualOvulationDay'] as int?;
          final bool isPregnantLegacy = userData['isPregnant'] ?? false;
          String appMode = userData['appMode'] ?? (isPregnantLegacy ? 'pregnancy' : 'standard');

          double globalWeight = userData['weight'] != null ? (userData['weight'] as num).toDouble() : 60.0;

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

          return SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                  padding: const EdgeInsets.all(20), 
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface, 
                    borderRadius: BorderRadius.circular(24), 
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))
                    ]
                  ),
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          dayInfo.title, 
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dayInfo.description, 
                        textAlign: TextAlign.center, 
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w500)
                      ),
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16), 
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface, 
                    borderRadius: BorderRadius.circular(24), 
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))
                    ]
                  ),
                  child: HarmonyCalendar(
                    userData: userData,
                    onDaySelected: (selectedDay, uData) {
                      setState(() => _selectedDay = selectedDay);
                      _loadDayLogs(selectedDay);

                      final cheatStatus = CycleCalculator.getCheatStatus(targetDate: selectedDay, userData: uData);
                      if (cheatStatus == 'cheat_day') {
                        HarmonyBottomSheets.showInfoSheet(context: context, title: "Прислушайся к себе ✨", description: "Сейчас 26-й день цикла. Позволь себе любимую еду без чувства вины.");
                      } else if (cheatStatus == 'cheat_meal') {
                        HarmonyBottomSheets.showInfoSheet(context: context, title: "Воскресенье — день для души ✨", description: "Ты можешь позволить себе любимые блюда без угрызений совести.");
                      }

                      HarmonyBottomSheets.showDayActionSheet(
                        context: context, 
                        day: selectedDay, 
                        userData: uData,
                        onSymptomsTap: () => HarmonySymptomsSheet.show(
                          context: context, 
                          selectedDay: _selectedDay, 
                          currentSymptoms: _currentDaySymptoms, 
                          onSave: (map) => setState(() => _currentDaySymptoms = map),
                        ),
                        onMoodTap: () => HarmonyMoodSheet.show(
                          context: context, 
                          selectedDay: _selectedDay, 
                          currentMoods: _currentMoods, 
                          onSave: (list) => setState(() => _currentMoods = list),
                        ),
                        onTempTap: () => HarmonyBottomSheets.showTemperatureSheet(
                          context: context, 
                          currentTemp: _currentTemperature, 
                          onSave: (val) {
                            setState(() => _currentTemperature = val);
                            final docId = "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";
                            FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'temperature': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                          }
                        ),
                        onWeightTap: () => HarmonyBottomSheets.showWeightSheet(
                          context: context, 
                          currentWeight: _currentWeight ?? globalWeight, 
                          onSave: (val) async {
                            final msg = ScaffoldMessenger.of(context);
                            setState(() => _currentWeight = val);
                            final docId = "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";
                            await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'weight': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                            await FirebaseFirestore.instance.collection('users').doc(uid).update({'weight': val});

                            final int? age = userData['age'] as int?;
                            final double? height = (userData['height'] as num?)?.toDouble();
                            final String goal = userData['goal'] ?? 'Похудеть';
                            final String activity = userData['activityLevel'] ?? 'Умеренная (1-2 тренировки)';
                            
                            if (age != null && height != null) {
                              await CalculationService().recalculateAndSaveGoals(weight: val, height: height, age: age, goal: goal, activityLevel: activity, isPregnant: goal == 'Здоровая беременность');
                              if (!mounted) return;
                              msg.showSnackBar(SnackBar(content: const Text('Вес и КБЖУ успешно обновлены! ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: theme.colorScheme.primary));
                            }
                          }
                        ),
                        onSexTap: () => HarmonyBottomSheets.showSexSheet(
                          context: context,
                          currentData: _currentSexData,
                          currentOrgasmCount: _currentOrgasmCount,
                          // ИСПРАВЛЕНИЕ: Переименовали переменную, чтобы избежать конфликта (avoid_types_as_parameter_names)
                          onSave: (list, orgasms) {
                            setState(() {
                              _currentSexData = list;
                              _currentOrgasmCount = orgasms;
                            });
                            final docId = "${_selectedDay.year}-${_selectedDay.month.toString().padLeft(2, '0')}-${_selectedDay.day.toString().padLeft(2, '0')}";
                            FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'sex_data': list, 'orgasm_count': orgasms, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                          }
                        ),
                        onMedsTap: () => HarmonyMedsSheet.show(
                          context: context, 
                          selectedDay: _selectedDay, 
                          currentMeds: _currentMeds, 
                          onSave: (list) => setState(() => _currentMeds = list),
                        ),
                      );
                    },
                  ),
                ),

                GestureDetector(
                  onTap: _openEvaChat, 
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20), 
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface, 
                      borderRadius: BorderRadius.circular(20), 
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 1), 
                      boxShadow: [
                        BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                      ]
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10), 
                          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle), 
                          child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 24)
                        ),
                        const SizedBox(width: 16),
                        Expanded(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, 
    children: [
      Text('Ева ✨', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)), 
      const SizedBox(height: 2), 
      Text('Твой личный ИИ-ассистент', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500))
    ]
  )
),
                        Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          );
        }
      ),
    );
  }
}