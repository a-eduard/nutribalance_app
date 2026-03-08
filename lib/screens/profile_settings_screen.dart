import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import '../services/database_service.dart';
import '../widgets/base_background.dart';
import 'home_wrapper.dart';
import 'p2p_chat_screen.dart';
import '../services/local_notification_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const String SUPPORT_ADMIN_UID = 'ywzqqr6dhJbxGEwofUubgkptbGV2';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  String _selectedGender = 'не указан';

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _goalsController = TextEditingController();
  final TextEditingController _cycleLengthController = TextEditingController();

  bool _isFetching = true;
  bool _isLoading = false;
  bool _notificationsEnabled = true; 

  String? _currentPhotoUrl;
  File? _newPhotoFile;
  final ImagePicker _picker = ImagePicker();
  String? _nicknameError;

  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _accentColor = Color(0xFFB76E79);

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _goalsController.dispose();
    _cycleLengthController.dispose();
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
          _nameController.text = userData['name'] ?? '';
          _notificationsEnabled = userData['notificationsEnabled'] ?? true;

          String loadedNick = (userData['nickname'] ?? '').toString().toLowerCase();
          loadedNick = loadedNick.replaceAll(RegExp(r'[^a-z0-9_]'), '');
          _nicknameController.text = loadedNick;

          _currentPhotoUrl = userData['photoUrl'];
          _selectedGender = userData['gender'] ?? 'не указан';

          _ageController.text = userData['age']?.toString() ?? '';
          _heightController.text = userData['height']?.toString() ?? '';
          _weightController.text = userData['weight']?.toString() ?? '';
          _goalsController.text = userData['goals'] ?? '';
          _cycleLengthController.text = userData['cycleLength']?.toString() ?? '28';
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
    } catch (e) {}
  }

  void _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'notificationsEnabled': value});
    }

    if (value) {
      await LocalNotificationService().scheduleDailyNotifications();
    } else {
      await LocalNotificationService().cancelAll();
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);

    final String newNickname = _nicknameController.text.trim().replaceAll('@', '');

    if (newNickname.isNotEmpty) {
      final isUnique = await DatabaseService().isNicknameUnique(newNickname);
      if (!isUnique) {
        if (mounted) setState(() { _isLoading = false; _nicknameError = "Этот никнейм уже занят"; });
        return;
      }
    }

    try {
      String? photoToSave = _currentPhotoUrl;
      if (_newPhotoFile != null) {
        final url = await StorageService().uploadUserAvatar(_newPhotoFile!, uid);
        if (url != null) photoToSave = url;
      }

      final int? age = int.tryParse(_ageController.text.trim());
      final double? height = double.tryParse(_heightController.text.replaceAll(',', '.').trim());
      final double? weight = double.tryParse(_weightController.text.replaceAll(',', '.').trim());
      final int cycleLength = int.tryParse(_cycleLengthController.text.trim()) ?? 28;

      Map<String, dynamic> userUpdates = {
        'name': _nameController.text.trim(),
        'nickname': newNickname,
        'gender': _selectedGender,
        'photoUrl': photoToSave ?? '',
        'goals': _goalsController.text.trim(),
        'cycleLength': cycleLength,
      };

      if (age != null) userUpdates['age'] = age;
      if (height != null) userUpdates['height'] = height;
      if (weight != null) userUpdates['weight'] = weight;

      await DatabaseService().updateUserData(userUpdates);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Профиль обновлен!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
      Navigator.pop(context);
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
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeWrapper()), (route) => false);
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Письмо отправлено на почту!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
      } catch (e) {}
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      await user.delete();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeWrapper()), (route) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В целях безопасности перезайдите в аккаунт.'), backgroundColor: Colors.orangeAccent));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Удаление аккаунта', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        content: const Text('Все ваши данные будут удалены безвозвратно.', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); _deleteAccount(); }, child: const Text('Удалить', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildListField(String label, TextEditingController controller, String hint, IconData? icon, {int maxLines = 1, List<TextInputFormatter>? inputFormatters, String? errorText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, color: Colors.grey, size: 20), const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                TextField(
                  controller: controller, maxLines: maxLines, inputFormatters: inputFormatters,
                  style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500),
                  cursorColor: _accentColor,
                  decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontWeight: FontWeight.normal), errorText: errorText, errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4, bottom: 4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.wc, color: Colors.grey, size: 20), const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Пол", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 30,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedGender, isExpanded: true, dropdownColor: Colors.white,
                      style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500),
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      items: <String>['Мужской', 'Женский', 'не указан'].map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                      onChanged: (String? newValue) { if (newValue != null) setState(() => _selectedGender = newValue); },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
          TextField(
            controller: controller, keyboardType: TextInputType.number,
            style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500),
            cursorColor: _accentColor,
            decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4, bottom: 4)),
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
        appBar: AppBar(title: const Text("Настройки", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18)), backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: _textColor)),
        body: _isFetching
            ? const Center(child: CircularProgressIndicator(color: _accentColor))
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
                            child: CircleAvatar(radius: 55, backgroundColor: const Color(0xFFF0F0F0), backgroundImage: imageProvider, child: imageProvider == null ? const Icon(Icons.person, size: 55, color: Colors.grey) : null),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _accentColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)), child: const Icon(Icons.camera_alt, size: 16, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ОБЩИЕ ДАННЫЕ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      _buildListField("Имя / Фамилия", _nameController, "Как к вам обращаться?", Icons.person),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      _buildListField("Никнейм", _nicknameController, "username", Icons.alternate_email, errorText: _nicknameError, inputFormatters: [TextInputFormatter.withFunction((oldValue, newValue) { if (!RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(newValue.text)) return oldValue; return newValue.copyWith(text: newValue.text.toLowerCase()); })]),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      _buildGenderField(),
                    ]),

                    const SizedBox(height: 24),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРОФИЛЬ АТЛЕТА", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(child: _buildMiniMetric("Возраст", _ageController, "Лет")),
                            VerticalDivider(color: Colors.grey.withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Рост", _heightController, "см")),
                            VerticalDivider(color: Colors.grey.withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Вес", _weightController, "кг")),
                          ],
                        ),
                      ),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      _buildListField("Ваша цель", _goalsController, "Похудение, набор массы...", Icons.flag),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      _buildListField("Длина цикла (дней)", _cycleLengthController, "28", Icons.calendar_month, inputFormatters: [FilteringTextInputFormatter.digitsOnly]),
                    ]),

                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity, height: 56,
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [_accentColor, Color(0xFFD49A89)]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))]),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("НАСТРОЙКИ ПРИЛОЖЕНИЯ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      SwitchListTile(activeColor: _accentColor, title: const Text("Заботливые напоминания от Евы", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600)), subtitle: const Text("Вода, обед и итоги дня", style: TextStyle(color: Colors.grey, fontSize: 12)), value: _notificationsEnabled, onChanged: _toggleNotifications),
                    ]),

                    const SizedBox(height: 32),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРАВОВАЯ ИНФОРМАЦИЯ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      ListTile(leading: const Icon(Icons.description_outlined, color: Colors.grey, size: 20), title: const Text("Пользовательское соглашение", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14), onTap: () => launchUrl(Uri.parse("https://docs.google.com/document/d/1aZNeAoui_eiEuxMTW3KEJNo9fMktMt-esbsrEmKgi6I/edit?usp=sharing"), mode: LaunchMode.externalApplication)),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.privacy_tip_outlined, color: Colors.grey, size: 20), title: const Text("Политика конфиденциальности", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14), onTap: () => launchUrl(Uri.parse("https://docs.google.com/document/d/1LZXjxv2vJYXOkicb_zsul8NM4VNoBAQhuw7hycOiyBQ/edit?usp=sharing"), mode: LaunchMode.externalApplication)),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.support_agent, color: _accentColor, size: 22), title: const Text("Написать в поддержку", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 14)), trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: SUPPORT_ADMIN_UID, otherUserName: 'Поддержка NutriBalance'))); }),
                    ]),

                    const SizedBox(height: 24),
                    _buildSettingsCard([
                      ListTile(leading: const Icon(Icons.lock_reset, color: Colors.orangeAccent, size: 20), title: const Text("Сменить пароль", style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _changePassword),
                      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.logout, color: Colors.grey, size: 20), title: const Text("Выйти из аккаунта", style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _logout),
                    ]),

                    const SizedBox(height: 32),
                    Center(child: TextButton(onPressed: () => _showDeleteAccountDialog(context), child: const Text("Удалить аккаунт навсегда", style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600)))),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}