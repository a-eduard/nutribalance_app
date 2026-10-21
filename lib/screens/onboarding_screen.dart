import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/calculation_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import '../services/analytics_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _pregWeekController = TextEditingController();

  String _selectedGoal = '';
  String _selectedActivity = '';
  DateTime? _lastPeriodDate;

  static const List<(String, String, IconData)> _goals = [
    ('Похудеть', 'Мягкий дефицит без жёстких диет', Icons.trending_down_rounded),
    ('Поддержание веса', 'Баланс и хорошее самочувствие', Icons.balance_rounded),
    ('Набрать вес', 'Энергия и сила', Icons.trending_up_rounded),
    ('Здоровая беременность', 'Бережное питание для двоих', Icons.child_friendly_rounded),
  ];
  static const List<(String, String, IconData)> _activities = [
    ('Низкая (сидячий образ)', 'Офис, мало движения', Icons.chair_outlined),
    ('Умеренная (1-2 тренировки)', 'Прогулки и 1–2 тренировки в неделю', Icons.directions_walk_rounded),
    ('Высокая (3-5 тренировок)', 'Регулярный спорт', Icons.fitness_center_rounded),
    ('Очень высокая (каждый день)', 'Ежедневные нагрузки', Icons.bolt_rounded),
  ];

  static const int _steps = 4;

  @override
  void initState() {
    super.initState();
    _prefillName();
  }

  Future<void> _prefillName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get().timeout(const Duration(seconds: 8));
      final name = doc.data()?['name']?.toString() ?? FirebaseAuth.instance.currentUser?.displayName ?? '';
      if (mounted && _nameController.text.isEmpty) setState(() => _nameController.text = name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _pregWeekController.dispose();
    super.dispose();
  }

  bool get _isPregnancy => _selectedGoal == 'Здоровая беременность';

  double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

  String? _validateStep() {
    switch (_currentIndex) {
      case 0:
        final age = _num(_ageController), height = _num(_heightController), weight = _num(_weightController);
        if (_nameController.text.trim().isEmpty) return 'Как тебя зовут?';
        if (age == null || age < 12 || age > 100) return 'Укажи возраст от 12 до 100 лет';
        if (height == null || height < 120 || height > 230) return 'Укажи рост в сантиметрах (120–230)';
        if (weight == null || weight < 30 || weight > 300) return 'Укажи вес в килограммах (30–300)';
        return null;
      case 1:
        return _selectedGoal.isEmpty ? 'Выбери цель' : null;
      case 2:
        if (_isPregnancy) {
          final w = int.tryParse(_pregWeekController.text.trim());
          return (w == null || w < 1 || w > 42) ? 'Укажи неделю беременности от 1 до 42' : null;
        }
        return _lastPeriodDate == null ? 'Укажи дату начала последних месячных' : null;
      case 3:
        return _selectedActivity.isEmpty ? 'Выбери уровень активности' : null;
    }
    return null;
  }

  void _next() {
    final error = _validateStep();
    if (error != null) {
      HapticFeedback.lightImpact();
      EvaSnack.show(context, error, type: EvaSnackType.error);
      return;
    }
    FocusScope.of(context).unfocus();
    if (_currentIndex < _steps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    } else {
      _saveProfileAndCalculate();
    }
  }

  void _back() {
    if (_currentIndex == 0) return;
    FocusScope.of(context).unfocus();
    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  Future<void> _saveProfileAndCalculate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);

    final double weight = _num(_weightController) ?? 65.0;
    final double height = _num(_heightController) ?? 165.0;
    final int age = (_num(_ageController) ?? 25).round();

    final Map<String, dynamic> userData = {
      'name': _nameController.text.trim(),
      'gender': 'female',
      'age': age,
      'height': height,
      'weight': weight,
      'goal': _selectedGoal,
      'activityLevel': _selectedActivity,
      'isPregnant': _isPregnancy,
      'appMode': _isPregnancy ? 'pregnancy' : 'standard',
      'isOnboardingCompleted': true,
      'joinDate': FieldValue.serverTimestamp(),
    };
    if (_isPregnancy) {
      final int weeks = int.tryParse(_pregWeekController.text.trim()) ?? 1;
      userData['pregnancyStartDate'] = Timestamp.fromDate(DateTime.now().subtract(Duration(days: weeks * 7)));
    } else if (_lastPeriodDate != null) {
      userData['lastPeriodStartDate'] = Timestamp.fromDate(_lastPeriodDate!);
    }

    try {
      // Расчёт нормы — локально и мгновенно; запись уйдёт на сервер в фоне.
      await CalculationService().recalculateAndSaveGoals(
        weight: weight,
        height: height,
        age: age,
        goal: _selectedGoal,
        activityLevel: _selectedActivity,
        isPregnant: _isPregnancy,
      );
      // Флаг завершения онбординга пишем последним — HomeWrapper сам откроет главный экран.
      FirebaseFirestore.instance.collection('users').doc(uid).set(userData, SetOptions(merge: true)).catchError((e) => debugPrint('onboarding save: $e'));
      Analytics.event('onboarding_complete', {'goal': _selectedGoal, 'app_mode': _isPregnancy ? 'pregnancy' : 'standard'});
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        EvaSnack.show(context, 'Не удалось сохранить. Попробуйте ещё раз', type: EvaSnackType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;

    return Scaffold(
      body: EvaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                child: Row(
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _currentIndex == 0 ? 0 : 1,
                      child: IconButton(
                        onPressed: _currentIndex == 0 ? null : _back,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: (_currentIndex + 1) / _steps),
                          duration: const Duration(milliseconds: 350),
                          builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${_currentIndex + 1}/$_steps', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  children: [
                    _buildParamsStep(theme),
                    _buildOptionsStep(theme, 'Твоя главная цель?', 'Ева подстроит норму и советы под неё', _goals, _selectedGoal, (v) => setState(() => _selectedGoal = v)),
                    _isPregnancy ? _buildPregnancyStep(theme) : _buildCycleStep(theme, palette),
                    _buildOptionsStep(theme, 'Уровень активности', 'Нужен для точного расчёта калорий', _activities, _selectedActivity, (v) => setState(() => _selectedActivity = v)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: EvaPrimaryButton(
                  label: _currentIndex == _steps - 1 ? 'Рассчитать мою норму' : 'Далее',
                  loading: _isLoading,
                  onPressed: _next,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepHeader(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(subtitle, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildParamsStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        _stepHeader(theme, 'Давай знакомиться ✨', 'Это нужно, чтобы точно рассчитать твою норму'),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Имя', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Возраст', suffixText: 'лет', prefixIcon: Icon(Icons.cake_outlined)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Рост', suffixText: 'см'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _next(),
                decoration: const InputDecoration(labelText: 'Вес', suffixText: 'кг'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionsStep(
    ThemeData theme,
    String title,
    String subtitle,
    List<(String, String, IconData)> options,
    String current,
    ValueChanged<String> onSelect,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        _stepHeader(theme, title, subtitle),
        ...options.map((o) => EvaOptionTile(
              title: o.$1,
              subtitle: o.$2,
              icon: o.$3,
              selected: current == o.$1,
              onTap: () => onSelect(o.$1),
            )),
      ],
    );
  }

  Widget _buildCycleStep(ThemeData theme, EvaPalette palette) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        _stepHeader(theme, 'Женское здоровье 🌸', 'Ева будет адаптировать питание под фазы твоего цикла'),
        EvaCard(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              helpText: 'Начало последних месячных',
              initialDate: _lastPeriodDate ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 90)),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _lastPeriodDate = picked);
          },
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const EvaIconBubble(icon: Icons.calendar_month_rounded, color: EvaColors.menstruation),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Начало последних месячных', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      _lastPeriodDate == null ? 'Выбрать дату' : DateFormat('d MMMM yyyy', 'ru').format(_lastPeriodDate!),
                      style: theme.textTheme.titleMedium?.copyWith(color: _lastPeriodDate == null ? theme.colorScheme.primary : theme.colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Не помнишь точно? Укажи примерную дату — её всегда можно изменить в «Гармонии».', style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _buildPregnancyStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        _stepHeader(theme, 'Прекрасные новости! 👶', 'Ева будет особенно бережно следить за твоим питанием'),
        TextField(
          controller: _pregWeekController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Текущая неделя беременности', hintText: 'от 1 до 42', prefixIcon: Icon(Icons.child_friendly_rounded)),
        ),
      ],
    );
  }
}
