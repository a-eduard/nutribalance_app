import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui_widgets.dart';
import '../services/database_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _bodyFatController = TextEditingController();
  final TextEditingController _experienceController = TextEditingController();
  
  String _selectedGender = 'male';
  String? _avatarPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _avatarPath = prefs.getString('avatar_path'));
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('avatar_path', pickedFile.path);
      setState(() => _avatarPath = pickedFile.path);
    }
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _nameController.text = data['name'] ?? "";
        _selectedGender = data['gender'] ?? "male";
        _weightController.text = (data['weight'] ?? "").toString();
        _heightController.text = (data['height'] ?? "").toString();
        _ageController.text = (data['age'] ?? "").toString();
        _bodyFatController.text = (data['bodyFat'] ?? "").toString();
        _experienceController.text = data['experience'] ?? "";
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      await DatabaseService().updateUserData(
        name: _nameController.text,
        gender: _selectedGender,
        weight: double.tryParse(_weightController.text) ?? 0,
        height: double.tryParse(_heightController.text) ?? 0,
        age: int.tryParse(_ageController.text) ?? 0,
        bodyFat: double.tryParse(_bodyFatController.text) ?? 0,
        experience: _experienceController.text,
      );
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Сохранено!"), backgroundColor: Color(0xFFCCFF00)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  // НОВЫЙ МЕТОД: Показ диалога питания
  void _showNutritionPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00))));

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    
    if (mounted) Navigator.pop(context); // Закрываем лоадер

    if (data != null && data.containsKey('nutrition_plan')) {
      final plan = data['nutrition_plan'] as Map<String, dynamic>;
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text("🍎 Мой План Питания", style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPlanRow("Калории:", "${plan['calories']}"),
                _buildPlanRow("Белок:", "${plan['protein']}"),
                _buildPlanRow("Жиры:", "${plan['fats']}"),
                _buildPlanRow("Углеводы:", "${plan['carbs']}"),
                const Divider(color: Colors.white24),
                const SizedBox(height: 8),
                Text("Совет: ${plan['advice']}", style: const TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Закрыть", style: TextStyle(color: Color(0xFFCCFF00))))
          ],
        ),
      );
    } else {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("План питания еще не создан. Сгенерируйте его в AI Тренере.")));
    }
  }

  Widget _buildPlanRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(title: const Text("Профиль"), backgroundColor: Colors.transparent, actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () => FirebaseAuth.instance.signOut())]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Center(
              child: Stack(
                children: [
                  CircleAvatar(radius: 60, backgroundColor: const Color(0xFF1C1C1E), backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null, child: _avatarPath == null ? const Icon(Icons.person, size: 60, color: Colors.grey) : null),
                  Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _pickImage, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(color: Color(0xFFCCFF00), shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.black, size: 20)))),
                ],
              ),
            ),
            const SizedBox(height: 32),
            HeavyInput(controller: _nameController, hint: "Имя", onChanged: (v){}),
            const SizedBox(height: 16),
            Row(children: [const Text("Пол:", style: TextStyle(color: Colors.white, fontSize: 16)), const SizedBox(width: 20), ChoiceChip(label: const Text("М"), selected: _selectedGender == 'male', onSelected: (v) => setState(() => _selectedGender = 'male'), selectedColor: const Color(0xFFCCFF00)), const SizedBox(width: 10), ChoiceChip(label: const Text("Ж"), selected: _selectedGender == 'female', onSelected: (v) => setState(() => _selectedGender = 'female'), selectedColor: const Color(0xFFCCFF00))]),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: HeavyInput(controller: _weightController, hint: "Вес (кг)", keyboardType: TextInputType.number, onChanged: (v){})), const SizedBox(width: 16), Expanded(child: HeavyInput(controller: _heightController, hint: "Рост (см)", keyboardType: TextInputType.number, onChanged: (v){}))]),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: HeavyInput(controller: _ageController, hint: "Возраст", keyboardType: TextInputType.number, onChanged: (v){})), const SizedBox(width: 16), Expanded(child: HeavyInput(controller: _bodyFatController, hint: "% Жира", keyboardType: TextInputType.number, onChanged: (v){}))]),
            const SizedBox(height: 16),
            
            // ОБНОВЛЕННАЯ ПОДСКАЗКА
            HeavyInput(controller: _experienceController, hint: "Стаж тренировок (лет)", onChanged: (v){}),

            const SizedBox(height: 32),
            if (_isLoading) const CircularProgressIndicator(color: Color(0xFFCCFF00)) else NeonActionButton(text: "СОХРАНИТЬ", onTap: _saveProfile, isFullWidth: true),
            
            const SizedBox(height: 16),
            // КНОПКА ПЛАНА ПИТАНИЯ
            OutlinedButton.icon(
              onPressed: _showNutritionPlan, 
              icon: const Icon(Icons.restaurant_menu, color: Color(0xFFCCFF00)), 
              label: const Text("🍎 Мой План Питания", style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white10), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24)),
            ),
          ],
        ),
      ),
    );
  }
}