import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SmartQuestionnaireScreen extends StatefulWidget {
  const SmartQuestionnaireScreen({super.key});

  @override
  State<SmartQuestionnaireScreen> createState() => _SmartQuestionnaireScreenState();
}

class _SmartQuestionnaireScreenState extends State<SmartQuestionnaireScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isLoading = true; // Начинаем с загрузки

  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);

  final Map<String, dynamic> _answers = {};
  final Map<String, TextEditingController> _customTextControllers = {};

  final List<Map<String, dynamic>> _questions = [
    // БЛОК 1
    {'id': 'Тип питания', 'q': 'Твой тип питания?', 'type': 'single', 'opts': ['Всеядная', 'Вегетарианка', 'Веган', 'Пескетарианка', 'Свой вариант']},
    {'id': 'Аллергии', 'q': 'Есть ли пищевая аллергия или непереносимость?', 'type': 'multi', 'opts': ['Нет', 'Лактоза', 'Глютен', 'Орехи', 'Морепродукты', 'Свой вариант']},
    {'id': 'Режим питания', 'q': 'Сколько раз в день тебе комфортно есть?', 'type': 'single', 'opts': ['2-3 больших приема', '4-5 небольших порций', 'Ем, когда придется', 'Свой вариант']},
    {'id': 'Отношение к готовке', 'q': 'Готовка для тебя — это...?', 'type': 'single', 'opts': ['Обожаю кулинарию', 'Готовлю только простое и быстрое', 'Ненавижу готовить, ем вне дома', 'Свой вариант']},
    {'id': 'Вода', 'q': 'Твое отношение к воде?', 'type': 'single', 'opts': ['Пью свою норму легко', 'Постоянно забываю пить', 'Свой вариант']},
    // БЛОК 2
    {'id': 'Работа', 'q': 'Кем ты работаешь / Как проходит твой день?', 'type': 'single', 'opts': ['Весь день за компьютером', 'Постоянно на ногах', 'Смешанный график', 'Фриланс из дома', 'Свой вариант']},
    {'id': 'График', 'q': 'Твой типичный график?', 'type': 'single', 'opts': ['Стандартный с 9 до 18', 'Плавающий', 'Часто бывают ночные смены', 'Свой вариант']},
    {'id': 'Транспорт', 'q': 'Как ты обычно добираешься по делам?', 'type': 'multi', 'opts': ['Пешком', 'За рулем', 'Общественный транспорт', 'Свой вариант']},
    {'id': 'Биоритмы', 'q': 'Твои биоритмы?', 'type': 'single', 'opts': ['Ранняя пташка ☀️', 'Сова 🌙', 'Свой вариант']},
    {'id': 'Активность', 'q': 'Любимый вид активности?', 'type': 'multi', 'opts': ['Тренажерный зал', 'Йога и пилатес', 'Танцы', 'Бег', 'Просто люблю гулять', 'Не люблю спорт', 'Свой вариант']},
    // БЛОК 3
    {'id': 'Стресс', 'q': 'Твой средний уровень стресса?', 'type': 'single', 'opts': ['Я спокойна как удав', 'Средне, бывают завалы', 'Я живу в состоянии стресса', 'Свой вариант']},
    {'id': 'Реакция на стресс', 'q': 'Как ты чаще всего реагируешь на стресс?', 'type': 'multi', 'opts': ['Пропадает аппетит', 'Заедаю сладким или фастфудом', 'Иду на тренировку', 'Хочу лежать и плакать', 'Свой вариант']},
    {'id': 'Сон', 'q': 'Сколько часов ты обычно спишь?', 'type': 'single', 'opts': ['Меньше 6 часов', '6-8 часов', 'Больше 8 часов', 'Свой вариант']},
    {'id': 'Слабости в еде', 'q': 'Твоя главная «вредная» слабость в еде?', 'type': 'multi', 'opts': ['Шоколад и конфеты', 'Выпечка и булочки', 'Соленья и чипсы', 'Фастфуд', 'Свой вариант']},
    {'id': 'Отдых', 'q': 'Твой идеальный способ перезагрузиться — это...?', 'type': 'multi', 'opts': ['Лежать с книгой/сериалом', 'Встреча с подругами', 'Активный отдых на природе', 'Спа, ванна и уход', 'Сон 💤', 'Секс 🔥', 'Алкоголь 🍷', 'Свой вариант']},
    // БЛОК 4
    {'id': 'Сожители', 'q': 'С кем ты живешь?', 'type': 'single', 'opts': ['Одна', 'С партнером', 'Большая семья', 'Свой вариант']},
    {'id': 'Дети', 'q': 'Есть ли у тебя дети?', 'type': 'single', 'opts': ['Да', 'Нет', 'Планирую', 'Свой вариант']},
    {'id': 'Животные', 'q': 'Домашние животные?', 'type': 'multi', 'opts': ['Собака', 'Кот', 'Другие', 'Нет', 'Свой вариант']},
    {'id': 'Частота алкоголя', 'q': 'Как часто ты употребляешь алкоголь?', 'type': 'single', 'opts': ['Вообще не пью', 'Только по праздникам', '1-2 раза в неделю по выходным', 'Пару раз в неделю после работы', 'Свой вариант']},
    {'id': 'Вид алкоголя', 'q': 'Какой алкоголь предпочитаешь?', 'type': 'multi', 'opts': ['Сухое вино', 'Сладкое вино и шампанское', 'Коктейли', 'Пиво', 'Крепкий алкоголь', 'Свой вариант']},
    {'id': 'Нелюбимая еда', 'q': 'Какие продукты ты терпеть не можешь?', 'type': 'text', 'hint': 'Впиши через запятую или пропусти'},
    {'id': 'Здоровье', 'q': 'Хронические заболевания или травмы (для ИИ)?', 'type': 'text', 'hint': 'Напиши, если есть, например "болят колени"'},
  ];

  @override
  void initState() {
    super.initState();
    for (var q in _questions) {
      _customTextControllers[q['id']] = TextEditingController();
      if (q['type'] == 'multi') _answers[q['id']] = <String>[];
    }
    _loadExistingAnswers(); // <-- ИСПРАВЛЕНО: Подгружаем ответы из базы
  }

  Future<void> _loadExistingAnswers() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data.containsKey('questionnaire')) {
          final Map<String, dynamic> savedAnswers = data['questionnaire'];
          
          for (var q in _questions) {
            final String id = q['id'];
            final String type = q['type'];
            final List<String> opts = List<String>.from(q['opts'] ?? []);

            if (savedAnswers.containsKey(id)) {
              final savedValue = savedAnswers[id];

              if (type == 'text') {
                _customTextControllers[id]?.text = savedValue.toString();
              } else if (type == 'single') {
                String val = savedValue.toString();
                if (opts.contains(val)) {
                  _answers[id] = val;
                } else {
                  // Если ответа нет в стандартных опциях, значит это "Свой вариант"
                  _answers[id] = 'Свой вариант';
                  _customTextControllers[id]?.text = val;
                }
              } else if (type == 'multi') {
                List<String> savedList = List<String>.from(savedValue);
                List<String> actualAnswers = [];
                for (String val in savedList) {
                  if (opts.contains(val)) {
                    actualAnswers.add(val);
                  } else {
                    actualAnswers.add('Свой вариант');
                    _customTextControllers[id]?.text = val;
                  }
                }
                _answers[id] = actualAnswers.toSet().toList(); // Убираем дубликаты "Свой вариант"
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Ошибка загрузки анкеты: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var c in _customTextControllers.values) { c.dispose(); }
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < _questions.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _saveAndExit();
    }
  }

  Future<void> _saveAndExit() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Map<String, dynamic> finalAnswers = {};

    for (var q in _questions) {
      final String id = q['id'];
      final type = q['type'];

      if (type == 'text') {
        final val = _customTextControllers[id]?.text.trim() ?? '';
        if (val.isNotEmpty) finalAnswers[id] = val;
      } else if (type == 'single') {
        String? val = _answers[id];
        if (val == 'Свой вариант') {
          final customVal = _customTextControllers[id]?.text.trim() ?? '';
          if (customVal.isNotEmpty) finalAnswers[id] = customVal;
        } else if (val != null && val.isNotEmpty) {
          finalAnswers[id] = val;
        }
      } else if (type == 'multi') {
        List<String> vals = List<String>.from(_answers[id] ?? []);
        if (vals.contains('Свой вариант')) {
          vals.remove('Свой вариант');
          final customVal = _customTextControllers[id]?.text.trim() ?? '';
          if (customVal.isNotEmpty) vals.add(customVal);
        }
        if (vals.isNotEmpty) finalAnswers[id] = vals;
      }
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'questionnaire': finalAnswers, // <-- ИСПРАВЛЕНО: Используем set с merge: true для надежности
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Анкета сохранена! Ева стала умнее 🧠✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.teal));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Произошла ошибка, попробуйте еще раз', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: Colors.redAccent
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: _textColor)),
        body: const Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        iconTheme: const IconThemeData(color: _textColor),
        title: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            backgroundColor: const Color(0xFFF2F2F7),
            valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
            minHeight: 8,
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), 
        itemCount: _questions.length,
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        itemBuilder: (context, index) {
          final q = _questions[index];
          final type = q['type'];
          final opts = q['opts'] as List<String>? ?? [];

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Вопрос ${index + 1} из ${_questions.length}", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 16),
                Text(q['q'], style: const TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
                const SizedBox(height: 32),

                Expanded(
                  child: SingleChildScrollView(
                    child: type == 'text' 
                      ? _buildTextField(q['id'], q['hint'] ?? 'Ваш ответ')
                      : Wrap(
                          spacing: 12, runSpacing: 12,
                          children: opts.map((opt) => _buildChip(q['id'], opt, type)).toList(),
                        ),
                  ),
                ),

                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                    onPressed: _isLoading ? null : _nextPage,
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(index == _questions.length - 1 ? "СОХРАНИТЬ И ВЫЙТИ" : "ДАЛЕЕ", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1.0)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(String qId, String option, String type) {
    final bool isMulti = type == 'multi';
    final List<String> currentMulti = isMulti ? (_answers[qId] as List<String>? ?? []) : [];
    final bool isSelected = isMulti ? currentMulti.contains(option) : _answers[qId] == option;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceChip(
          label: Text(option, style: TextStyle(color: isSelected ? Colors.white : _textColor, fontWeight: FontWeight.w600, fontSize: 15)),
          selected: isSelected,
          selectedColor: _accentColor,
          backgroundColor: const Color(0xFFF2F2F7),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.transparent)),
          onSelected: (selected) {
            setState(() {
              if (isMulti) {
                if (option == 'Нет' || option == 'Вообще не пью') {
                  currentMulti.clear();
                  if (selected) currentMulti.add(option);
                } else {
                  currentMulti.remove('Нет');
                  currentMulti.remove('Вообще не пью');
                  if (selected) {
                    currentMulti.add(option);
                  } else {
                    currentMulti.remove(option);
                  }
                }
                _answers[qId] = currentMulti; 
              } else {
                _answers[qId] = selected ? option : null; 
              }
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: (isSelected && option == 'Свой вариант')
              ? Padding(
                  padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
                  child: _buildTextField(qId, 'Напишите свой вариант...'),
                )
              : const SizedBox.shrink(),
        )
      ],
    );
  }

  Widget _buildTextField(String qId, String hint) {
    final double screenWidth = MediaQuery.of(context).size.width;
    
    return SizedBox(
      width: screenWidth - 48, 
      child: TextField(
        controller: _customTextControllers[qId],
        maxLines: 3, minLines: 1,
        style: const TextStyle(color: _textColor, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.grey),
          filled: true, fillColor: const Color(0xFFF2F2F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}