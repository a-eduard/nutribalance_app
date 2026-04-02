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
import '../services/calculation_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const String SUPPORT_ADMIN_UID = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  String _selectedGender = 'не указан';
  String _selectedActivity = 'Умеренная (1-2 тренировки)';

  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  String _selectedGoal = 'Похудеть';

  bool _isFetching = true;
  bool _isLoading = false;
  bool _notificationsEnabled = false; 

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
          _notificationsEnabled = userData['notificationsEnabled'] ?? false;

          String loadedNick = (userData['nickname'] ?? '').toString().toLowerCase();
          loadedNick = loadedNick.replaceAll(RegExp(r'[^a-z0-9_]'), '');
          _nicknameController.text = loadedNick;

          _currentPhotoUrl = userData['photoUrl'];
          _selectedGender = userData['gender'] ?? 'не указан';

          _ageController.text = userData['age']?.toString() ?? '';
          _heightController.text = userData['height']?.toString() ?? '';
          _weightController.text = userData['weight']?.toString() ?? '';
          _selectedGoal = userData['goal'] ?? userData['goals'] ?? 'Похудеть';
          _selectedActivity = userData['activityLevel'] ?? 'Умеренная (1-2 тренировки)';
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
    if (value) {
      final bool granted = await LocalNotificationService().requestPermissions();
      
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Необходимо разрешить уведомления в настройках телефона', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
              backgroundColor: _accentColor
            )
          );
        }
        setState(() => _notificationsEnabled = false);
        return;
      }
    }

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

      Map<String, dynamic> userUpdates = {
        'name': _nameController.text.trim(),
        'nickname': newNickname,
        'gender': _selectedGender,
        'photoUrl': photoToSave ?? '',
        'goal': _selectedGoal,
      };

      if (age != null) userUpdates['age'] = age;
      if (height != null) userUpdates['height'] = height;
      if (weight != null) userUpdates['weight'] = weight;

      await DatabaseService().updateUserData(userUpdates);

      if (age != null && height != null && weight != null) {
        await CalculationService().recalculateAndSaveGoals(
          weight: weight,
          height: height,
          age: age,
          goal: _selectedGoal,
          activityLevel: _selectedActivity,
          isPregnant: _selectedGoal == 'Здоровая беременность',
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Профиль обновлен! ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
      Navigator.pop(context); 
      // ИСПРАВЛЕН БАГ: Убран дублирующий Navigator.pop(context);
      
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
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.email != null) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Письмо отправлено на почту!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: _accentColor));
      }
    }
    if (mounted) setState(() => _isLoading = false);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В целях безопасности перезайдите в аккаунт.'), backgroundColor: Color(0xFFB6A6CA)));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Удаление аккаунта', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        content: const Text('Все ваши данные будут удалены безвозвратно.', style: TextStyle(color: Color(0xFF8E8E93))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: Color(0xFF8E8E93)))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _accentColor, elevation: 0), onPressed: () { Navigator.pop(ctx); _deleteAccount(); }, child: const Text('Удалить', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _showActivityBottomSheet() {
    final activities = ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Уровень активности", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor)),
              const SizedBox(height: 16),
              ...activities.map((act) => ListTile(
                title: Text(act, style: TextStyle(fontWeight: _selectedActivity == act ? FontWeight.bold : FontWeight.normal, color: _selectedActivity == act ? _accentColor : _textColor)),
                trailing: _selectedActivity == act ? const Icon(Icons.check, color: _accentColor) : null,
                onTap: () async {
                  setState(() => _selectedActivity = act);
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  await DatabaseService().updateActivityAndRecalculate(act);
                  setState(() => _isLoading = false);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Активность обновлена! ✨'), backgroundColor: _accentColor));
                },
              )),
            ],
          ),
        ),
      )
    );
  }

  void _showGoalBottomSheet() {
    final goals = ['Похудеть', 'Поддержание веса', 'Набрать вес', 'Здоровая беременность'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Ваша цель", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _textColor)),
              const SizedBox(height: 16),
              ...goals.map((g) => ListTile(
                title: Text(g, style: TextStyle(fontWeight: _selectedGoal == g ? FontWeight.bold : FontWeight.normal, color: _selectedGoal == g ? _accentColor : _textColor)),
                trailing: _selectedGoal == g ? const Icon(Icons.check, color: _accentColor) : null,
                onTap: () async {
                  setState(() => _selectedGoal = g);
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) await FirebaseFirestore.instance.collection('users').doc(uid).update({'goal': g});
                  setState(() => _isLoading = false);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Цель обновлена! ✨'), backgroundColor: _accentColor));
                },
              )),
            ],
          ),
        ),
      )
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
          if (icon != null) ...[Icon(icon, color: const Color(0xFF8E8E93), size: 20), const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold)),
                TextField(
                  controller: controller, maxLines: maxLines, inputFormatters: inputFormatters,
                  style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500),
                  cursorColor: _accentColor,
                  decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: const Color(0xFF8E8E93).withValues(alpha: 0.5), fontWeight: FontWeight.normal), errorText: errorText, errorStyle: const TextStyle(color: _accentColor, fontSize: 12), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4, bottom: 4)),
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
          Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold)),
          TextField(
            controller: controller, keyboardType: TextInputType.number,
            style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500),
            cursorColor: _accentColor,
            decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: const Color(0xFF8E8E93).withValues(alpha: 0.5)), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4, bottom: 4)),
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
        backgroundColor: const Color(0xFFF9F9F9),
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
                            child: CircleAvatar(radius: 55, backgroundColor: Colors.white, backgroundImage: imageProvider, child: imageProvider == null ? const Icon(Icons.person, size: 55, color: Color(0xFF8E8E93)) : null),
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

                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ОБЩИЕ ДАННЫЕ", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      _buildListField("Имя / Фамилия", _nameController, "Как к вам обращаться?", Icons.person),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      _buildListField("Никнейм", _nicknameController, "username", Icons.alternate_email, errorText: _nicknameError, inputFormatters: [TextInputFormatter.withFunction((oldValue, newValue) { if (!RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(newValue.text)) return oldValue; return newValue.copyWith(text: newValue.text.toLowerCase()); })]),
                    ]),

                    const SizedBox(height: 24),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРОФИЛЬ", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(child: _buildMiniMetric("Возраст", _ageController, "Лет")),
                            VerticalDivider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Рост", _heightController, "см")),
                            VerticalDivider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Вес", _weightController, "кг")),
                          ],
                        ),
                      ),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      ListTile(title: const Text("Уровень активности", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text(_selectedActivity, style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)), onTap: _showActivityBottomSheet),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      ListTile(title: const Text("Ваша цель", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text(_selectedGoal, style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)), onTap: _showGoalBottomSheet),
                    ]),

                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity, height: 56,
                      decoration: BoxDecoration(color: _accentColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))]),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("НАСТРОЙКИ ПРИЛОЖЕНИЯ", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      SwitchListTile(activeColor: _accentColor, title: const Text("Заботливые напоминания от Евы", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600)), subtitle: const Text("Вода, обед и итоги дня", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)), value: _notificationsEnabled, onChanged: _toggleNotifications),
                    ]),

                    const SizedBox(height: 32),
                    const Padding(padding: EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРАВОВАЯ ИНФОРМАЦИЯ", style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      ListTile(leading: const Icon(Icons.description_outlined, color: Color(0xFF8E8E93), size: 20), title: const Text("Пользовательское соглашение", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF8E8E93), size: 14), onTap: () { const String url = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing"; launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication); }),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF8E8E93), size: 20), title: const Text("Политика конфиденциальности", style: TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w500)), trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF8E8E93), size: 14), onTap: () { const String url = "https://docs.google.com/document/d/1ak-7-B2_uvmY1O7b6kJu-rUEOa5e_sDY/edit?usp=sharing"; launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication); }),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.support_agent, color: _accentColor, size: 22), title: const Text("Написать в поддержку", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 14)), trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF8E8E93), size: 14), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: SUPPORT_ADMIN_UID, otherUserName: 'Поддержка MyEva'))); }),
                    ]),

                    const SizedBox(height: 24),
                    _buildSettingsCard([
                      ListTile(leading: const Icon(Icons.lock_reset, color: Color(0xFFB6A6CA), size: 20), title: const Text("Сменить пароль", style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _changePassword),
                      Divider(color: const Color(0xFF8E8E93).withValues(alpha: 0.1), height: 1),
                      ListTile(leading: const Icon(Icons.logout, color: Color(0xFF8E8E93), size: 20), title: const Text("Выйти из аккаунта", style: TextStyle(color: _textColor, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _logout),
                    ]),

                    const SizedBox(height: 32),
                    Center(child: TextButton(onPressed: () => _showDeleteAccountDialog(context), child: const Text("Удалить аккаунт навсегда", style: TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w600)))),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}