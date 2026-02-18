import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_widgets.dart'; // Убедись, что путь к виджетам верный
import 'screens/dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  
  String _selectedGender = 'male'; // 'male' или 'female'
  bool _isLoading = false;

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final weight = _weightController.text.trim();
    final age = _ageController.text.trim();

    if (name.isEmpty || weight.isEmpty || age.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пожалуйста, заполните все поля"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Сохраняем данные пользователя
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': name,
        'gender': _selectedGender,
        'weight': double.tryParse(weight.replaceAll(',', '.')) ?? 0.0,
        'age': int.tryParse(age) ?? 0,
        'joinDate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        // Переходим на главный экран и удаляем историю навигации
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                const Text("Добро пожаловать", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16)),
                const SizedBox(height: 8),
                const Text("ДАВАЙ ЗНАКОМИТЬСЯ", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
                const SizedBox(height: 40),

                // 1. ИМЯ
                const Text("Как к тебе обращаться?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                HeavyInput(
                  controller: _nameController, 
                  hint: "Твое имя", 
                  onChanged: (v) {},
                ),

                const SizedBox(height: 24),

                // 2. ПОЛ
                const Text("Пол", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _GenderButton(
                      label: "Мужчина", 
                      icon: Icons.male, 
                      isSelected: _selectedGender == 'male', 
                      onTap: () => setState(() => _selectedGender = 'male')
                    ),
                    const SizedBox(width: 16),
                    _GenderButton(
                      label: "Женщина", 
                      icon: Icons.female, 
                      isSelected: _selectedGender == 'female', 
                      onTap: () => setState(() => _selectedGender = 'female')
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 3. ВЕС И ВОЗРАСТ
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Вес (кг)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          HeavyInput(
                            controller: _weightController, 
                            hint: "80", 
                            keyboardType: TextInputType.number,
                            onChanged: (v) {},
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Возраст", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          HeavyInput(
                            controller: _ageController, 
                            hint: "25", 
                            keyboardType: TextInputType.number,
                            onChanged: (v) {},
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 60),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)))
                else
                  NeonActionButton(
                    text: "НАЧАТЬ ТРАНСФОРМАЦИЮ", 
                    onTap: _saveProfile,
                    isFullWidth: true, // Убедись, что твоя кнопка поддерживает этот параметр, или убери его
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Виджет кнопки выбора пола
class _GenderButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderButton({required this.label, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFCCFF00) : const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? const Color(0xFFCCFF00) : Colors.white10),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.black : Colors.white, size: 28),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}