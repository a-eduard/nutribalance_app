import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/push_notification_service.dart';
import 'home_wrapper.dart';

import '../widgets/base_background.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _nicknameController = TextEditingController();

  final _bioController = TextEditingController();
  final _expController = TextEditingController();
  final _priceController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  bool _isLoading = false;
  String _selectedRole = 'athlete';
  String _registeredRole = 'athlete';

  String _selectedGender = 'Мужской';

  String? _currentPhotoUrl;
  File? _newPhotoFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;

        _registeredRole = data['registeredRole'] ?? 'athlete';
        if (_registeredRole == 'user') _registeredRole = 'athlete';

        String activeRole = data['activeRole'] ?? 'athlete';
        if (activeRole == 'user') activeRole = 'athlete';

        String dbGender = data['gender']?.toString().toLowerCase() ?? '';
        String safeGender = 'Мужской';
        if (dbGender == 'female' || dbGender == 'женский') {
          safeGender = 'Женский';
        }

        setState(() {
          _nameController.text = data['name'] ?? '';
          _lastNameController.text = data['lastName'] ?? '';
          _nicknameController.text = data['nickname'] ?? '';

          _bioController.text = data['bio'] ?? '';
          _selectedRole = activeRole;
          _expController.text = data['experience'] ?? '';
          _priceController.text = data['price']?.toString() ?? '';
          _ageController.text = data['age']?.toString() ?? '';
          _heightController.text = data['height']?.toString() ?? '';
          _weightController.text = data['weight']?.toString() ?? '';

          _selectedGender = safeGender;

          _currentPhotoUrl = data['photoUrl'];
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1080,
        maxHeight: 1080,
      );
      if (picked != null) setState(() => _newPhotoFile = File(picked.path));
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      String? photoUrlToSave = _currentPhotoUrl;
      if (_newPhotoFile != null) {
        final url = await StorageService().uploadUserAvatar(
          _newPhotoFile!,
          uid,
        );
        if (url != null) photoUrlToSave = url;
      }

      final int parsedPrice = int.tryParse(_priceController.text.trim()) ?? 0;

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'nickname': _nicknameController.text.trim().toLowerCase(),
        'bio': _bioController.text.trim(),
        'photoUrl': photoUrlToSave,
        'activeRole': _selectedRole,
        if (_selectedRole == 'coach') 'experience': _expController.text.trim(),
        if (_selectedRole == 'coach') 'price': parsedPrice,
        if (_selectedRole == 'athlete')
          'age': int.tryParse(_ageController.text) ?? 0,
        if (_selectedRole == 'athlete')
          'height': int.tryParse(_heightController.text) ?? 0,
        if (_selectedRole == 'athlete')
          'weight':
              double.tryParse(_weightController.text.replaceAll(',', '.')) ??
              0.0,
        if (_selectedRole == 'athlete') 'gender': _selectedGender,
      });

      if (_registeredRole == 'coach' || _selectedRole == 'coach') {
        await FirebaseFirestore.instance.collection('coaches').doc(uid).set({
          'name': _nameController.text.trim(),
          'lastName': _lastNameController.text.trim(),
          'nickname': _nicknameController.text.trim().toLowerCase(),
          'bio': _bioController.text.trim(),
          'photoUrl': photoUrlToSave,
          'specialization': _expController.text.trim(),
          'price': parsedPrice,
        }, SetOptions(merge: true));
      }

      if (_selectedRole == 'athlete' && _weightController.text.isNotEmpty) {
        double? newWeight = double.tryParse(
          _weightController.text.replaceAll(',', '.'),
        );
        if (newWeight != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('weight_history')
              .add({'weight': newWeight, 'date': FieldValue.serverTimestamp()});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('data_saved'.tr()),
            backgroundColor: const Color(0xFFB76E79),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${'error_msg'.tr()}: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ФИКС БАГА 5: Смена пароля ---
  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Письмо для сброса пароля отправлено на почту!",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Color(0xFFB76E79),
            ),
          );
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red),
          );
      }
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);
    await PushNotificationService().clearToken(); // Убиваем токен
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeWrapper()),
        (route) => false,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final uid = user.uid;
      final db = FirebaseFirestore.instance;
      final subcollections = [
        'workouts',
        'history',
        'meals',
        'nutrition_goal',
        'weight_history',
        'custom_exercises',
        'ai_chats_trainer',
        'ai_chats_dietitian',
        'assigned_workouts',
      ];

      for (String sub in subcollections) {
        final snap = await db
            .collection('users')
            .doc(uid)
            .collection(sub)
            .get();
        for (var doc in snap.docs) await doc.reference.delete();
      }

      await db.collection('users').doc(uid).delete();
      await user.delete();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Пожалуйста, выйдите из аккаунта и войдите заново для удаления.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orangeAccent,
            ),
          );
      }
    } catch (e) {}
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          'Удаление аккаунта',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Все ваши данные будут удалены безвозвратно.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAccount();
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarSection() {
    ImageProvider? imageProvider;
    if (_newPhotoFile != null) {
      imageProvider = FileImage(_newPhotoFile!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      if (_currentPhotoUrl!.startsWith('http')) {
        imageProvider = CachedNetworkImageProvider(_currentPhotoUrl!);
      } else {
        try {
          imageProvider = MemoryImage(base64Decode(_currentPhotoUrl!));
        } catch (_) {}
      }
    }

    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[800],
              backgroundImage: imageProvider,
              child: imageProvider == null
                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFB76E79),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(String title, String role) {
    final isActive = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFB76E79)
                : Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFB76E79)
                  : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: Colors.black.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Настройки',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatarSection(),
                const SizedBox(height: 32),

                if (_registeredRole == 'coach') ...[
                  Row(
                    children: [
                      _buildRoleButton('Атлет', "athlete"),
                      const SizedBox(width: 12),
                      _buildRoleButton('Тренер', "coach"),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],

                _buildInputField(_nameController, 'Имя'),
                _buildInputField(_lastNameController, 'Фамилия (опционально)'),
                _buildInputField(_nicknameController, 'Никнейм (@username)'),
                _buildInputField(_bioController, 'about_me'.tr(), maxLines: 3),

                if (_selectedRole == 'coach') ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12, top: 8),
                    child: Text(
                      'pro_data'.tr(),
                      style: const TextStyle(
                        color: Color(0xFFB76E79),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildInputField(_expController, 'experience'.tr()),
                  _buildInputField(
                    _priceController,
                    'price_services'.tr(),
                    isNumber: true,
                  ),
                ],

                if (_selectedRole == 'athlete') ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: DropdownButtonFormField<String>(
                      value: _selectedGender,
                      dropdownColor: const Color(0xFF1C1C1E),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Пол',
                        labelStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.black.withOpacity(0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: ['Мужской', 'Женский']
                          .map(
                            (String value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (newValue) =>
                          setState(() => _selectedGender = newValue!),
                    ),
                  ),
                  _buildInputField(_ageController, 'Возраст', isNumber: true),
                  _buildInputField(
                    _heightController,
                    'Рост (см)',
                    isNumber: true,
                  ),
                  _buildInputField(
                    _weightController,
                    'Вес (кг)',
                    isNumber: true,
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(color: Colors.white10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description, color: Colors.grey),
                  title: const Text(
                    'Пользовательское соглашение',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  trailing: const Icon(
                    Icons.open_in_new,
                    color: Colors.grey,
                    size: 16,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(
                      "https://docs.google.com/document/d/1aZNeAoui_eiEuxMTW3KEJNo9fMktMt-esbsrEmKgi6I/edit?usp=sharing",
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip, color: Colors.grey),
                  title: const Text(
                    'Политика конфиденциальности',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  trailing: const Icon(
                    Icons.open_in_new,
                    color: Colors.grey,
                    size: 16,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(
                      "https://docs.google.com/document/d/1LZXjxv2vJYXOkicb_zsul8NM4VNoBAQhuw7hycOiyBQ/edit?usp=sharing",
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const Divider(color: Colors.white10),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB76E79),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isLoading ? null : _saveChanges,
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'СОХРАНИТЬ',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 32),

                // --- ФИКС БАГА 5: Кнопка "Сменить пароль" ---
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.lock_reset,
                    color: Colors.orangeAccent,
                  ),
                  title: const Text(
                    'Сменить пароль',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: _changePassword,
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.white54),
                  title: Text(
                    'logout_account'.tr(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap:
                      _logout, // Теперь кнопка ссылается на наш новый безопасный метод
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  title: const Text(
                    'Удалить аккаунт',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () => _showDeleteAccountDialog(context),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
