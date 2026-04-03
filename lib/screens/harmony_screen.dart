import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';
import 'ai_chat_screen.dart'; 

class HarmonyScreen extends StatefulWidget {
  const HarmonyScreen({super.key});

  @override
  State<HarmonyScreen> createState() => _HarmonyScreenState();
}

class _HarmonyScreenState extends State<HarmonyScreen> {
  static const Color _accentColor = Color(0xFFB76E79); 
  static const Color _bgColor = Color(0xFFF9F9F9);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  
  List<String> _currentDaySymptoms = [];
  String _currentMood = '';
  String _currentSleep = '';
  bool _isAnalyzing = false;

  final List<String> _availableSymptoms = [
    'Тянет живот', 'Грусть', 'Энергичность', 'Высыпания', 
    'Раздражительность', 'Головная боль', 'Чувствительность груди', 
    'Спокойствие', 'Тяга к сладкому', 'Вздутие'
  ];
  
  final List<String> _availableMoods = [
    'Отличное ✨', 'Спокойное 🌿', 'Грусть 🌧️', 
    'Тревога 🌪️', 'Раздражение ⚡', 'Апатия 🌫️'
  ];

  final List<String> _availableSleep = [
    'Отлично (8+ ч)', 'Нормально (6-8 ч)', 
    'Мало (<6 ч)', 'Бессонница'
  ];

  final Map<DateTime, Map<String, dynamic>> _cachedDays = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadSymptomsForDay(_selectedDay!);
  }

  Future<void> _loadSymptomsForDay(DateTime date) async {
    final dateKey = DateTime(date.year, date.month, date.day);
    
    if (_cachedDays.containsKey(dateKey)) {
      final data = _cachedDays[dateKey]!;
      setState(() { 
        _currentDaySymptoms = List<String>.from(data['symptoms'] ?? []); 
        _currentMood = data['mood'] ?? '';
        _currentSleep = data['sleep'] ?? '';
      });
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final String docId = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).get();
    
    if (doc.exists && mounted) {
      final data = doc.data()!;
      _cachedDays[dateKey] = data; 
      setState(() { 
        _currentDaySymptoms = List<String>.from(data['symptoms'] ?? []); 
        _currentMood = data['mood'] ?? '';
        _currentSleep = data['sleep'] ?? '';
      });
    } else if (mounted) {
      _cachedDays[dateKey] = {}; 
      setState(() { 
        _currentDaySymptoms = []; 
        _currentMood = '';
        _currentSleep = '';
      });
    }
  }

  Map<String, String> _getPregnancyTip(int week) {
    if (week < 4) return {'title': 'Подготовка организма', 'desc': 'Ваше тело только готовится к чудесным изменениям.'};
    if (week >= 4 && week < 8) return {'title': 'Размер макового зернышка', 'desc': 'Начинает биться крошечное сердечко. Заложите основу здорового питания.'};
    if (week >= 8 && week < 12) return {'title': 'Размер клубнички 🍓', 'desc': 'Формируются ручки и ножки. Не забывайте про витамины!'};
    if (week >= 12 && week < 16) return {'title': 'Размер лимона 🍋', 'desc': 'Малыш учится глотать и двигаться. Риск токсикоза обычно снижается.'};
    if (week >= 16 && week < 20) return {'title': 'Размер авокадо 🥑', 'desc': 'Скоро вы сможете почувствовать первые шевеления!'};
    if (week >= 20 && week < 24) return {'title': 'Размер банана 🍌', 'desc': 'Малыш уже слышит ваш голос. Начинайте разговаривать с ним.'};
    if (week >= 24 && week < 28) return {'title': 'Размер кукурузы 🌽', 'desc': 'Открываются глазки. Следите за уровнем железа и отдыхайте.'};
    if (week >= 28 && week < 32) return {'title': 'Размер кокоса 🥥', 'desc': 'Начинается третий триместр! Малыш активно набирает вес.'};
    if (week >= 32 && week < 36) return {'title': 'Размер дыни 🍈', 'desc': 'Легкие почти сформированы, малыш тренируется дышать.'};
    if (week >= 36 && week <= 40) return {'title': 'Размер арбуза 🍉', 'desc': 'Организм готовится к родам. Собирайте сумку в роддом и больше отдыхайте!'};
    return {'title': 'Малыш готов!', 'desc': 'Готов появиться на свет со дня на день! ❤️'};
  }

  Map<String, String> _getDayInfo(DateTime day, DateTime? lastStart, int cycleLength, int periodDuration, bool isPregnant, DateTime? pregStart) {
    if (isPregnant && pregStart != null) {
      final int days = day.difference(pregStart).inDays;
      if (days < 0) return {'title': 'До беременности', 'desc': 'Этот день был до начала отсчета беременности.'};
      
      final int weeks = days ~/ 7;
      if (weeks > 42) return {'title': 'Малыш уже с вами! 🎉', 'desc': 'Период беременности завершен.'};

      final DateTime dueDate = pregStart.add(const Duration(days: 280));
      final tip = _getPregnancyTip(weeks);

      return {
        'title': '$weeks неделя 🤰',
        'desc': '${tip['title']}\n\n${tip['desc']}\n\nПДР: ${DateFormat('dd.MM.yyyy').format(dueDate)}'
      };
    }

    if (!isPregnant && lastStart != null) {
      final start = DateTime(lastStart.year, lastStart.month, lastStart.day);
      final current = DateTime(day.year, day.month, day.day);
      final int diff = current.difference(start).inDays;

      if (diff < 0) return {'title': 'Обычный день', 'desc': 'Данных о цикле на этот день еще нет.'};

      final int normalizedDay = diff % cycleLength;
      
      bool isActualMenstruation = normalizedDay >= 0 && normalizedDay < periodDuration;
      bool isOvulation = normalizedDay == (cycleLength - 14) || normalizedDay == (cycleLength - 15);
      bool isFertile = normalizedDay >= (cycleLength - 19) && normalizedDay <= (cycleLength - 13) && !isOvulation;
      bool isPMS = normalizedDay >= (cycleLength - 7);

      if (isActualMenstruation) {
        return {'title': 'Менструация 🩸', 'desc': 'Отмечена красным цветом. В эти дни телу нужен отдых и забота. Избегайте тяжелых тренировок.'};
      } else if (isOvulation) {
        return {'title': 'Овуляция ✨', 'desc': 'Оранжевый кружок. День максимальной фертильности и пика вашей энергии!'};
      } else if (isFertile) {
        return {'title': 'Окно фертильности 🌸', 'desc': 'Светло-бирюзовый цвет. Дни с высокой вероятностью зачатия.'};
      } else if (isPMS) {
        return {'title': 'ПМС (Лютеиновая фаза) 🌙', 'desc': 'Светло-фиолетовый цвет. Организм готовится к новому циклу. Возможна тяга к сладкому, перепады настроения и задержка жидкости.'};
      } else {
        return {'title': 'Фолликулярная фаза 🌿', 'desc': 'Белый фон. Период роста эстрогена. Отличное время для активного фитнеса и новых начинаний.'};
      }
    }
    return {'title': 'Нет данных', 'desc': 'Отметьте начало цикла, чтобы календарь начал показывать прогнозы.'};
  }

  void _showDayTooltip(DateTime day, Map<String, dynamic> userData) {
    final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
    final bool isPregnant = userData['isPregnant'] ?? false;
    final Timestamp? pregStartTs = userData['pregnancyStartDate'] as Timestamp?;

    final info = _getDayInfo(day, lastStartTs?.toDate(), cycleLength, periodDuration, isPregnant, pregStartTs?.toDate());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info['title']!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _textColor)),
            const SizedBox(height: 12),
            Text(info['desc']!, style: const TextStyle(fontSize: 15, color: _subTextColor, height: 1.5, fontWeight: FontWeight.w500)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ПОНЯТНО', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // === НОВАЯ ШТОРКА ДЛЯ ВОСКРЕСЕНЬЯ (ДЕНЬ ДЛЯ ДУШИ) ===
  void _showCheatMealSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Воскресенье — день для души ✨",
                style: TextStyle(
                  color: Color(0xFF2D2D2D),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                "В этот день мы не строги к себе. Ты можешь позволить себе любимые блюда без угрызений совести и жесткого контроля. Еда — это не только топливо, но и радость.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB76E79),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Понятно 🌸",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // === НОВАЯ ШТОРКА ДЛЯ ПМС (26-Й ДЕНЬ ЦИКЛА) ===
  void _showPMSCheatDaySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Прислушайся к себе ✨",
                style: TextStyle(
                  color: Color(0xFF2D2D2D),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                "Сейчас 26-й день твоего цикла. В этот период ПМС твоему телу физиологически нужно чуть больше энергии и углеводов. Это нормально! Позволь себе любимую еду без чувства вины — организму нужна поддержка, а не строгие рамки.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB76E79),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "Понятно 🌸",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

    void _showSymptomsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Симптомы", style: TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text("Отметь, что чувствуешь сегодня", style: TextStyle(color: _subTextColor, fontSize: 14)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: _availableSymptoms.map((symptom) {
                      final bool isSelected = _currentDaySymptoms.contains(symptom);
                      return ChoiceChip(
                        label: Text(symptom, style: TextStyle(color: isSelected ? Colors.white : _textColor, fontWeight: FontWeight.w600)),
                        selected: isSelected,
                        selectedColor: _accentColor,
                        backgroundColor: const Color(0xFFF2F2F7),
                        side: const BorderSide(color: Colors.transparent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) _currentDaySymptoms.add(symptom);
                            else _currentDaySymptoms.remove(symptom);
                          });
                          setState(() {}); 
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () { DatabaseService().saveDailySymptoms(_selectedDay!, _currentDaySymptoms); Navigator.pop(ctx); },
                      child: const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
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

  void _showSingleSelectionBottomSheet({
    required String title,
    required String subtitle,
    required List<String> options,
    required String currentValue,
    required Function(String) onSave,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: const TextStyle(color: _subTextColor, fontSize: 14)),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: options.map((option) {
                      final bool isSelected = currentValue == option;
                      return ChoiceChip(
                        label: Text(option, style: TextStyle(color: isSelected ? Colors.white : _textColor, fontWeight: FontWeight.w600)),
                        selected: isSelected,
                        selectedColor: _accentColor,
                        backgroundColor: const Color(0xFFF2F2F7),
                        side: const BorderSide(color: Colors.transparent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onSelected: (selected) {
                          setModalState(() => currentValue = selected ? option : '');
                          setState(() {}); 
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                      onPressed: () { onSave(currentValue); Navigator.pop(ctx); },
                      child: const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
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

  void _showMoodBottomSheet() {
    _showSingleSelectionBottomSheet(
      title: "Настроение",
      subtitle: "Как ты себя чувствуешь сегодня?",
      options: _availableMoods,
      currentValue: _currentMood,
      onSave: (val) {
        _currentMood = val;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final String docId = "${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}";
          FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'mood': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      }
    );
  }

  void _showSleepBottomSheet() {
    _showSingleSelectionBottomSheet(
      title: "Сон",
      subtitle: "Как ты спала сегодня ночью?",
      options: _availableSleep,
      currentValue: _currentSleep,
      onSave: (val) {
        _currentSleep = val;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final String docId = "${_selectedDay!.year}-${_selectedDay!.month.toString().padLeft(2, '0')}-${_selectedDay!.day.toString().padLeft(2, '0')}";
          FirebaseFirestore.instance.collection('users').doc(uid).collection('cycle_logs').doc(docId).set({'sleep': val, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
      }
    );
  }

  void _showCycleLengthDialog(int currentLength) {
    final TextEditingController controller = TextEditingController(text: currentLength.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: const Text("Длина цикла", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: _textColor)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: "Например: 28", 
            hintStyle: TextStyle(color: Colors.grey),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
          ),
          cursorColor: _accentColor,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () {
              final int? newLen = int.tryParse(controller.text);
              if (newLen != null && newLen > 15 && newLen < 60) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) FirebaseFirestore.instance.collection('users').doc(uid).update({'cycleLength': newLen});
              }
              Navigator.pop(ctx);
            },
            child: const Text("Сохранить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _analyzeWithEva() async {
    if (_isAnalyzing) return;
    setState(() => _isAnalyzing = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final symptomsText = _currentDaySymptoms.isEmpty ? 'Нет' : _currentDaySymptoms.join(', ');
    final moodText = _currentMood.isEmpty ? 'Не указано' : _currentMood;
    final sleepText = _currentSleep.isEmpty ? 'Не указано' : _currentSleep;

    final prompt = "Ева, проанализируй мое состояние на сегодня:\nНастроение - [$moodText]\nСон - [$sleepText]\nСимптомы - [$symptomsText]\nДай рекомендации.";

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Отправляем данные Еве... ✨", style: TextStyle(fontWeight: FontWeight.bold)), duration: Duration(seconds: 2), backgroundColor: _accentColor)
    );

    await FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats_dietitian').add({
      'text': prompt,
      'role': 'user',
      'timestamp': FieldValue.serverTimestamp(),
      'isActionCompleted': false,
    });

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
    }

    try {
      final history = await DatabaseService().getChatHistoryForAI('dietitian');
      final userContext = await DatabaseService().getAIContextSummary();
      final callable = FirebaseFunctions.instance.httpsCallable('askDietitian');
      
      final result = await callable.call({
        'prompt': prompt,
        'history': history,
        'userContext': userContext,
      });

      final aiResponse = result.data['text'] as String;
      await DatabaseService().saveBotChatMessage('dietitian', aiResponse, 'ai');
    } catch (e) {
      debugPrint("Ошибка фонового вызова Евы: $e");
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Map<String, String> _getPhaseTip(int dayOfCycle) {
    if (dayOfCycle >= 1 && dayOfCycle <= 5) return {'icon': '🩸', 'text': 'Твоему телу сейчас нужен отдых и забота. Завари теплый травяной чай, надень уютные носочки и позволь себе кусочек темного шоколада. Никаких тяжелых тренировок сегодня!'};
    else if (dayOfCycle >= 6 && dayOfCycle <= 13) return {'icon': '🌸', 'text': 'Уровень эстрогена растет, а вместе с ним — твоя энергия! Отличное время для новых начинаний, активного фитнеса и сложных рабочих задач.'};
    else if (dayOfCycle == 14 || dayOfCycle == 15) return {'icon': '✨', 'text': 'Ты сейчас на пике своей привлекательности и уверенности. Сияй! Идеальный день для свидания, фотосессии или важной презентации.'};
    else return {'icon': '🌙', 'text': 'Организм готовится к отдыху. Могут появиться отеки или тяга к сладкому — это абсолютно нормально! Добавь в рацион больше сложных углеводов и не ругай себя.'};
  }

  Future<void> _selectDateAndSave(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: _accentColor, onPrimary: Colors.white, onSurface: _textColor)), child: child!),
    );
    if (picked != null) await DatabaseService().savePeriodData(start: picked, cycleLength: 28, periodDuration: 5);
  }

  Future<void> _endPeriod() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await FirebaseFirestore.instance.collection('users').doc(uid).update({'lastPeriodEndDate': FieldValue.serverTimestamp()});
  }

  // === ОБНОВЛЕНО: Расчет читмилов строго по Воскресеньям ===
  String _getCheatStatus(DateTime day, Map<String, dynamic> userData) {
    if (userData['isPregnant'] == true || userData['goal'] == 'Здоровая беременность') return 'none';

    final lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

    bool isCheatDay = false;
    // Новая логика: Читмил всегда в воскресенье
    bool isCheatMeal = day.weekday == DateTime.sunday;

    if (lastStartTs != null) {
      final start = DateTime(lastStartTs.toDate().year, lastStartTs.toDate().month, lastStartTs.toDate().day);
      final current = DateTime(day.year, day.month, day.day);
      final int diff = current.difference(start).inDays;
      if (diff >= 0) {
        final int dayOfCycle = (diff % cycleLength) + 1;
        if (dayOfCycle == 26) isCheatDay = true;
      }
    }

    if (isCheatDay) return 'cheat_day';
    if (isCheatMeal) return 'cheat_meal';
    return 'none';
  }

  // === ОБНОВЛЕНО: Метод отрисовки дней календаря с иконкой 🧁 ===
  Widget _buildCalendarDay(DateTime day, DateTime? lastStart, int cycleLength, int periodDuration, bool isPregnant, Timestamp? pregStartTs, Map<String, dynamic> userData, {bool isToday = false, bool isOutside = false, bool isSelected = false}) {
    Color bgColor = Colors.transparent;
    Color txtColor = isOutside ? Colors.grey.withValues(alpha: 0.4) : _textColor;
    BoxBorder? border;

    if (isPregnant && pregStartTs != null) {
      final pregStart = pregStartTs.toDate();
      final dueDate = pregStart.add(const Duration(days: 280));
      
      final isDueDate = day.year == dueDate.year && day.month == dueDate.month && day.day == dueDate.day;
      final int daysDiff = day.difference(pregStart).inDays;

      if (isDueDate) {
        bgColor = Colors.deepPurpleAccent;
        txtColor = Colors.white;
      } else if (daysDiff >= 0 && daysDiff <= 294) {
        final int weeks = daysDiff ~/ 7;

        if (weeks < 4) {
          bgColor = Colors.grey.shade100;
        } else if (weeks >= 4 && weeks < 8) {
          bgColor = const Color(0xFFFCE4EC); 
        } else if (weeks >= 8 && weeks < 12) {
          bgColor = const Color(0xFFFFEBEE); 
        } else if (weeks >= 12 && weeks < 16) {
          bgColor = const Color(0xFFFFF9C4); 
        } else if (weeks >= 16 && weeks < 20) {
          bgColor = const Color(0xFFE8F5E9); 
        } else if (weeks >= 20 && weeks < 24) {
          bgColor = const Color(0xFFFFF3E0); 
        } else if (weeks >= 24 && weeks < 28) {
          bgColor = const Color(0xFFFFF8E1); 
        } else if (weeks >= 28 && weeks < 32) {
          bgColor = const Color(0xFFEFEBE9); 
        } else if (weeks >= 32 && weeks < 36) {
          bgColor = const Color(0xFFF1F8E9); 
        } else if (weeks >= 36 && weeks <= 42) {
          bgColor = const Color(0xFFFFEBE8); 
        }

        txtColor = Colors.black87; 
      }

    } else if (!isPregnant && lastStart != null) {
      final start = DateTime(lastStart.year, lastStart.month, lastStart.day);
      final current = DateTime(day.year, day.month, day.day);
      final int diff = current.difference(start).inDays;
      final int normalizedDay = diff >= 0 ? diff % cycleLength : (cycleLength + (diff % cycleLength)) % cycleLength;

      bool isActualMenstruation = diff >= 0 && diff < periodDuration;
      bool isMenstruationPrediction = normalizedDay >= 0 && normalizedDay < periodDuration && diff >= periodDuration;
      bool isOvulation = normalizedDay == (cycleLength - 14) || normalizedDay == (cycleLength - 15);
      
      bool isFertile = normalizedDay >= (cycleLength - 19) && normalizedDay <= (cycleLength - 13) && !isOvulation;
      bool isPMS = normalizedDay >= (cycleLength - 7) && normalizedDay < cycleLength;

      if (isActualMenstruation) { 
        bgColor = _accentColor; 
        txtColor = Colors.white; 
      } else if (isMenstruationPrediction) { 
        bgColor = const Color(0xFFFDECE8); 
        txtColor = _accentColor; 
      } else if (isOvulation) { 
        bgColor = const Color(0xFFFFDAB9).withValues(alpha: 0.5); 
        txtColor = Colors.deepOrange; 
        border = Border.all(color: Colors.deepOrange.withValues(alpha: 0.4), width: 1.5); 
      } else if (isFertile) {
        bgColor = const Color(0xFFE0F7FA).withValues(alpha: 0.6); 
        txtColor = Colors.teal;
      } else if (isPMS) {
        bgColor = const Color(0xFFF3E5F5).withValues(alpha: 0.5); 
        txtColor = Colors.deepPurple;
      }
    }

    if (isSelected) {
      border = Border.all(color: _textColor, width: 2);
    } else if (isToday && !isPregnant) { 
      border = Border.all(color: _accentColor.withValues(alpha: 0.5), width: 2);
    } else if (isToday && isPregnant && bgColor != Colors.deepPurpleAccent) { 
      border = Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.6), width: 2);
      txtColor = Colors.deepPurpleAccent;
    }

    final String cheatStatus = _getCheatStatus(day, userData);
    Widget contentWidget;
    
    if (cheatStatus == 'cheat_day' && !isOutside) {
      contentWidget = const Text('🎂', style: TextStyle(fontSize: 16));
    } else if (cheatStatus == 'cheat_meal' && !isOutside) {
      // Иконка для воскресенья
      contentWidget = const Text('🧁', style: TextStyle(fontSize: 16));
    } else {
      contentWidget = Text(day.day.toString(), style: TextStyle(color: txtColor, fontWeight: FontWeight.bold, fontSize: 15));
    }

    return Container(
      margin: const EdgeInsets.all(6.0),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle, border: border),
      child: contentWidget,
    );
  }

  Widget _buildSymptomCard(String title, IconData icon, Color color, VoidCallback onTap, {bool isActive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4), 
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.1) : Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          border: Border.all(color: isActive ? color : Colors.transparent, width: 1.5), 
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4))]
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              title, 
              textAlign: TextAlign.center, 
              style: TextStyle(color: _textColor, fontSize: 12, fontWeight: isActive ? FontWeight.w800 : FontWeight.w600, height: 1.2)
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: _bgColor);

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Гармония', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
            const SizedBox(width: 8),
            Icon(Icons.spa, color: _accentColor, size: 28), 
          ],
        ),
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        centerTitle: false
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: _accentColor));
          
          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final Timestamp? lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
          final Timestamp? lastPeriodEndTs = userData['lastPeriodEndDate'] as Timestamp?;
          final Timestamp? pregStartTs = userData['pregnancyStartDate'] as Timestamp?;
          final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
          final int periodDuration = (userData['periodDuration'] as num?)?.toInt() ?? 5;
          final bool isPregnant = userData['isPregnant'] ?? false;

          DateTime? lastStart = lastStartTs?.toDate();
          String dayText = "Нет данных", phaseText = "Отметьте первый день цикла";
          int currentDayOfCycle = 0;
          bool hasEnded = false;
          
          if (isPregnant) {
            if (pregStartTs != null) {
              final int weeks = DateTime.now().difference(pregStartTs.toDate()).inDays ~/ 7;
              if (weeks > 42) {
                dayText = "Уже родили 🎉";
                phaseText = "Режим беременности можно выключить";
              } else if (weeks < 0) {
                dayText = "Подготовка";
                phaseText = "Беременность еще не наступила";
              } else {
                dayText = "$weeks неделя";
                phaseText = "Беременность 🤰";
              }
            }
          } else if (lastStart != null) {
            final start = DateTime(lastStart.year, lastStart.month, lastStart.day);
            final diff = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).difference(start).inDays;
            if (lastPeriodEndTs != null && lastPeriodEndTs.toDate().isAfter(lastStart)) hasEnded = true;

            if (diff >= 0) {
              currentDayOfCycle = (diff % cycleLength) + 1;
              dayText = "$currentDayOfCycle-й день";
              if (currentDayOfCycle <= periodDuration && !hasEnded) phaseText = 'Менструация 🩸';
              else if (currentDayOfCycle <= cycleLength - 15) phaseText = 'Фолликулярная фаза 🌸';
              else if (currentDayOfCycle <= cycleLength - 12) phaseText = 'Окно фертильности ✨';
              else phaseText = 'Лютеиновая фаза 🌿';
            }
          }

          bool showEndButton = currentDayOfCycle > 0 && currentDayOfCycle <= periodDuration && !hasEnded && !isPregnant;

          return SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))]),
                  child: SwitchListTile(
                    activeColor: _accentColor,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    title: const Text("Я беременна 🤰", style: TextStyle(color: _textColor, fontSize: 15, fontWeight: FontWeight.w800)),
                    value: isPregnant,
                    onChanged: (val) async {
                      if (val) {
                        final picked = await showDatePicker(
                          context: context, 
                          initialDate: DateTime.now(), 
                          firstDate: DateTime.now().subtract(const Duration(days: 300)), 
                          lastDate: DateTime.now(),
                          builder: (context, child) => Theme(data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: _accentColor, onPrimary: Colors.white, onSurface: _textColor)), child: child!),
                        );
                        if (picked != null) {
                          FirebaseFirestore.instance.collection('users').doc(uid).update({'isPregnant': true, 'pregnancyStartDate': Timestamp.fromDate(picked)});
                        }
                      } else {
                        FirebaseFirestore.instance.collection('users').doc(uid).update({'isPregnant': false});
                      }
                    }
                  ),
                ),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(20), width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))]),
                  child: Column(
                    children: [
                      Text(dayText, style: const TextStyle(color: _textColor, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                      const SizedBox(height: 6),
                      Text(phaseText, style: const TextStyle(color: _subTextColor, fontSize: 15, fontWeight: FontWeight.w600)),
                      
                      if (!isPregnant) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _showCycleLengthDialog(cycleLength),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.edit_calendar, color: _accentColor, size: 14),
                              const SizedBox(width: 6),
                              Text("Длина цикла: $cycleLength дн. ✎", style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      if (!isPregnant)
                        SizedBox(
                          width: double.infinity, height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: showEndButton ? const Color(0xFF2D2D2D) : _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)), elevation: 0),
                            onPressed: () { if (showEndButton) _endPeriod(); else _selectDateAndSave(context, true); },
                            child: Text(showEndButton ? "ОТМЕТИТЬ ОКОНЧАНИЕ" : "ОТМЕТИТЬ НАЧАЛО", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.0)),
                          ),
                        )
                    ],
                  ),
                ),

                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))]),
                  child: TableCalendar(
                    locale: 'ru_RU', firstDay: DateTime.utc(2020, 10, 16), lastDay: DateTime.utc(2030, 3, 14),
                    focusedDay: _focusedDay,
                    availableGestures: AvailableGestures.horizontalSwipe, 
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    // === ОБНОВЛЕНО: Действие при клике на день ===
                    onDaySelected: (selectedDay, focusedDay) { 
                      setState(() { _selectedDay = selectedDay; _focusedDay = focusedDay; }); 
                      _loadSymptomsForDay(selectedDay); 
                      _showDayTooltip(selectedDay, userData);
                      
                      if (!isPregnant) {
                        final String cheatStatus = _getCheatStatus(selectedDay, userData);
                        if (cheatStatus == 'cheat_day') {
                          // Показываем шторку ПМС для 26-го дня
                          _showPMSCheatDaySheet();
                        } else if (cheatStatus == 'cheat_meal') {
                          // Показываем шторку читмила по воскресеньям
                          _showCheatMealSheet();
                        }
                      }
                    },
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _textColor)),
                    daysOfWeekStyle: const DaysOfWeekStyle(weekdayStyle: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold), weekendStyle: TextStyle(color: _accentColor, fontWeight: FontWeight.bold)),
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (c, d, f) => _buildCalendarDay(d, lastStart, cycleLength, periodDuration, isPregnant, pregStartTs, userData),
                      todayBuilder: (c, d, f) => _buildCalendarDay(d, lastStart, cycleLength, periodDuration, isPregnant, pregStartTs, userData, isToday: true),
                      outsideBuilder: (c, d, f) => _buildCalendarDay(d, lastStart, cycleLength, periodDuration, isPregnant, pregStartTs, userData, isOutside: true),
                      selectedBuilder: (c, d, f) => _buildCalendarDay(d, lastStart, cycleLength, periodDuration, isPregnant, pregStartTs, userData, isSelected: true),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildSymptomCard("Симптомы", Icons.healing_outlined, _accentColor, _showSymptomsBottomSheet, isActive: _currentDaySymptoms.isNotEmpty)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSymptomCard("Настроение", Icons.sentiment_satisfied_alt, Colors.orange, _showMoodBottomSheet, isActive: _currentMood.isNotEmpty)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSymptomCard("Сон", Icons.bedtime_outlined, Colors.deepPurpleAccent, _showSleepBottomSheet, isActive: _currentSleep.isNotEmpty)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                
                if (!isPregnant && currentDayOfCycle > 0) ...[
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.7), shape: BoxShape.circle),
                          child: Text(_getPhaseTip(currentDayOfCycle)['icon']!, style: const TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_getPhaseTip(currentDayOfCycle)['text']!, style: const TextStyle(color: _textColor, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ],

                GestureDetector(
                  onTap: _analyzeWithEva, 
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))]),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle), child: _isAnalyzing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.auto_awesome, color: Colors.white, size: 24)),
                        const SizedBox(width: 16),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Анализ Евы', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)), SizedBox(height: 2), Text('Обсудить симптомы с ИИ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))])),
                        const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
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