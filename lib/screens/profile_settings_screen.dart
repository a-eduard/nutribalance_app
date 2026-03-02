import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // Добавлено для ссылок
import 'package:url_launcher/url_launcher.dart'; // Добавлено для ссылок
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/push_notification_service.dart';

import '../services/storage_service.dart';
import '../widgets/base_background.dart';
import 'home_wrapper.dart'; 

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  // --- Общие поля ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  String _selectedGender = 'не указан'; // БЛОК 4: Добавлена переменная пола

  // --- Поля Тренера ---
  final TextEditingController _specializationController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  // --- Поля Клиента (Атлета) ---
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _goalsController = TextEditingController();

  bool _isFetching = true;
  bool _isLoading = false;
  String _activeRole = 'athlete'; 

  String? _currentPhotoUrl; 
  File? _newPhotoFile;      
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _specializationController.dispose();
    _bioController.dispose();
    _priceController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _goalsController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() as Map<String, dynamic>;
        
        setState(() {
          _activeRole = userData['activeRole'] ?? 'athlete';
          _nameController.text = userData['name'] ?? '';
          _nicknameController.text = userData['nickname'] ?? '';
          _currentPhotoUrl = userData['photoUrl'];
          _selectedGender = userData['gender'] ?? 'не указан'; // Читаем пол
          
          _ageController.text = userData['age']?.toString() ?? '';
          _heightController.text = userData['height']?.toString() ?? '';
          _weightController.text = userData['weight']?.toString() ?? '';
          _goalsController.text = userData['goals'] ?? '';
        });
      }

      final coachDoc = await FirebaseFirestore.instance.collection('coaches').doc(uid).get();
      if (coachDoc.exists && mounted) {
        final coachData = coachDoc.data() as Map<String, dynamic>;
        setState(() {
          _specializationController.text = coachData['specialization'] ?? '';
          _bioController.text = coachData['bio'] ?? '';
          _priceController.text = coachData['price']?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint("Ошибка загрузки данных профиля: $e");
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (pickedFile != null) setState(() => _newPhotoFile = File(pickedFile.path));
    } catch (e) {
      debugPrint("Ошибка выбора фото: $e");
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);

    try {
      String? photoToSave = _currentPhotoUrl;
      if (_newPhotoFile != null) {
        final url = await StorageService().uploadUserAvatar(_newPhotoFile!, uid);
        if (url != null) photoToSave = url;
      }
      
      final String newName = _nameController.text.trim();

      Map<String, dynamic> userUpdates = {
        'name': newName,
        'nickname': _nicknameController.text.trim(),
        'gender': _selectedGender, // Сохраняем пол
        'photoUrl': photoToSave ?? '', 
      };

      if (_activeRole == 'athlete') {
        userUpdates.addAll({
          'age': _ageController.text.trim(),
          'height': _heightController.text.trim(),
          'weight': _weightController.text.trim(),
          'goals': _goalsController.text.trim(),
        });
      }
      
      await FirebaseFirestore.instance.collection('users').doc(uid).set(userUpdates, SetOptions(merge: true));

      if (_activeRole == 'coach') {
        await FirebaseFirestore.instance.collection('coaches').doc(uid).set({
          'name': newName, 
          'photoUrl': photoToSave ?? '',       
          'specialization': _specializationController.text.trim(),
          'bio': _bioController.text.trim(),
          'price': _priceController.text.trim(),
          'rating': 5.0, 
        }, SetOptions(merge: true));

        // БЛОК 4: ГЛОБАЛЬНАЯ СИНХРОНИЗАЦИЯ ИМЕНИ В ЧАТАХ
        final chatsQuery = await FirebaseFirestore.instance.collection('chats').where('users', arrayContains: uid).get();
        for (var chatDoc in chatsQuery.docs) {
          final data = chatDoc.data();
          if (data['userNames'] != null && data['userNames'][uid] != null) {
            await chatDoc.reference.update({
              'userNames.$uid': newName,
            });
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Профиль успешно обновлен!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
          backgroundColor: Color(0xFF9CD600)
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Ошибка сохранения профиля: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);
    await PushNotificationService().clearToken(); 
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeWrapper()), 
        (route) => false
      );
    }
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Письмо для сброса пароля отправлено на почту!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Color(0xFF9CD600))
          );
        }
      } catch (e) {
        debugPrint("Ошибка сброса пароля: $e");
      }
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);

    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;
      
      try { await db.collection('coaches').doc(uid).delete(); } catch (e) { debugPrint("Ошибка удаления из coaches: $e"); }

      final subcollections = [
        'workouts', 'history', 'meals', 'nutrition_goal', 
        'weight_history', 'custom_exercises', 'ai_chats_trainer', 
        'ai_chats_dietitian', 'assigned_workouts', 'rated_coaches', 
        'client_notes', 'athlete_requests'
      ];
      
      for (String sub in subcollections) {
        try {
          final snap = await db.collection('users').doc(uid).collection(sub).get();
          for (var doc in snap.docs) { await doc.reference.delete(); }
        } catch (e) {}
      }

      try {
        final snap = await db.collection('coaches').doc(uid).collection('rated_clients').get();
        for (var doc in snap.docs) { await doc.reference.delete(); }
      } catch (e) {}

      try { await db.collection('users').doc(uid).delete(); } catch (e) {}
      await user.delete();
      
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeWrapper()), 
          (route) => false
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('В целях безопасности выйдите из аккаунта и войдите заново для удаления.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.orangeAccent)
          );
        }
      }
    } catch (e) {
      debugPrint("Критическая ошибка удаления аккаунта: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Удаление аккаунта', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Все ваши данные будут удалены безвозвратно.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () { Navigator.pop(ctx); _deleteAccount(); },
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;
    if (_newPhotoFile != null) imageProvider = FileImage(_newPhotoFile!);
    else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      if (_currentPhotoUrl!.startsWith('http')) imageProvider = NetworkImage(_currentPhotoUrl!);
      else { try { imageProvider = MemoryImage(base64Decode(_currentPhotoUrl!)); } catch (_) {} }
    }

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Настройки профиля", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: _isFetching 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _pickImage,
                          child: CircleAvatar(radius: 60, backgroundColor: const Color(0xFF1C1C1E), backgroundImage: imageProvider, child: imageProvider == null ? const Icon(Icons.person, size: 60, color: Colors.grey) : null),
                        ),
                        Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _pickImage, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF9CD600), shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 3)), child: const Icon(Icons.camera_alt, size: 20, color: Colors.black)))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  const Text("ОБЩИЕ ДАННЫЕ", style: TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 16),
                  
                  _buildLabel("Имя / Фамилия"),
                  _buildInputField(_nameController, "Как к вам обращаться?", Icons.person),
                  const SizedBox(height: 16),
                  
                  _buildLabel("Никнейм"),
                  _buildInputField(_nicknameController, "@username", Icons.alternate_email),
                  const SizedBox(height: 16),
                  
                  // БЛОК 4: Добавлено поле выбора пола
                  _buildLabel("Пол"),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedGender,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1C1C1E),
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                        items: <String>['Мужской', 'Женский', 'не указан'].map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value));
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) setState(() => _selectedGender = newValue);
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),

                  Text(_activeRole == 'coach' ? "ПРОФИЛЬ ТРЕНЕРА" : "ПРОФИЛЬ АТЛЕТА", style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 16),

                  if (_activeRole == 'coach') ...[
                    _buildLabel("Специализация"),
                    _buildInputField(_specializationController, "Например: Набор массы, Сушка", Icons.fitness_center),
                    const SizedBox(height: 16),
                    
                    _buildLabel("О себе"),
                    _buildInputField(_bioController, "Опыт, достижения...", null, maxLines: 3),
                    const SizedBox(height: 16),
                    
                    _buildLabel("Стоимость услуг"),
                    _buildInputField(_priceController, "Например: 5000 руб/мес", Icons.payments),
                  ] else ...[
                    Row(
                      children: [
                        // БЛОК 4: Убраны иконки, уменьшен отступ, чтобы длинные числа (105.5) влезали
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildLabel("Возраст"), _buildMiniNumberField(_ageController, "Лет")])),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildLabel("Рост"), _buildMiniNumberField(_heightController, "см")])),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildLabel("Вес"), _buildMiniNumberField(_weightController, "кг")])),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildLabel("Ваша цель"),
                    _buildInputField(_goalsController, "Похудение, набор массы...", Icons.flag),
                  ],
                  
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CD600), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) : const Text("СОХРАНИТЬ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  
                  const Text("ПРАВОВАЯ ИНФОРМАЦИЯ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  
                  // БЛОК 4: Возвращены юридические документы
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Политика конфиденциальности", style: TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.underline)),
                    onTap: () => launchUrl(Uri.parse("https://docs.google.com/document/d/1LZXjxv2vJYXOkicb_zsul8NM4VNoBAQhuw7hycOiyBQ/edit?usp=sharing"), mode: LaunchMode.externalApplication),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Пользовательское соглашение", style: TextStyle(color: Colors.white70, fontSize: 14, decoration: TextDecoration.underline)),
                    onTap: () => launchUrl(Uri.parse("https://docs.google.com/document/d/1aZNeAoui_eiEuxMTW3KEJNo9fMktMt-esbsrEmKgi6I/edit?usp=sharing"), mode: LaunchMode.externalApplication),
                  ),

                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.lock_reset, color: Colors.orangeAccent),
                    title: const Text("Сменить пароль", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    onTap: _changePassword,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.logout, color: Colors.white54),
                    title: const Text("Выйти из аккаунта", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                    onTap: _logout,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                    title: const Text("Удалить аккаунт", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    onTap: () => _showDeleteAccountDialog(context),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8.0, left: 4.0), child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)));

  Widget _buildInputField(TextEditingController controller, String hint, IconData? icon, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: TextField(
        controller: controller, 
        maxLines: maxLines, 
        style: const TextStyle(color: Colors.white, fontSize: 16), 
        cursorColor: const Color(0xFF9CD600),
        decoration: InputDecoration(prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null, hintText: hint, hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 16 : 18)),
      ),
    );
  }

  // БЛОК 4: Новый метод для компактных полей (без иконок, меньше паддинги)
  Widget _buildMiniNumberField(TextEditingController controller, String hint) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
      child: TextField(
        controller: controller, 
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 16), 
        cursorColor: const Color(0xFF9CD600),
        decoration: InputDecoration(
          hintText: hint, 
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)), 
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16) // Уменьшили паддинги
        ),
      ),
    );
  }
}