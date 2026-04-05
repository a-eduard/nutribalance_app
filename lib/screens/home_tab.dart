import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/database_service.dart';
import 'shopping_list_screen.dart';
import 'meal_detail_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _lavenderColor = Color(0xFFB6A6CA); 
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);
  static const Color _bgColor = Color(0xFFF9F9F9);

  DateTime _selectedDate = DateTime.now();

  // === OPTIMISTIC UI: ЛОКАЛЬНЫЙ ЧЕРНЫЙ СПИСОК УДАЛЕННЫХ БЛЮД ===
  // Храним ID удаленных блюд, чтобы интерфейс реагировал мгновенно, не дожидаясь базы данных.
  final Set<String> _optimisticDeletedIds = {};

  @override
  bool get wantKeepAlive => true;

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
    "Слушай свое тело, оно знает лучше 🌸"
  ];

  String _getAffirmationForToday() {
    int dayIndex = DateTime.now().weekday % _affirmations.length;
    return _affirmations[dayIndex];
  }

  String _getCheatStatus(DateTime day, Map<String, dynamic> userData) {
    if (userData['isPregnant'] == true || userData['goal'] == 'Здоровая беременность') return 'none';

    final lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

    bool isCheatDay = false;
    bool isCheatMeal = day.weekday == DateTime.sunday;

    if (lastStartTs != null) {
      final start = DateTime(lastStartTs.toDate().year, lastStartTs.toDate().month, lastStartTs.toDate().day);
      final current = DateTime(day.year, day.month, day.day);
      final int diff = current.difference(start).inDays;
      if (diff >= 0 && (diff % cycleLength) + 1 == 26) isCheatDay = true;
    }

    if (isCheatDay) return 'cheat_day';
    if (isCheatMeal) return 'cheat_meal';
    return 'none';
  }

  void _showCheatMealSheet() {
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Воскресенье — день для души ✨", style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center), const SizedBox(height: 16), const Text("В этот день мы не строги к себе. Ты можешь позволить себе любимые блюда без угрызений совести и жесткого контроля.", textAlign: TextAlign.center, style: TextStyle(color: _subTextColor, fontSize: 15, height: 1.4)), const SizedBox(height: 24), SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () => Navigator.pop(ctx), child: const Text("Понятно 🌸", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))))]))));
  }

  void _showCheatDaySheet() {
    showModalBottomSheet(context: context, backgroundColor: Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("🎂", style: TextStyle(fontSize: 64)), const SizedBox(height: 16), const Text("День заботы о себе!", style: TextStyle(color: _textColor, fontSize: 22, fontWeight: FontWeight.w900), textAlign: TextAlign.center), const SizedBox(height: 12), const Text("Сегодня твой организм отдыхает. Никакого жесткого подсчета калорий, только гармония и комфорт 🌸", textAlign: TextAlign.center, style: TextStyle(color: _subTextColor, fontSize: 15, height: 1.4)), const SizedBox(height: 24), SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _lavenderColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0), onPressed: () => Navigator.pop(ctx), child: const Text("ОТЛИЧНО", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0))))]))));
  }

  void _showEditWeightDialog(BuildContext context, Map<String, dynamic> item) {
    final TextEditingController weightController = TextEditingController(text: item['weight_g'].toString());
    bool isSaving = false;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Изменить порцию', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item['name'], style: const TextStyle(color: _accentColor, fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 16), TextField(controller: weightController, keyboardType: TextInputType.number, style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900), decoration: const InputDecoration(labelText: 'Вес (граммы)', labelStyle: TextStyle(color: _subTextColor), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor, width: 2)), suffixText: 'г', suffixStyle: TextStyle(color: _textColor, fontSize: 20)), cursorColor: _accentColor)]),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _accentColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: isSaving ? null : () async {
                  final newWeight = int.tryParse(weightController.text.trim());
                  if (newWeight != null && newWeight > 0) {
                    setStateDialog(() => isSaving = true);
                    try { await DatabaseService().updateMealItemWeight(item, newWeight); if (context.mounted) Navigator.pop(ctx); } catch (e) { setStateDialog(() => isSaving = false); }
                  }
                },
                child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // === РЕАКТИВНОЕ РЕДАКТИРОВАНИЕ ЦЕЛЕЙ (КАЛОРИИ И БЖУ) ===
  void _showEditGoalDialog(int currentCals, int currentP, int currentF, int currentC) {
    final TextEditingController calsCtrl = TextEditingController(text: currentCals.toString());
    final TextEditingController protCtrl = TextEditingController(text: currentP.toString());
    final TextEditingController fatCtrl = TextEditingController(text: currentF.toString());
    final TextEditingController carbsCtrl = TextEditingController(text: currentC.toString());

    bool isAutoUpdating = false;
    bool isSaving = false;

    // Вычисляем текущие пропорции макросов (в долях от калорий), 
    // чтобы при изменении общей калорийности сохранить баланс БЖУ.
    double pRatio = currentCals > 0 ? (currentP * 4) / currentCals : 0.3;
    double fRatio = currentCals > 0 ? (currentF * 9) / currentCals : 0.3;
    double cRatio = currentCals > 0 ? (currentC * 4) / currentCals : 0.4;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {

          // Если меняем общую калорийность -> пересчитываем БЖУ
          void updateFromCals(String val) {
            if (isAutoUpdating) return;
            int? newCals = int.tryParse(val);
            if (newCals != null && newCals > 0) {
              isAutoUpdating = true; // Ставим предохранитель
              protCtrl.text = ((newCals * pRatio) / 4).round().toString();
              fatCtrl.text = ((newCals * fRatio) / 9).round().toString();
              carbsCtrl.text = ((newCals * cRatio) / 4).round().toString();
              isAutoUpdating = false; // Снимаем предохранитель
            }
          }

          // Если меняем макросы руками -> пересчитываем общие калории
          void updateFromMacros(String _) {
            if (isAutoUpdating) return;
            int p = int.tryParse(protCtrl.text) ?? 0;
            int f = int.tryParse(fatCtrl.text) ?? 0;
            int c = int.tryParse(carbsCtrl.text) ?? 0;
            
            isAutoUpdating = true; // Ставим предохранитель
            calsCtrl.text = ((p * 4) + (f * 9) + (c * 4)).toString();
            
            // Обновляем новые пропорции на будущее
            int newCals = int.tryParse(calsCtrl.text) ?? 1;
            pRatio = (p * 4) / newCals;
            fRatio = (f * 9) / newCals;
            cRatio = (c * 4) / newCals;
            isAutoUpdating = false; // Снимаем предохранитель
          }

          Widget buildField(String label, TextEditingController ctrl, Function(String) onChanged, Color color) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: onChanged,
                  style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
                  ),
                  cursorColor: color,
                ),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Ваша норма', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Измените калории, и БЖУ пересчитаются сами. Или настройте макросы вручную.", style: TextStyle(color: _subTextColor, fontSize: 12, height: 1.4)),
                const SizedBox(height: 16),
                
                // Главное поле - Калории
                TextField(
                  controller: calsCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: updateFromCals,
                  style: const TextStyle(color: _accentColor, fontSize: 32, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(
                    labelText: 'Калории',
                    labelStyle: TextStyle(color: _subTextColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor, width: 2)),
                    suffixText: 'ккал',
                    suffixStyle: TextStyle(color: _textColor, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Ряд с БЖУ
                Row(
                  children: [
                    buildField('Белки (г)', protCtrl, updateFromMacros, const Color(0xFFD49A89)),
                    buildField('Жиры (г)', fatCtrl, updateFromMacros, const Color(0xFFE5C158)),
                    buildField('Углеводы (г)', carbsCtrl, updateFromMacros, const Color(0xFF89CFF0)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx), 
                child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor, 
                  foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: isSaving ? null : () async {
                  final c = int.tryParse(calsCtrl.text) ?? 0;
                  final p = int.tryParse(protCtrl.text) ?? 0;
                  final f = int.tryParse(fatCtrl.text) ?? 0;
                  final cb = int.tryParse(carbsCtrl.text) ?? 0;

                  if (c > 0) {
                    setStateDialog(() => isSaving = true);
                    try {
                      await DatabaseService().saveNutritionGoal({
                        'calories': c,
                        'protein': p,
                        'fat': f,
                        'carbs': cb,
                      });
                      if (context.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setStateDialog(() => isSaving = false);
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent));
                    }
                  }
                },
                child: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
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
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(includeMetadataChanges: true),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) return const Center(child: Text("Ошибка загрузки профиля"));
        if (userSnapshot.connectionState == ConnectionState.waiting && !userSnapshot.hasData) return const Center(child: CircularProgressIndicator(color: _accentColor));
        if (!userSnapshot.hasData || !userSnapshot.data!.exists) return const Center(child: Text("Данные не найдены"));

        final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
        final String name = userData['name']?.toString() ?? 'Красотка';

        return SafeArea(
          top: true, bottom: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Привет, $name ✨", style: const TextStyle(color: _textColor, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    IconButton(icon: Image.asset('assets/icons/bag.png', width: 24, height: 24, color: _textColor), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen()))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, _accentColor.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16), border: Border.all(color: _accentColor.withValues(alpha: 0.1), width: 1), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Text(_getAffirmationForToday(), style: const TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(height: 16),
              _buildCompactCalendar(userData),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWaterWidget(uid),
                      const SizedBox(height: 24),
                      _buildNutritionDashboard(uid),
                      const SizedBox(height: 32),
                      const Text("История", style: TextStyle(color: _textColor, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 16),
                      _buildDiaryList(uid),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactCalendar(Map<String, dynamic> userData) {
    final today = DateTime.now();
    final monday = today.subtract(Duration(days: today.weekday - 1));

    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 24, right: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (index) {
          final date = monday.add(Duration(days: index));
          final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month;
          final String cheatStatus = _getCheatStatus(date, userData);
          String iconStr = '';
          if (cheatStatus == 'cheat_day') iconStr = '🎂';
          else if (cheatStatus == 'cheat_meal') iconStr = '🍪';

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = date);
              if (cheatStatus == 'cheat_meal') _showCheatMealSheet();
              else if (cheatStatus == 'cheat_day') _showCheatDaySheet();
            },
            child: Column(
              children: [
                Text(DateFormat('E', 'ru').format(date).toUpperCase().substring(0, 1), style: const TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: isSelected ? _accentColor : Colors.transparent, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: iconStr.isNotEmpty ? Text(iconStr, style: const TextStyle(fontSize: 18)) : Text(date.day.toString(), style: TextStyle(color: isSelected ? Colors.white : _textColor, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNutritionDashboard(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('nutrition_goal').doc('current').snapshots(includeMetadataChanges: true),
      builder: (context, goalSnapshot) {
        if (goalSnapshot.hasError) return const SizedBox.shrink(); 
        final goalData = goalSnapshot.data?.data() as Map<String, dynamic>?;
        int targetCals = goalData?['calories'] ?? 0;
        final int targetP = goalData?['protein'] ?? 0;
        final int targetF = goalData?['fat'] ?? 0;
        final int targetC = goalData?['carbs'] ?? 0;
        final int targetFiber = 25; 

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_docId).snapshots(includeMetadataChanges: true),
          builder: (context, mealSnapshot) { 
            if (mealSnapshot.hasError) return const Center(child: Text("Ошибка загрузки данных"));

            // === OPTIMISTIC UI: ЖИВОЙ ПЕРЕСЧЕТ КАЛОРИЙ ИЗ СПИСКА ===
            int curC = 0, curP = 0, curF = 0, curCarb = 0, bonusCals = 0, curFiber = 0;
            double totalHealthScore = 0;
            int mealsCount = 0;

            if (mealSnapshot.hasData && mealSnapshot.data!.exists) {
              final data = mealSnapshot.data!.data() as Map<String, dynamic>? ?? {};
              bonusCals = (data['bonus_calories'] as num?)?.toInt() ?? 0;
              curC = bonusCals; // Сразу добавляем бонусы

              final List<dynamic> rawItems = data['items'] ?? [];
              
              // 1. Отбрасываем блюда, которые пользователь локально удалил
              final List<dynamic> activeItems = rawItems.where((item) => !_optimisticDeletedIds.contains(item['id'].toString())).toList();

              // 2. Считаем макросы на лету!
              for (var item in activeItems) {
                if (item is Map<String, dynamic>) {
                  curC += (item['calories'] as num?)?.toInt() ?? 0;
                  curP += (item['protein'] as num?)?.toInt() ?? 0;
                  curF += (item['fat'] as num?)?.toInt() ?? 0;
                  curCarb += (item['carbs'] as num?)?.toInt() ?? 0;
                  curFiber += (item['fiber'] as num?)?.toInt() ?? 0;

                  if (item.containsKey('health_score') && item['health_score'] != null) {
                    totalHealthScore += (item['health_score'] as num).toDouble();
                    mealsCount++;
                  }
                }
              }
            }

            final int avgHealthScore = mealsCount > 0 ? (totalHealthScore / mealsCount).round() : 0;
            targetCals += bonusCals;
            bool isExceeded = targetCals > 0 && curC > targetCals;
            final Color activeColor = isExceeded ? _lavenderColor : _accentColor;

            // Оборачиваем в GestureDetector для открытия настроек
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                // Передаем ЧИСТУЮ цель из базы данных (без бонусов за читмил), чтобы юзер редактировал базу
                final int baseTargetCals = goalData?['calories'] ?? 0;
                _showEditGoalDialog(baseTargetCals, targetP, targetF, targetC);
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('КАЛОРИИ ЗА СЕГОДНЯ', style: TextStyle(color: activeColor, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
                      if (mealsCount > 0)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: _accentColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.favorite, color: _accentColor, size: 12), const SizedBox(width: 4), Text("Польза $avgHealthScore/10", style: const TextStyle(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold))]))
                      else if (bonusCals > 0)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text("+$bonusCals бонус", style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('$curC', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : _textColor, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                      Text(' / $targetCals ккал', style: const TextStyle(color: _subTextColor, fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(isExceeded ? 'Сверх нормы ✨' : 'Калорий употреблено', style: TextStyle(color: isExceeded ? const Color(0xFFB6A6CA) : _subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _buildMacroBar("Белки", curP, targetP, activeColor), const SizedBox(width: 8),
                      _buildMacroBar("Жиры", curF, targetF, const Color(0xFFE5C158)), const SizedBox(width: 8),
                      _buildMacroBar("Углеводы", curCarb, targetC, const Color(0xFF89CFF0)), const SizedBox(width: 8),
                      _buildMacroBar("Клетчатка", curFiber, targetFiber, Colors.green[300] ?? Colors.green),
                    ],
                  )
                ],
              ),
            )
            ); // <-- Закрыли GestureDetector
          },
        );
      }
    );
  }

 Widget _buildMacroBar(String label, int current, int target, Color activeColor) {
    double progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(label, style: const TextStyle(color: _textColor, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(height: 6),
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: activeColor), duration: const Duration(milliseconds: 500),
            builder: (context, color, child) { return ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(value: progress, backgroundColor: const Color(0xFFF9F9F9), valueColor: AlwaysStoppedAnimation<Color>(color ?? _accentColor), minHeight: 6)); },
          ),
          const SizedBox(height: 6),
          RichText(text: TextSpan(children: [TextSpan(text: '$current', style: const TextStyle(color: _textColor, fontSize: 11, fontWeight: FontWeight.w800)), TextSpan(text: '/$target г', style: const TextStyle(color: _subTextColor, fontSize: 10, fontWeight: FontWeight.w500))])),
        ],
      ),
    );
  }

  Widget _buildDiaryList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_docId).snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("Ошибка загрузки дневника")); 
        if (!snapshot.hasData || !snapshot.data!.exists) return _buildEmptyState();

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> rawItems = data['items'] ?? [];

        // === OPTIMISTIC UI: ОТОБРАЖАЕМ ТОЛЬКО АКТИВНЫЕ БЛЮДА ===
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
                // Никаких лоадеров! Просто быстрый вопрос.
                return await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      title: const Text("Удалить запись?", style: TextStyle(color: _textColor, fontWeight: FontWeight.w900)),
                      content: const Text("Ты уверена, что хочешь удалить этот прием пищи?", style: TextStyle(color: _subTextColor, fontSize: 15)),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Отмена", style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold))),
                        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Удалить", style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.bold))),
                      ],
                    );
                  },
                ) ?? false;
              },
              onDismissed: (_) { 
                // 1. МГНОВЕННОЕ ЛОКАЛЬНОЕ УДАЛЕНИЕ (OPTIMISTIC UI)
                // Юзер видит, как калории пересчитываются прямо на его глазах, за долю секунды.
                setState(() {
                  _optimisticDeletedIds.add(item['id'].toString());
                });

                // 2. ОТПРАВЛЯЕМ ФОНОВЫЙ ПРИКАЗ БАЗЕ
                // Мы больше не ждем сервер. Если он завис - нам все равно.
                DatabaseService().deleteMealItem(item, List.from(rawItems), _docId).catchError((e) {
                  debugPrint("Фоновая БД тупит: $e"); // Молча игнорируем, не пугаем юзера.
                });
                
                // 3. ПОКАЗЫВАЕМ УВЕДОМЛЕНИЕ
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                messenger.showSnackBar(SnackBar(content: const Text('Блюдо удалено ✨', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16), textAlign: TextAlign.center), backgroundColor: _accentColor, behavior: SnackBarBehavior.floating, elevation: 10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24), duration: const Duration(seconds: 2)));
              },
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (isGrouped) Navigator.push(context, MaterialPageRoute(builder: (_) => MealDetailScreen(mealData: item, dateDocId: _docId)));
                  else _showEditWeightDialog(context, item);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Container(width: 56, height: 56, decoration: BoxDecoration(color: _bgColor, borderRadius: BorderRadius.circular(16)), child: isValidUrl ? ClipRRect(borderRadius: BorderRadius.circular(16), child: CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover)) : const Icon(Icons.restaurant, color: Color(0xFFC7C7CC), size: 28)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['name'] ?? 'Прием пищи', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _textColor, fontSize: 15, fontWeight: FontWeight.w800))), Text(timeStr, style: const TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.w500))]),
                            const SizedBox(height: 4),
                            Text("${item['calories']} Калории", style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            Row(children: [_buildMiniBadge('P', item['protein'], const Color(0xFFD49A89)), const SizedBox(width: 10), _buildMiniBadge('F', item['fat'], const Color(0xFFE5C158)), const SizedBox(width: 10), _buildMiniBadge('C', item['carbs'], const Color(0xFF89CFF0))]),
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
      }
    );
  }

  Widget _buildMiniBadge(String letter, dynamic value, Color color) {
    return Row(children: [Container(width: 16, height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))), const SizedBox(width: 6), Text('${value ?? 0}г', style: const TextStyle(color: _textColor, fontSize: 12, fontWeight: FontWeight.bold))]);
  }

  Widget _buildWaterWidget(String uid) {
    return OptimisticWaterWidget(uid: uid, docId: _docId);
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE5E5EA), width: 1, style: BorderStyle.solid)),
      child: Column(children: [Icon(Icons.restaurant_outlined, size: 64, color: _subTextColor.withValues(alpha: 0.3)), const SizedBox(height: 16), const Text("Дневник пуст", style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text("Нажми на кнопку внизу экрана,\nчтобы записать свой первый прием", textAlign: TextAlign.center, style: TextStyle(color: _subTextColor, fontSize: 14, fontWeight: FontWeight.w500))]),
    );
  }
}

class OptimisticWaterWidget extends StatefulWidget {
  final String uid; final String docId;
  const OptimisticWaterWidget({super.key, required this.uid, required this.docId});
  @override
  State<OptimisticWaterWidget> createState() => _OptimisticWaterWidgetState();
}

class _OptimisticWaterWidgetState extends State<OptimisticWaterWidget> {
  int _glasses = 0; bool _isOptimistic = false;
  static const Color _textColor = Color(0xFF2D2D2D); static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('meals').doc(widget.docId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (snapshot.hasData && snapshot.data!.exists) {
          int serverGlasses = (snapshot.data!.data() as Map<String, dynamic>?)?['water_glasses']?.toInt() ?? 0;
          if (!_isOptimistic) { _glasses = serverGlasses; } else if (serverGlasses == _glasses) { _isOptimistic = false; }
        }
        return Container(
          padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Выпито воды", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(8, (index) {
                  bool isFilled = index < _glasses;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact(); int newCount = isFilled ? index : index + 1;
                      setState(() { _glasses = newCount; _isOptimistic = true; });
                      DatabaseService().updateWaterGlasses(newCount);
                    },
                    child: AnimatedContainer(duration: const Duration(milliseconds: 200), curve: Curves.easeInOut, transform: Matrix4.identity()..scale(isFilled ? 1.15 : 1.0), transformAlignment: Alignment.center, child: Icon(Icons.water_drop, color: isFilled ? Colors.lightBlueAccent : const Color(0xFFE5E5EA), size: 30)),
                  );
                }),
              ),
              const SizedBox(height: 12), Center(child: Text("$_glasses из 8 стаканов (0.3 л)", style: const TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
            ],
          ),
        );
      },
    );
  }
}