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
import '../services/theme_service.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const String supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

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
      if (pickedFile != null) {
        setState(() => _newPhotoFile = File(pickedFile.path));
      }
    } catch (e) {
      debugPrint("Ошибка выбора фото: $e");
    }
  }

  void _toggleNotifications(bool value) async {
    if (value) {
      final bool granted = await LocalNotificationService().requestPermissions();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Необходимо разрешить уведомления в настройках телефона', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: Theme.of(context).colorScheme.primary
          )
        );
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

      Map<String, dynamic> userUpdates = {'name': _nameController.text.trim(), 'nickname': newNickname, 'gender': _selectedGender, 'photoUrl': photoToSave ?? '', 'goal': _selectedGoal};
      if (age != null) userUpdates['age'] = age;
      if (height != null) userUpdates['height'] = height;
      if (weight != null) userUpdates['weight'] = weight;

      await DatabaseService().updateUserData(userUpdates);

      if (age != null && height != null && weight != null) {
        await CalculationService().recalculateAndSaveGoals(weight: weight, height: height, age: age, goal: _selectedGoal, activityLevel: _selectedActivity, isPregnant: _selectedGoal == 'Здоровая беременность');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Профиль обновлен! ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
          backgroundColor: Theme.of(context).colorScheme.primary
        )
      );
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
    if (!mounted) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Письмо отправлено на почту!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
            backgroundColor: Theme.of(context).colorScheme.primary
          )
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка: $e"), backgroundColor: Theme.of(context).colorScheme.primary)
        );
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
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeWrapper()), (route) => false);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В целях безопасности перезайдите в аккаунт.'), backgroundColor: Color(0xFFB6A6CA))
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Удаление аккаунта', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        content: Text('Все ваши данные будут удалены безвозвратно.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Отмена', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, elevation: 0), 
            onPressed: () { 
              Navigator.pop(ctx); 
              _deleteAccount(); 
            }, 
            child: const Text('Удалить', style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  void _showActivityBottomSheet(ThemeData theme) {
    final activities = ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'];
    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Уровень активности", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              ...activities.map((act) => ListTile(
                title: Text(
                  act, 
                  style: TextStyle(
                    fontWeight: _selectedActivity == act ? FontWeight.bold : FontWeight.normal, 
                    color: _selectedActivity == act ? theme.colorScheme.primary : theme.colorScheme.onSurface
                  )
                ),
                trailing: _selectedActivity == act ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () async {
                  setState(() => _selectedActivity = act);
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  await DatabaseService().updateActivityAndRecalculate(act);
                  if (mounted) setState(() => _isLoading = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Активность обновлена! ✨'), backgroundColor: theme.colorScheme.primary)
                  );
                },
              )),
            ],
          ),
        ),
      )
    );
  }

  void _showGoalBottomSheet(ThemeData theme) {
    final goals = ['Похудеть', 'Поддержание веса', 'Набрать вес', 'Здоровая беременность'];
    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Ваша цель", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              ...goals.map((g) => ListTile(
                title: Text(
                  g, 
                  style: TextStyle(
                    fontWeight: _selectedGoal == g ? FontWeight.bold : FontWeight.normal, 
                    color: _selectedGoal == g ? theme.colorScheme.primary : theme.colorScheme.onSurface
                  )
                ),
                trailing: _selectedGoal == g ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () async {
                  setState(() => _selectedGoal = g);
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({'goal': g});
                  }
                  if (mounted) setState(() => _isLoading = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: const Text('Цель обновлена! ✨'), backgroundColor: theme.colorScheme.primary)
                  );
                },
              )),
            ],
          ),
        ),
      )
    );
  }

  void _showThemeBottomSheet(ThemeMode currentMode, ThemeData theme) {
    final modes = {
      ThemeMode.system: 'Как в системе',
      ThemeMode.light: 'Светлая',
      ThemeMode.dark: 'Темная',
    };

    showModalBottomSheet(
      context: context, 
      backgroundColor: theme.colorScheme.surface, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Тема оформления", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              ...modes.entries.map((entry) => ListTile(
                title: Text(
                  entry.value, 
                  style: TextStyle(
                    fontWeight: currentMode == entry.key ? FontWeight.bold : FontWeight.normal, 
                    color: currentMode == entry.key ? theme.colorScheme.primary : theme.colorScheme.onSurface
                  )
                ),
                trailing: currentMode == entry.key ? Icon(Icons.check, color: theme.colorScheme.primary) : null,
                onTap: () {
                  ThemeService().toggleTheme(entry.key);
                  Navigator.pop(ctx);
                },
              )),
            ],
          ),
        ),
      )
    );
  }

  Widget _buildSettingsCard(List<Widget> children, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(24), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), 
            blurRadius: 24, 
            offset: const Offset(0, 8)
          )
        ]
      ), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: children
      )
    );
  }

  Widget _buildListField(String label, TextEditingController controller, String hint, IconData? icon, ThemeData theme, {int maxLines = 1, List<TextInputFormatter>? inputFormatters, String? errorText}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 20), const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
                TextField(
                  controller: controller, 
                  maxLines: maxLines, 
                  inputFormatters: inputFormatters, 
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500), 
                  cursorColor: theme.colorScheme.primary,
                  decoration: InputDecoration(
                    hintText: hint, 
                    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.normal), 
                    errorText: errorText, 
                    errorStyle: TextStyle(color: theme.colorScheme.primary, fontSize: 12), 
                    border: InputBorder.none, 
                    isDense: true, 
                    contentPadding: const EdgeInsets.only(top: 4, bottom: 4)
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniMetric(String label, TextEditingController controller, String hint, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)),
          TextField(
            controller: controller, 
            keyboardType: TextInputType.number, 
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500), 
            cursorColor: theme.colorScheme.primary, 
            decoration: InputDecoration(
              hintText: hint, 
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)), 
              border: InputBorder.none, 
              isDense: true, 
              contentPadding: const EdgeInsets.only(top: 4, bottom: 4)
            )
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    ImageProvider? imageProvider;
    if (_newPhotoFile != null) {
      imageProvider = FileImage(_newPhotoFile!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      if (_currentPhotoUrl!.startsWith('http')) {
        imageProvider = NetworkImage(_currentPhotoUrl!);
      } else { 
        try { 
          imageProvider = MemoryImage(base64Decode(_currentPhotoUrl!)); 
        } catch (_) {} 
      }
    }

    return BaseBackground(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text("Настройки", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 18)), 
          backgroundColor: Colors.transparent, 
          elevation: 0, 
          iconTheme: IconThemeData(color: theme.colorScheme.onSurface)
        ),
        body: _isFetching
            ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
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
                            child: CircleAvatar(
                              radius: 55, 
                              backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), 
                              backgroundImage: imageProvider, 
                              child: imageProvider == null ? Icon(Icons.person, size: 55, color: theme.colorScheme.onSurfaceVariant) : null
                            )
                          ),
                          Positioned(
                            bottom: 0, right: 0, 
                            child: GestureDetector(
                              onTap: _pickImage, 
                              child: Container(
                                padding: const EdgeInsets.all(8), 
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary, 
                                  shape: BoxShape.circle, 
                                  border: Border.all(color: theme.scaffoldBackgroundColor, width: 3)
                                ), 
                                child: const Icon(Icons.camera_alt, size: 16, color: Colors.white)
                              )
                            )
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ОБЩИЕ ДАННЫЕ", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      _buildListField("Имя / Фамилия", _nameController, "Как к вам обращаться?", Icons.person, theme),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      _buildListField("Никнейм", _nicknameController, "username", Icons.alternate_email, theme, errorText: _nicknameError, inputFormatters: [
                        TextInputFormatter.withFunction((oldValue, newValue) { 
                          if (!RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(newValue.text)) {
                            return oldValue; 
                          }
                          return newValue.copyWith(text: newValue.text.toLowerCase()); 
                        })
                      ]),
                    ], theme),

                    const SizedBox(height: 24),
                    Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРОФИЛЬ", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(child: _buildMiniMetric("Возраст", _ageController, "Лет", theme)), 
                            VerticalDivider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Рост", _heightController, "см", theme)), 
                            VerticalDivider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), width: 1, thickness: 1),
                            Expanded(child: _buildMiniMetric("Вес", _weightController, "кг", theme)),
                          ],
                        ),
                      ),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      ListTile(title: Text("Уровень активности", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text(_selectedActivity, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500)), trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), onTap: () => _showActivityBottomSheet(theme)),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      ListTile(title: Text("Ваша цель", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold)), subtitle: Text(_selectedGoal, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w500)), trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), onTap: () => _showGoalBottomSheet(theme)),
                    ], theme),

                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity, height: 56,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary, 
                        borderRadius: BorderRadius.circular(20), 
                        boxShadow: [
                          BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))
                        ]
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                        child: _isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : const Text("СОХРАНИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("НАСТРОЙКИ ПРИЛОЖЕНИЯ", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      SwitchListTile(
                        activeTrackColor: theme.colorScheme.primary, 
                        title: Text("Заботливые напоминания от Евы", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)), 
                        subtitle: Text("Вода, обед и итоги дня", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)), 
                        value: _notificationsEnabled, 
                        onChanged: _toggleNotifications
                      ),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService().themeModeNotifier,
                        builder: (context, currentMode, _) {
                          String modeText = 'Как в системе';
                          if (currentMode == ThemeMode.light) {
                            modeText = 'Светлая';
                          }
                          if (currentMode == ThemeMode.dark) {
                            modeText = 'Темная';
                          }

                          return ListTile(
                            title: Text("Тема оформления", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)), 
                            subtitle: Text(modeText, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)), 
                            trailing: Icon(Icons.arrow_forward_ios, size: 14, color: theme.colorScheme.onSurfaceVariant), 
                            onTap: () => _showThemeBottomSheet(currentMode, theme)
                          );
                        }
                      ),
                    ], theme),

                    const SizedBox(height: 32),
                    Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text("ПРАВОВАЯ ИНФОРМАЦИЯ", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
                    _buildSettingsCard([
                      ListTile(leading: Icon(Icons.description_outlined, color: theme.colorScheme.onSurfaceVariant, size: 20), title: Text("Пользовательское соглашение", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500)), trailing: Icon(Icons.arrow_forward_ios, color: theme.colorScheme.onSurfaceVariant, size: 14), onTap: () { const String url = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing"; launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication); }),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: Icon(Icons.privacy_tip_outlined, color: theme.colorScheme.onSurfaceVariant, size: 20), title: Text("Политика конфиденциальности", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500)), trailing: Icon(Icons.arrow_forward_ios, color: theme.colorScheme.onSurfaceVariant, size: 14), onTap: () { const String url = "https://docs.google.com/document/d/1ak-7-B2_uvmY1O7b6kJu-rUEOa5e_sDY/edit?usp=sharing"; launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication); }),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: Icon(Icons.support_agent, color: theme.colorScheme.primary, size: 22), title: Text("Написать в поддержку", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)), trailing: Icon(Icons.arrow_forward_ios, color: theme.colorScheme.onSurfaceVariant, size: 14), onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: supportAdminUid, otherUserName: 'Поддержка MyEva'))); }),
                    ], theme),

                    const SizedBox(height: 24),
                    _buildSettingsCard([
                      ListTile(leading: const Icon(Icons.lock_reset, color: Color(0xFFB6A6CA), size: 20), title: Text("Сменить пароль", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _changePassword),
                      Divider(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1),
                      ListTile(leading: Icon(Icons.logout, color: theme.colorScheme.onSurfaceVariant, size: 20), title: Text("Выйти из аккаунта", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14)), onTap: _logout),
                    ], theme),

                    const SizedBox(height: 32),
                    Center(child: TextButton(onPressed: () => _showDeleteAccountDialog(context, theme), child: Text("Удалить аккаунт навсегда", style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600)))),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }
}