import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../../services/cycle_calculator.dart'; // ИМПОРТ ДОБАВЛЕН

class HarmonyBottomSheets {

  static final List<String> availableMoods = [
    'Отличное ✨', 'Спокойное 🌿', 'Грусть 🌧️',
    'Тревога 🌪️', 'Раздражение ⚡', 'Апатия 🌫️'
  ];

  static final List<String> availableSleep = [
    'Отлично (8+ ч)', 'Нормально (6-8 ч)',
    'Мало (<6 ч)', 'Бессонница'
  ];

  // Вспомогательный метод для определения цвета фазы
  static Color _getPhaseColor(String phaseType, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    switch (phaseType) {
      case 'menstruation': return theme.colorScheme.primary;
      case 'ovulation': return isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
      case 'fertile': return isDark ? const Color(0xFF80CBC4) : const Color(0xFF00695C);
      case 'pms': return isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
      default: return theme.colorScheme.onSurfaceVariant;
    }
  }

  static void showDayActionSheet({
    required BuildContext context,
    required DateTime day,
    required Map<String, dynamic> userData,
    required VoidCallback onSymptomsTap,
    required VoidCallback onMoodTap,
    required VoidCallback onWeightTap,
    required VoidCallback onMedsTap,
    required VoidCallback onSexTap,
    required VoidCallback onTempTap,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final theme = Theme.of(context);

    final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final Timestamp? lastEndTs = userData['lastPeriodEndDate'] as Timestamp?;
    final String appMode = userData['appMode'] ?? 'standard';
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
    final int? manualOvulationDay = userData['manualOvulationDay'] as int?;
    final Timestamp? pregStartTs = userData['pregnancyStartDate'] as Timestamp?;

    bool isStartDay = lastStartTs != null && _isSameDay(lastStartTs.toDate(), day);
    bool isEndDay = lastEndTs != null && _isSameDay(lastEndTs.toDate(), day);

    // Рассчитываем фазу цикла для выбранного дня
    final dayInfo = CycleCalculator.getDayInfo(
      targetDate: day,
      lastStartDate: lastStartTs?.toDate(),
      lastEndDate: lastEndTs?.toDate(),
      cycleLength: cycleLength,
      periodDuration: periodDuration,
      appMode: appMode,
      manualOvulationDay: manualOvulationDay,
      pregStartTs: pregStartTs,
    );

    final Color phaseColor = _getPhaseColor(dayInfo.phaseType, theme);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('dd MMMM yyyy', 'ru_RU').format(day), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            
            // ИНФОРМАЦИЯ О ФАЗЕ ЦИКЛА
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: phaseColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: phaseColor.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Text(dayInfo.title, style: TextStyle(color: phaseColor, fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(dayInfo.description, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.3, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            if (appMode != 'pregnancy' && appMode != 'menopause') ...[
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      title: isStartDay ? "Убрать начало" : "Начало периода",
                      icon: Icons.water_drop,
                      isActive: isStartDay,
                      theme: theme,
                      onTap: () {
                        if (isStartDay) {
                          FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodStartDate': FieldValue.delete()});
                        } else {
                          FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodStartDate': Timestamp.fromDate(day), 'lastPeriodEndDate': FieldValue.delete()});
                        }
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      title: isEndDay ? "Убрать конец" : "Конец периода",
                      icon: Icons.check_circle_outline,
                      isActive: isEndDay,
                      theme: theme,
                      onTap: () {
                        if (isEndDay) {
                          FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodEndDate': FieldValue.delete()});
                        } else {
                          FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodEndDate': Timestamp.fromDate(day)});
                        }
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.0,
              children: [
                _buildSquareAction("Симптомы", Icons.tune, Colors.orange, theme, () { Navigator.pop(ctx); onSymptomsTap(); }),
                _buildSquareAction("Настроение", Icons.emoji_emotions, Colors.purple, theme, () { Navigator.pop(ctx); onMoodTap(); }),
                _buildSquareAction("Медикаменты", Icons.medication_outlined, Colors.teal, theme, () { Navigator.pop(ctx); onMedsTap(); }),
                _buildSquareAction("Вес", Icons.monitor_weight_outlined, Colors.blueGrey, theme, () { Navigator.pop(ctx); onWeightTap(); }),
                _buildSquareAction("Секс", Icons.favorite_outline, Colors.pinkAccent, theme, () { Navigator.pop(ctx); onSexTap(); }),
                _buildSquareAction("БТТ", Icons.thermostat_outlined, Colors.redAccent, theme, () { Navigator.pop(ctx); onTempTap(); }),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  static void showTemperatureSheet({
    required BuildContext context,
    required double? currentTemp,
    required Function(double) onSave,
  }) {
    int wholeNumber = currentTemp != null ? currentTemp.truncate() : 36;
    int decimalNumber = currentTemp != null ? ((currentTemp - wholeNumber) * 10).round() : 6;
    final theme = Theme.of(context);

    final Widget selectionOverlay = Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 1.5), bottom: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
      ),
    );

    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Базальная температура", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 160,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: wholeNumber - 35),
                            itemExtent: 48, selectionOverlay: selectionOverlay,
                            onSelectedItemChanged: (idx) => setModalState(() => wholeNumber = 35 + idx),
                            children: List.generate(8, (index) => Center(child: Text("${35 + index}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)))),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text(",", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                        SizedBox(
                          width: 80,
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: decimalNumber),
                            itemExtent: 48, selectionOverlay: selectionOverlay,
                            onSelectedItemChanged: (idx) => setModalState(() => decimalNumber = idx),
                            children: List.generate(10, (index) => Center(child: Text("$index", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("°C", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () {
                        onSave(wholeNumber + (decimalNumber / 10.0));
                        Navigator.pop(ctx);
                      },
                      child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  static void showWeightSheet({
    required BuildContext context,
    required double? currentWeight,
    required Function(double) onSave,
  }) {
    int wholeNumber = currentWeight != null ? currentWeight.truncate() : 60;
    int decimalNumber = currentWeight != null ? ((currentWeight - wholeNumber) * 10).round() : 0;
    final theme = Theme.of(context);

    final Widget selectionOverlay = Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.primary, width: 1.5), bottom: BorderSide(color: theme.colorScheme.primary, width: 1.5))),
    );

    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Вес", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 160,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: wholeNumber - 30),
                            itemExtent: 48, selectionOverlay: selectionOverlay,
                            onSelectedItemChanged: (idx) => setModalState(() => wholeNumber = 30 + idx),
                            children: List.generate(171, (index) => Center(child: Text("${30 + index}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)))),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: Text(",", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                        SizedBox(
                          width: 80,
                          child: CupertinoPicker(
                            scrollController: FixedExtentScrollController(initialItem: decimalNumber),
                            itemExtent: 48, selectionOverlay: selectionOverlay,
                            onSelectedItemChanged: (idx) => setModalState(() => decimalNumber = idx),
                            children: List.generate(10, (index) => Center(child: Text("$index", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("кг", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () {
                        onSave(wholeNumber + (decimalNumber / 10.0));
                        Navigator.pop(ctx);
                      },
                      child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  )
                ],
              ),
            );
          }
        );
      }
    );
  }

  static void showSexSheet({
    required BuildContext context,
    required List<String> currentData,
    required int currentOrgasmCount,
    required Function(List<String>, int) onSave,
  }) {
    List<String> tempData = List.from(currentData);
    int tempOrgasmCount = currentOrgasmCount == 0 && tempData.contains('Оргазм') ? 1 : currentOrgasmCount;
    final theme = Theme.of(context);
    
    final List<String> protectionOptions = ['Защищенный', 'Незащищенный'];
    final List<String> extraOptions = ['Оргазм', 'Мастурбация'];

    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Секс и интимность", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 24),
                  
                  Text("Тип контакта", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 12,
                    children: protectionOptions.map((option) {
                      final bool isSelected = tempData.contains(option);
                      return ChoiceChip(
                        label: Text(option, style: TextStyle(color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                        selected: isSelected, selectedColor: theme.colorScheme.primary, backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                        side: const BorderSide(color: Colors.transparent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              tempData.removeWhere((item) => protectionOptions.contains(item));
                              tempData.add(option);
                            } else {
                              tempData.remove(option);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  Text("Дополнительно", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8, runSpacing: 12,
                    children: extraOptions.map((option) {
                      final bool isSelected = tempData.contains(option);
                      return ChoiceChip(
                        label: Text(option, style: TextStyle(color: isSelected ? Colors.white : theme.colorScheme.onSurface, fontWeight: FontWeight.w600)),
                        selected: isSelected, selectedColor: Colors.pinkAccent, backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                        side: const BorderSide(color: Colors.transparent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              tempData.add(option);
                              if (option == 'Оргазм' && tempOrgasmCount == 0) tempOrgasmCount = 1;
                            } else {
                              tempData.remove(option);
                              if (option == 'Оргазм') tempOrgasmCount = 0;
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),

                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: tempData.contains('Оргазм') 
                      ? Column(
                          children: [
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Количество оргазмов", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.bold)),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: tempOrgasmCount > 1 ? () => setModalState(() => tempOrgasmCount--) : null,
                                      icon: Icon(Icons.remove_circle_outline, color: tempOrgasmCount > 1 ? theme.colorScheme.primary : Colors.grey.withValues(alpha: 0.3), size: 28),
                                    ),
                                    Text('$tempOrgasmCount', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                                    IconButton(
                                      onPressed: () => setModalState(() => tempOrgasmCount++),
                                      icon: Icon(Icons.add_circle_outline, color: theme.colorScheme.primary, size: 28),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () {
                        onSave(tempData, tempOrgasmCount);
                        Navigator.pop(ctx);
                      },
                      child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  static void showSingleSelectionSheet({required BuildContext context, required String title, required String subtitle, required List<String> options, required String currentValue, required Function(String) onSave}) {
    String tempValue = currentValue;
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      isScrollControlled: true, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8), 
                  Text(subtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8, runSpacing: 12,
                    children: options.map((option) {
                      final bool isSelected = tempValue == option;
                      return ChoiceChip(
                        label: Text(option, style: TextStyle(color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, fontWeight: FontWeight.w600)), 
                        selected: isSelected, 
                        selectedColor: theme.colorScheme.primary, 
                        backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), 
                        side: const BorderSide(color: Colors.transparent), 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), 
                        onSelected: (selected) { setModalState(() => tempValue = selected ? option : ''); }
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 50, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0), 
                      onPressed: () { onSave(tempValue); Navigator.pop(ctx); }, 
                      child: Text("СОХРАНИТЬ", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15))
                    )
                  )
                ],
              ),
            );
          }
        );
      },
    );
  }

  static void showCycleSettingDialog({required BuildContext context, required String title, required String hintText, required int currentValue, required int minVal, required int maxVal, required String updateField}) {
    final theme = Theme.of(context);
    final TextEditingController controller = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), 
        backgroundColor: theme.colorScheme.surface,
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: theme.colorScheme.onSurface)),
        content: TextField(
          controller: controller, 
          keyboardType: TextInputType.number, 
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold), 
          decoration: InputDecoration(
            hintText: hintText, 
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)), 
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary))
          ), 
          cursorColor: theme.colorScheme.primary
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Отмена", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), 
            onPressed: () { 
              final int? newLen = int.tryParse(controller.text); 
              if (newLen != null && newLen >= minVal && newLen <= maxVal) { 
                final uid = FirebaseAuth.instance.currentUser?.uid; 
                if (uid != null) { 
                  FirebaseFirestore.instance.collection('users').doc(uid).update({updateField: newLen}); 
                } 
              } 
              Navigator.pop(ctx); 
            }, 
            child: Text("Сохранить", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  static void showInfoSheet({required BuildContext context, required String title, required String description}) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 16), 
              Text(description, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15, height: 1.4)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 50, 
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0), 
                  onPressed: () => Navigator.pop(ctx), 
                  child: Text("Понятно 🌸", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, letterSpacing: 1.0))
                )
              )
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildActionButton({required String title, required IconData icon, required bool isActive, required ThemeData theme, required VoidCallback onTap}) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), 
        foregroundColor: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, 
        elevation: 0, 
        padding: const EdgeInsets.symmetric(vertical: 12), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
      ),
      icon: Icon(icon, size: 18), 
      label: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), 
      onPressed: onTap,
    );
  }

  static Widget _buildSquareAction(String title, IconData icon, Color color, ThemeData theme, VoidCallback onTap) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28), const SizedBox(height: 8),
            Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  static bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}