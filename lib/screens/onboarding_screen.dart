import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/calculation_service.dart';
import '../ui_widgets.dart';
import 'dashboard_screen.dart';

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

  final List<String> _goals = ['Похудеть', 'Поддержание веса', 'Набрать вес', 'Здоровая беременность'];
  final List<String> _activities = ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'];

  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);

  @override
  void initState() {
    super.initState();
    _prefillName();
  }

  Future<void> _prefillName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() => _nameController.text = data['name'] ?? '');
      }
    }
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

  List<Widget> get _screens {
    List<Widget> steps = [];
    steps.add(_buildParamsStep());
    steps.add(_buildSelectionStep("Ваша главная цель?", _goals, _selectedGoal, (v) => setState(() => _selectedGoal = v)));
    if (_selectedGoal == 'Здоровая беременность') steps.add(_buildPregnancyStep());
    else steps.add(_buildCycleStep());
    steps.add(_buildSelectionStep("Уровень активности?", _activities, _selectedActivity, (v) => setState(() => _selectedActivity = v)));
    return steps;
  }

  void _nextPage() {
    if (_currentIndex == 0) {
      if (_nameController.text.isEmpty || _ageController.text.isEmpty || _heightController.text.isEmpty || _weightController.text.isEmpty) return _showError("Пожалуйста, заполните все параметры");
    } else if (_currentIndex == 1) {
      if (_selectedGoal.isEmpty) return _showError("Выберите цель");
    } else if (_currentIndex == 2) {
      if (_selectedGoal == 'Здоровая беременность' && _pregWeekController.text.isEmpty) return _showError("Укажите неделю беременности");
      else if (_selectedGoal != 'Здоровая беременность' && _lastPeriodDate == null) return _showError("Укажите дату начала цикла");
    }
    
    if (_currentIndex < _screens.length - 1) _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    else {
      if (_selectedActivity.isEmpty) return _showError("Выберите уровень активности");
      _saveProfileAndCalculate();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
  }

  Future<void> _saveProfileAndCalculate() async {
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final double weight = double.tryParse(_weightController.text.replaceAll(',', '.')) ?? 65.0;
      final double height = double.tryParse(_heightController.text.replaceAll(',', '.')) ?? 165.0;
      final int age = int.tryParse(_ageController.text) ?? 25;
      final bool isPregnant = _selectedGoal == 'Здоровая беременность';

      Map<String, dynamic> userData = {
        'name': _nameController.text.trim(),
        'gender': 'female', 
        'age': age,
        'height': height,
        'weight': weight,
        'goal': _selectedGoal,
        'activityLevel': _selectedActivity,
        'isPregnant': isPregnant,
        'isOnboardingCompleted': true, 
        'joinDate': FieldValue.serverTimestamp(),
      };

      if (isPregnant) {
        int weeks = int.tryParse(_pregWeekController.text) ?? 1;
        userData['pregnancyStartDate'] = Timestamp.fromDate(DateTime.now().subtract(Duration(days: weeks * 7)));
      } else if (_lastPeriodDate != null) {
        userData['lastPeriodStartDate'] = Timestamp.fromDate(_lastPeriodDate!);
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(userData, SetOptions(merge: true));
      await CalculationService().recalculateAndSaveGoals(weight: weight, height: height, age: age, goal: _selectedGoal, activityLevel: _selectedActivity, isPregnant: isPregnant);

      if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const DashboardScreen()), (route) => false);
    } catch (e) {
      _showError("Ошибка сохранения: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        title: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _screens.length,
            backgroundColor: const Color(0xFFE5E5EA),
            valueColor: const AlwaysStoppedAnimation<Color>(_accentColor),
            minHeight: 6,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (idx) => setState(() => _currentIndex = idx),
                  children: _screens,
                ),
              ),
              SizedBox(
                width: double.infinity, height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0),
                  onPressed: _isLoading ? null : _nextPage,
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_currentIndex == _screens.length - 1 ? "РАССЧИТАТЬ НОРМУ" : "ДАЛЕЕ", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 1.0)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParamsStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Давай знакомиться ✨", style: TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 12),
          const Text("Это нужно для точного расчета нормы калорий", style: TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 32),
          HeavyInput(controller: _nameController, hint: "Твое имя", onChanged: (v) {}, keyboardType: TextInputType.name),
          const SizedBox(height: 16),
          HeavyInput(controller: _ageController, hint: "Возраст (лет)", onChanged: (v) {}, keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          HeavyInput(controller: _heightController, hint: "Рост (см)", onChanged: (v) {}, keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          HeavyInput(controller: _weightController, hint: "Вес (кг)", onChanged: (v) {}, keyboardType: TextInputType.number),
        ],
      ),
    );
  }

  Widget _buildSelectionStep(String title, List<String> options, String currentValue, Function(String) onSelect) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 32),
        ...options.map((opt) {
          final isSelected = currentValue == opt;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? _accentColor.withValues(alpha: 0.1) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))] : [],
                border: Border.all(color: isSelected ? _accentColor : Colors.transparent, width: 2),
              ),
              child: Row(
                children: [
                  Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, color: isSelected ? _accentColor : const Color(0xFFE5E5EA)),
                  const SizedBox(width: 16),
                  Expanded(child: Text(opt, style: TextStyle(color: _textColor, fontSize: 16, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600))),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCycleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Женское здоровье 🌸", style: TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 12),
        const Text("Ева будет адаптировать питание под фазы твоего цикла.", style: TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 60)),
              lastDate: DateTime.now(),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: _accentColor, onPrimary: Colors.white, onSurface: _textColor)),
                  child: child!,
                );
              },
            );
            if (picked != null) setState(() => _lastPeriodDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: _accentColor),
                const SizedBox(width: 16),
                Expanded(child: Text(_lastPeriodDate == null ? "Начало последних месячных" : DateFormat('dd MMMM yyyy', 'ru').format(_lastPeriodDate!), style: TextStyle(color: _lastPeriodDate == null ? Colors.grey : _textColor, fontSize: 16, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPregnancyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Прекрасные новости! 👶", style: TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
        const SizedBox(height: 12),
        const Text("Ева будет особенно бережно следить за твоим питанием.", style: TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 32),
        HeavyInput(controller: _pregWeekController, hint: "Текущая неделя беременности (от 1 до 42)", onChanged: (v) {}, keyboardType: TextInputType.number),
      ],
    );
  }
}