import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/database_service.dart';
import '../services/calculation_service.dart';
import 'shopping_list_screen.dart';
import 'meal_detail_screen.dart';
import '../widgets/dashboard/nutrition_card.dart';
import 'ai_chat_screen.dart'; // Добавлен импорт для чата с Евой

import 'harmony/widgets/harmony_bottom_sheets.dart';
import 'harmony/widgets/harmony_symptoms_sheet.dart';
import 'harmony/widgets/harmony_mood_sheet.dart';
import 'harmony/widgets/harmony_meds_sheet.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  final Set<String> _optimisticDeletedIds = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        setState(() => _selectedDate = now);
      } else {
        setState(() {});
      }
    }
  }

  String get _docId {
    return "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";
  }

  final List<String> _affirmations = [
    "Твой вес — это не твоя ценность ✨",
    "Фокус на балансе и любви к себе 🌸",
    "Сегодня отличный день, чтобы выдохнуть 🌿",
    "Еда — это энергия, а не враг 🤍",
    "Ты прекрасна на любом этапе своего пути 🦋",
    "Каждый шаг к здоровью имеет значение 🕊️",
    "Слушай свое тело, оно знает лучше 🌸",
  ];

  String _getAffirmationForToday() {
    return _affirmations[DateTime.now().weekday % _affirmations.length];
  }

  String _getFormattedDate() {
    final str = DateFormat('EEEE, d MMMM', 'ru').format(_selectedDate);
    if (str.isEmpty) return "";
    return "${str[0].toUpperCase()}${str.substring(1)}";
  }

  void _openEvaChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')),
    );
  }

  Future<void> _openDailyTracker(Map<String, dynamic> userData) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final docSnap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(_docId).get();
    final data = docSnap.exists ? docSnap.data()! : {};

    Map<String, int> currentSymptoms = {};
    if (data['symptoms'] is Map) {
      currentSymptoms = (data['symptoms'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    }
    
    List<String> currentMoods = [];
    if (data['moods'] is List) {
      currentMoods = List<String>.from(data['moods']);
    } else if (data['mood'] is String && data['mood'].toString().isNotEmpty) {
      currentMoods = [data['mood'].toString()];
    }
    
    List<String> currentMeds = List<String>.from(data['meds'] ?? []);
    List<String> currentSexData = List<String>.from(data['sex_data'] ?? []);
    int currentOrgasmCount = data['orgasm_count'] != null ? (data['orgasm_count'] as num).toInt() : 0;
    
    double? currentTemp = data['temperature'] != null ? (data['temperature'] as num).toDouble() : null;
    double globalWeight = userData['weight'] != null ? (userData['weight'] as num).toDouble() : 60.0;
    double? currentWeight = data['weight'] != null ? (data['weight'] as num).toDouble() : globalWeight;

    if (!mounted) return;

    HarmonyBottomSheets.showDayActionSheet(
      context: context, 
      day: _selectedDate, 
      userData: userData,
      onSymptomsTap: () => HarmonySymptomsSheet.show(
        context: context, selectedDay: _selectedDate, currentSymptoms: currentSymptoms, 
        onSave: (map) {} 
      ),
      onMoodTap: () => HarmonyMoodSheet.show(
        context: context, selectedDay: _selectedDate, currentMoods: currentMoods, 
        onSave: (list) {} 
      ),
      onTempTap: () => HarmonyBottomSheets.showTemperatureSheet(
        context: context, currentTemp: currentTemp, 
        onSave: (val) {
          FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(_docId).set({'temperature': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      ),
      onWeightTap: () => HarmonyBottomSheets.showWeightSheet(
        context: context, currentWeight: currentWeight, 
        onSave: (val) async {
          final msg = ScaffoldMessenger.of(context);
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(_docId).set({'weight': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          await FirebaseFirestore.instance.collection('users').doc(uid).update({'weight': val});

          final int? age = userData['age'] as int?;
          final double? height = (userData['height'] as num?)?.toDouble();
          final String goal = userData['goal'] ?? 'Похудеть';
          final String activity = userData['activityLevel'] ?? 'Умеренная (1-2 тренировки)';
          
          if (age != null && height != null) {
            await CalculationService().recalculateAndSaveGoals(weight: val, height: height, age: age, goal: goal, activityLevel: activity, isPregnant: goal == 'Здоровая беременность');
            if (mounted) {
              msg.showSnackBar(SnackBar(content: const Text('Вес и КБЖУ обновлены! ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Theme.of(context).colorScheme.primary));
            }
          }
        }
      ),
      onSexTap: () => HarmonyBottomSheets.showSexSheet(
        context: context, currentData: currentSexData, currentOrgasmCount: currentOrgasmCount,
        onSave: (list, orgasmCount) {
          FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(_docId).set({'sex_data': list, 'orgasm_count': orgasmCount, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      ),
      onMedsTap: () => HarmonyMedsSheet.show(
        context: context, selectedDay: _selectedDate, currentMeds: currentMeds, 
        onSave: (list) {}
      ),
    );
  }

  void _showEditWeightDialog(BuildContext context, Map<String, dynamic> item) {
    final TextEditingController weightController = TextEditingController(text: item['weight_g'].toString());
    bool isSaving = false;
    final theme = Theme.of(context);

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: theme.colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Изменить порцию', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'], style: TextStyle(color: theme.colorScheme.primary, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController, keyboardType: TextInputType.number,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    labelText: 'Вес (граммы)', 
                    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant), 
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2))), 
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)), 
                    suffixText: 'г', 
                    suffixStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20)
                  ),
                  cursorColor: theme.colorScheme.primary,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: theme.colorScheme.onPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: isSaving ? null : () async {
                  final newWeight = int.tryParse(weightController.text.trim());
                  if (newWeight != null && newWeight > 0) {
                    setStateDialog(() => isSaving = true);
                    final nav = Navigator.of(ctx);
                    try {
                      await DatabaseService().updateMealItemWeight(item, newWeight);
                      if (mounted) nav.pop();
                    } catch (e) { 
                      setStateDialog(() => isSaving = false); 
                    }
                  }
                },
                child: isSaving ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: theme.colorScheme.onPrimary, strokeWidth: 2)) : Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    if (uid == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(includeMetadataChanges: true),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) {
          return const Center(child: Text("Ошибка загрузки профиля"));
        }
        if (userSnapshot.connectionState == ConnectionState.waiting && !userSnapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
        }
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          return const Center(child: Text("Данные не найдены"));
        }

        final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
        final String name = userData['name']?.toString() ?? 'Красотка';

        return SafeArea(
          top: true, bottom: true,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Привет, $name ✨", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('shopping_list').snapshots(),
                        builder: (context, cartSnapshot) {
                          bool hasItems = false;
                          if (cartSnapshot.hasData && cartSnapshot.data!.docs.isNotEmpty) {
                            for (var doc in cartSnapshot.data!.docs) {
                              final data = doc.data() as Map<String, dynamic>;
                              final categories = data['categories'] as List<dynamic>? ?? [];
                              if (categories.isNotEmpty) { 
                                hasItems = true; 
                                break; 
                              }
                            }
                          }
                          return Badge(
                            isLabelVisible: hasItems, backgroundColor: Colors.redAccent, smallSize: 10, offset: const Offset(-2, 2), 
                            child: IconButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen())),
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(), 
                              icon: Image.asset('assets/icons/bag.png', width: 32, height: 32, color: theme.colorScheme.onSurface),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.colorScheme.surface, theme.colorScheme.primary.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16), border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
                    child: Text(_getAffirmationForToday(), style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 24),
                
                Center(
                  child: Text(
                    _getFormattedDate(),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface, 
                      fontSize: 20, 
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                _buildCycleRingWidget(userData),
                
                const SizedBox(height: 16),
                _buildEvaChatButton(), // Новый премиальный чат с Евой
                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWaterWidget(uid),
                      const SizedBox(height: 24),
                      NutritionSummaryCard(uid: uid, docId: _docId, optimisticDeletedIds: _optimisticDeletedIds),
                      const SizedBox(height: 32),
                      Text("История", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 16),
                      _buildDiaryList(uid),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Обновленный премиум-виджет кольца
  Widget _buildCycleRingWidget(Map<String, dynamic> userData) {
    final theme = Theme.of(context);
    final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
    final String appMode = userData['appMode'] ?? (userData['isPregnant'] == true ? 'pregnancy' : 'standard');
    final int? manualOvulationDay = userData['manualOvulationDay'] as int?;
    
    int currentDay = 1;
    String phaseText = "Настройка";
    
    if (lastStartTs != null) {
      final start = DateTime(lastStartTs.toDate().year, lastStartTs.toDate().month, lastStartTs.toDate().day);
      final now = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final int diff = now.difference(start).inDays;
      if (diff >= 0) {
        currentDay = (diff % cycleLength) + 1;
        
        if (currentDay <= periodDuration) {
          phaseText = 'Менструация';
        } else if (currentDay <= (manualOvulationDay ?? 14) - 4) {
          phaseText = 'Фолликулярная';
        } else if (currentDay <= (manualOvulationDay ?? 14) + 1) {
          phaseText = 'Овуляция';
        } else {
          phaseText = 'Лютеиновая';
        }
      }
    }

    if (appMode == 'pregnancy') {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 24), padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))]),
        child: Center(child: Text("Режим беременности 🤰", style: TextStyle(color: theme.colorScheme.primary, fontSize: 18, fontWeight: FontWeight.bold))),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(32), 
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
        ]
      ),
      child: Column(
        children: [
          // Само кольцо стало элегантнее
          SizedBox(
            width: 180, height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(180, 180),
                  painter: CycleRingPainter(
                    cycleLength: cycleLength,
                    periodDuration: periodDuration,
                    currentDay: currentDay,
                    ovulationDay: manualOvulationDay ?? 14,
                    hasData: lastStartTs != null,
                    baseColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                    primaryColor: theme.colorScheme.primary,
                    indicatorColor: theme.colorScheme.surface,
                    dotColor: theme.colorScheme.onSurface,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lastStartTs != null ? phaseText : "Цикл", style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                    Text(lastStartTs != null ? "$currentDay" : "?", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 56, fontWeight: FontWeight.w300, height: 1.1)),
                    Text("день", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                )
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Аккуратная панель кнопок снизу
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMinimalActionButton(
                icon: Icons.edit_note, 
                label: "Отметить", 
                color: theme.colorScheme.primary, 
                theme: theme, 
                onTap: () => _openDailyTracker(userData)
              ),
              _buildMinimalActionButton(
                icon: Icons.calendar_today, 
                label: "Изменить", 
                color: theme.colorScheme.onSurfaceVariant, 
                theme: theme, 
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context, 
                    initialDate: lastStartTs?.toDate() ?? DateTime.now(), 
                    firstDate: DateTime.now().subtract(const Duration(days: 365)), 
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    builder: (context, child) => Theme(data: theme, child: child!),
                  );
                  if (picked != null) {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodStartDate': Timestamp.fromDate(picked)});
                    }
                  }
                }
              ),
              _buildMinimalActionButton(
                icon: Icons.info_outline, 
                label: "Справка", 
                color: theme.colorScheme.onSurfaceVariant, 
                theme: theme, 
                onTap: () {
                  HarmonyBottomSheets.showInfoSheet(context: context, title: "Твой цикл", description: "Яркая линия — менструация. Голубая дуга — окно овуляции. Тонкое кольцо — остальные фазы.");
                }
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMinimalActionButton({required IconData icon, required String label, required Color color, required ThemeData theme, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // Новая премиальная кнопка чата с Евой
  Widget _buildEvaChatButton() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: GestureDetector(
        onTap: _openEvaChat,
        child: Container(
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
                child: Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ева ✨', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Твой личный ИИ-ассистент', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiaryList(String uid) {
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot>(
      key: ValueKey('diary_$_docId'), 
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_docId).snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Ошибка загрузки дневника"));
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState();

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> rawItems = data['items'] ?? [];
        final List<dynamic> items = rawItems.where((item) => !_optimisticDeletedIds.contains(item['id'].toString())).toList();

        if (items.isEmpty) return _buildEmptyState();

        return ListView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            if (item is! Map<String, dynamic>) return const SizedBox.shrink();

            final bool isGrouped = item['is_grouped'] == true;
            final String timeStr = item['timestamp'] != null ? DateFormat('HH:mm').format((item['timestamp'] as Timestamp).toDate()) : '';
            final String? imageUrl = item['imageUrl']?.toString();
            final bool isValidUrl = imageUrl != null && imageUrl.startsWith('http') && imageUrl.length < 1000;

            return Dismissible(
              key: Key(item['id'] ?? index.toString()),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 24), margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28)),
              confirmDismiss: (direction) async {
                return await showDialog<bool>(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          title: Text("Удалить запись?", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
                          content: Text("Ты уверена, что хочешь удалить этот прием пищи?", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("Отмена", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))),
                            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text("Удалить", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold))),
                          ],
                        );
                      },
                    ) ?? false;
              },
              onDismissed: (_) {
                setState(() => _optimisticDeletedIds.add(item['id'].toString()));
                DatabaseService().deleteMealItem(item, List.from(rawItems), _docId).catchError((e) { debugPrint("Фоновая БД тупит: $e"); });
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                messenger.showSnackBar(SnackBar(content: const Text('Блюдо удалено ✨', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16), textAlign: TextAlign.center), backgroundColor: theme.colorScheme.primary, behavior: SnackBarBehavior.floating, elevation: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24), duration: const Duration(seconds: 2)));
              },
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (isGrouped) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => MealDetailScreen(mealData: item, dateDocId: _docId)));
                  } else {
                    _showEditWeightDialog(context, item);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: isValidUrl ? theme.scaffoldBackgroundColor : theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: isValidUrl ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover) : (imageUrl != null && imageUrl.startsWith('assets/')) ? Padding(padding: const EdgeInsets.all(8.0), child: Image.asset(imageUrl, fit: BoxFit.contain)) : Icon(Icons.restaurant, color: theme.colorScheme.primary, size: 28),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['name'] ?? 'Прием пищи', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.w800))), Text(timeStr, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500))]),
                            const SizedBox(height: 4), Text("${item['calories']} Калории", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildMiniBadge('P', item['protein'], theme.colorScheme.secondary), const SizedBox(width: 10),
                                _buildMiniBadge('F', item['fat'], const Color(0xFFE5C158)), const SizedBox(width: 10),
                                _buildMiniBadge('C', item['carbs'], const Color(0xFF89CFF0)), const SizedBox(width: 10),
                                _buildMiniBadge('K', item['fiber'], Colors.green[300] ?? Colors.green),
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
          },
        );
      },
    );
  }

  Widget _buildMiniBadge(String letter, dynamic value, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
        const SizedBox(width: 6), Text('${value ?? 0}г', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWaterWidget(String uid) {
    return OptimisticWaterWidget(key: ValueKey('water_$_docId'), uid: uid, docId: _docId);
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2), width: 1, style: BorderStyle.solid)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/empty_diary.png', width: 240, height: 240, fit: BoxFit.contain),
          const SizedBox(height: 16),
          Text("Дневник пока пуст ✨", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          Text("Нажми на кнопку внизу экрана,\nчтобы записать свой первый прием", textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}

class OptimisticWaterWidget extends StatefulWidget {
  final String uid;
  final String docId;
  const OptimisticWaterWidget({super.key, required this.uid, required this.docId});
  @override
  State<OptimisticWaterWidget> createState() => _OptimisticWaterWidgetState();
}

class _OptimisticWaterWidgetState extends State<OptimisticWaterWidget> {
  int _glasses = 0;
  bool _isOptimistic = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('meals').doc(widget.docId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (snapshot.hasData && snapshot.data!.exists) {
          int serverGlasses = (snapshot.data!.data() as Map<String, dynamic>?)?['water_glasses']?.toInt() ?? 0;
          if (!_isOptimistic) {
            _glasses = serverGlasses;
          } else if (serverGlasses == _glasses) {
            _isOptimistic = false;
          }
        }
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Выпито воды", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(8, (index) {
                  bool isFilled = index < _glasses;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      int newCount = isFilled ? index : index + 1;
                      setState(() { _glasses = newCount; _isOptimistic = true; });
                      DatabaseService().updateWaterGlasses(newCount);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
                      transform: Matrix4.diagonal3Values(isFilled ? 1.15 : 1.0, isFilled ? 1.15 : 1.0, 1.0),
                      transformAlignment: Alignment.center,
                      child: Icon(Icons.water_drop, color: isFilled ? Colors.lightBlueAccent : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3), size: 30),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Center(child: Text("$_glasses из 8 стаканов (0.3 л)", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold))),
            ],
          ),
        );
      },
    );
  }
}

// Премиальная отрисовка тонкого кольца
class CycleRingPainter extends CustomPainter {
  final int cycleLength;
  final int periodDuration;
  final int currentDay;
  final int ovulationDay;
  final bool hasData;
  final Color baseColor;
  final Color primaryColor;
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
    required this.indicatorColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 8.0; // ИСПРАВЛЕНИЕ: Тонкая изящная линия вместо 14.0

    final paintBase = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paintBase);

    if (!hasData) return;

    final double sweepAnglePerDay = (2 * pi) / cycleLength;
    const double startAngle = -pi / 2;

    final paintPeriod = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
      
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAnglePerDay * periodDuration,
      false,
      paintPeriod,
    );

    final paintOvulation = Paint()
      ..color = const Color(0xFF89CFF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final int ovStartDay = ovulationDay - 1; 
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + (sweepAnglePerDay * (ovStartDay - 1)),
      sweepAnglePerDay * 3, 
      false,
      paintOvulation,
    );

    final currentAngle = startAngle + (sweepAnglePerDay * (currentDay - 0.5));
    final double indicatorX = center.dx + radius * cos(currentAngle);
    final double indicatorY = center.dy + radius * sin(currentAngle);

    // Добавлена мягкая тень для индикатора (эффект свечения)
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(indicatorX, indicatorY + 2), 12, shadowPaint);

    final indicatorPaintP = Paint()..color = indicatorColor;
    canvas.drawCircle(Offset(indicatorX, indicatorY), 10, indicatorPaintP);
    
    final dotPaintP = Paint()..color = dotColor;
    canvas.drawCircle(Offset(indicatorX, indicatorY), 3.5, dotPaintP);
  }

  @override
  bool shouldRepaint(covariant CycleRingPainter oldDelegate) {
    return oldDelegate.currentDay != currentDay || 
           oldDelegate.cycleLength != cycleLength || 
           oldDelegate.hasData != hasData ||
           oldDelegate.baseColor != baseColor;
  }
}