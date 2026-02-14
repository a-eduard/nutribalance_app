import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _genderController = TextEditingController(); 
  
  bool _isLoading = false;
  
  // Локальные переменные для ролей
  String _registeredRole = 'user';
  String _activeRole = 'user';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _genderController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    DatabaseService().getUserData().listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _ageController.text = data['age']?.toString() ?? '';
          _weightController.text = data['weight']?.toString() ?? '';
          _heightController.text = data['height']?.toString() ?? '';
          _genderController.text = data['gender'] ?? '';
          
          // Обновляем статусы ролей
          _registeredRole = data['registeredRole'] ?? 'user';
          _activeRole = data['activeRole'] ?? 'user';
        });
      }
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final double weight = double.tryParse(_weightController.text.replaceAll(',', '.')) ?? 0.0;
      final int height = int.tryParse(_heightController.text) ?? 0;
      final int age = int.tryParse(_ageController.text) ?? 0;

      await DatabaseService().updateUserData({
        'name': _nameController.text.trim(),
        'age': age,
        'weight': weight,
        'height': height,
        'gender': _genderController.text.trim(),
        'lastUpdated': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Профиль сохранен", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFFCCFF00),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        title: const Text("ПРОФИЛЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Выйти из аккаунта',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            
            // АВАТАР И ТУМБЛЕР РЕЖИМА
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1C1C1E),
                          border: Border.all(color: const Color(0xFF1C1C1E), width: 2),
                        ),
                        child: const Icon(Icons.person, size: 50, color: Colors.grey),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFCCFF00),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  
                  // ПОКАЗЫВАЕМ ТУМБЛЕР ТОЛЬКО ЗАРЕГИСТРИРОВАННЫМ ТРЕНЕРАМ
                  if (_registeredRole == 'coach') ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.3), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _activeRole == 'coach' ? Icons.sports : Icons.fitness_center, 
                            color: const Color(0xFFCCFF00), 
                            size: 20
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _activeRole == 'coach' ? "РЕЖИМ ТРЕНЕРА" : "РЕЖИМ ПОЛЬЗОВАТЕЛЯ", 
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)
                          ),
                          const SizedBox(width: 8),
                          Switch(
                            value: _activeRole == 'coach',
                            activeColor: Colors.black,
                            activeTrackColor: const Color(0xFFCCFF00),
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.black,
                            onChanged: (val) async {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              if (uid != null) {
                                await FirebaseFirestore.instance.collection('users').doc(uid).update({
                                  'activeRole': val ? 'coach' : 'user'
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 40),
            
            // ИМЯ
            _buildLabel("ИМЯ"),
            _buildMinimalInput(_nameController, "Ваше имя"),
            
            const SizedBox(height: 24),
            
            // СЕТКА 2x2
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("ВЕС (КГ)"),
                      _buildMinimalInput(_weightController, "0.0", isNumber: true),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("РОСТ (СМ)"),
                      _buildMinimalInput(_heightController, "0", isNumber: true),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("ВОЗРАСТ"),
                      _buildMinimalInput(_ageController, "0", isNumber: true),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("ПОЛ"), 
                      _buildMinimalInput(_genderController, "M / Ж"),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 60),

            // КНОПКА СОХРАНИТЬ
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFCCFF00).withOpacity(0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  )
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCCFF00),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _isLoading 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("СОХРАНИТЬ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
      ),
    );
  }

  Widget _buildMinimalInput(TextEditingController controller, String hint, {bool isNumber = false}) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), 
        borderRadius: BorderRadius.circular(12), 
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        textAlign: TextAlign.center, 
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        cursorColor: const Color(0xFFCCFF00),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 16),
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          isDense: true,
        ),
      ),
    );
  }
}