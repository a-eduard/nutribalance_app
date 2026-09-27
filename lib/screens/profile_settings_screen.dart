import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/calculation_service.dart';
import '../services/database_service.dart';
import '../services/local_notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'p2p_chat_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const String supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';
  static const String _termsUrl = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing";
  static const String _privacyUrl = "https://docs.google.com/document/d/1ak-7-B2_uvmY1O7b6kJu-rUEOa5e_sDY/edit?usp=sharing";

  static const List<String> _activities = ['Низкая (сидячий образ)', 'Умеренная (1-2 тренировки)', 'Высокая (3-5 тренировок)', 'Очень высокая (каждый день)'];
  static const List<String> _goals = ['Похудеть', 'Поддержание веса', 'Набрать вес', 'Здоровая беременность'];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  String _selectedGender = 'не указан';
  String _selectedActivity = 'Умеренная (1-2 тренировки)';
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
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      DocumentSnapshot<Map<String, dynamic>> userDoc;
      try {
        userDoc = await ref.get(const GetOptions(source: Source.cache));
        if (!userDoc.exists) throw Exception('no cache');
      } catch (_) {
        userDoc = await ref.get().timeout(const Duration(seconds: 10));
      }
      final userData = userDoc.data();
      if (userData != null && mounted) {
        setState(() {
          _nameController.text = (userData['name'] ?? '').toString();
          _notificationsEnabled = userData['notificationsEnabled'] == true;
          _nicknameController.text = (userData['nickname'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
          _currentPhotoUrl = userData['photoUrl']?.toString();
          _selectedGender = (userData['gender'] ?? 'не указан').toString();
          _ageController.text = userData['age'] != null ? '${evaInt(userData['age'])}' : '';
          _heightController.text = userData['height']?.toString() ?? '';
          _weightController.text = userData['weight']?.toString() ?? '';
          final String goal = (userData['goal'] ?? userData['goals'] ?? 'Похудеть').toString();
          _selectedGoal = _goals.contains(goal) ? goal : (goal == 'Поддержать вес' ? 'Поддержание веса' : goal == 'Набрать массу' ? 'Набрать вес' : 'Похудеть');
          final String act = (userData['activityLevel'] ?? 'Умеренная (1-2 тренировки)').toString();
          _selectedActivity = _activities.contains(act) ? act : 'Умеренная (1-2 тренировки)';
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
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 800, maxHeight: 800);
      if (pickedFile != null) setState(() => _newPhotoFile = File(pickedFile.path));
    } catch (e) {
      debugPrint("Ошибка выбора фото: $e");
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final bool granted = await LocalNotificationService().requestPermissions();
      if (!granted) {
        if (!mounted) return;
        EvaSnack.show(context, 'Разрешите уведомления в настройках телефона', type: EvaSnackType.info);
        setState(() => _notificationsEnabled = false);
        return;
      }
    }
    setState(() => _notificationsEnabled = value);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).set({'notificationsEnabled': value}, SetOptions(merge: true)).catchError((e) => debugPrint('$e'));
    }
    try {
      if (value) {
        await LocalNotificationService().scheduleDailyNotifications();
      } else {
        await LocalNotificationService().cancelAll();
      }
    } catch (e) {
      debugPrint('notifications: $e');
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _nicknameError = null;
    });

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    final String newNickname = _nicknameController.text.trim().replaceAll('@', '').toLowerCase();
    if (newNickname.isNotEmpty) {
      if (newNickname.length < 3) {
        setState(() {
          _isLoading = false;
          _nicknameError = 'Минимум 3 символа';
        });
        return;
      }
      final isUnique = await DatabaseService().isNicknameUnique(newNickname);
      if (!isUnique) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _nicknameError = 'Этот никнейм уже занят';
          });
        }
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

      final Map<String, dynamic> updates = {
        'name': _nameController.text.trim(),
        'nickname': newNickname,
        'gender': _selectedGender,
        'photoUrl': photoToSave ?? '',
        'goal': _selectedGoal,
        'activityLevel': _selectedActivity,
      };
      if (age != null) updates['age'] = age;
      if (height != null) updates['height'] = height;
      if (weight != null) updates['weight'] = weight;

      await DatabaseService().updateUserData(updates);
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
      EvaSnack.showOn(messenger, theme, 'Профиль обновлён ✨', type: EvaSnackType.success);
      nav.pop();
    } catch (e) {
      debugPrint("Ошибка сохранения профиля: $e");
      EvaSnack.showOn(messenger, theme, 'Не удалось сохранить профиль', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    try {
      await PushNotificationService().clearToken();
      await LocalNotificationService().cancelAll();
    } catch (_) {}
    await AuthService().signOutEverywhere();
    // Корневой HomeWrapper сам покажет экран входа.
    nav.popUntil((route) => route.isFirst);
  }

  Future<void> _changePassword() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
      if (mounted) EvaSnack.show(context, 'Письмо для смены пароля отправлено на ${user.email}', type: EvaSnackType.success);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Не удалось отправить письмо', type: EvaSnackType.error);
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    try {
      await PushNotificationService().clearToken();
      await user.delete();
      await LocalNotificationService().cancelAll();
      nav.popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      EvaSnack.show(
        context,
        e.code == 'requires-recent-login'
            ? 'В целях безопасности выйдите и войдите снова, затем повторите удаление'
            : 'Не удалось удалить аккаунт: ${e.message ?? e.code}',
        type: EvaSnackType.error,
        duration: const Duration(seconds: 6),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDeleteAccountDialog() {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text('Все данные — дневник, цикл, чаты — будут удалены безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAccount();
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _pickFromList(String title, List<String> options, String current, ValueChanged<String> onPicked) {
    EvaSheet.show<void>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EvaSheetHeader(title: title),
            ...options.map((o) => EvaOptionTile(
                  title: o,
                  selected: o == current,
                  onTap: () {
                    Navigator.pop(ctx);
                    onPicked(o);
                  },
                )),
          ],
        ),
      ),
    );
  }

  ImageProvider? get _avatarProvider {
    if (_newPhotoFile != null) return FileImage(_newPhotoFile!);
    final url = _currentPhotoUrl ?? '';
    if (url.isEmpty) return null;
    if (url.startsWith('http')) return NetworkImage(url);
    try {
      return MemoryImage(base64Decode(url));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final avatar = _avatarProvider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        glow: false,
        child: _isFetching
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(gradient: palette.hero, shape: BoxShape.circle),
                            child: Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 3)),
                              child: CircleAvatar(
                                backgroundColor: palette.fieldFill,
                                backgroundImage: avatar,
                                child: avatar == null ? Icon(Icons.person_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant) : null,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 3)),
                              child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(padding: EdgeInsets.only(left: 8, bottom: 10), child: EvaOverline('Общие данные')),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Имя', prefixIcon: Icon(Icons.person_outline_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      labelText: 'Никнейм (для поиска в чатах)',
                      prefixText: '@',
                      errorText: _nicknameError,
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final lower = newValue.text.toLowerCase();
                        if (!RegExp(r'^[a-z0-9_]*$').hasMatch(lower)) return oldValue;
                        return newValue.copyWith(text: lower);
                      }),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Padding(padding: EdgeInsets.only(left: 8, bottom: 10), child: EvaOverline('Параметры')),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Возраст', suffixText: 'лет'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Рост', suffixText: 'см'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Вес', suffixText: 'кг'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  EvaMenuGroup(
                    children: [
                      EvaMenuTile(
                        icon: Icons.flag_outlined,
                        title: 'Цель',
                        subtitle: _selectedGoal,
                        onTap: () => _pickFromList('Твоя цель', _goals, _selectedGoal, (v) => setState(() => _selectedGoal = v)),
                      ),
                      EvaMenuTile(
                        icon: Icons.directions_run_rounded,
                        title: 'Активность',
                        subtitle: _selectedActivity,
                        onTap: () => _pickFromList('Уровень активности', _activities, _selectedActivity, (v) => setState(() => _selectedActivity = v)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  EvaPrimaryButton(label: 'Сохранить изменения', loading: _isLoading, onPressed: _saveProfile),
                  const SizedBox(height: 28),
                  EvaMenuGroup(
                    title: 'Приложение',
                    children: [
                      EvaMenuTile(
                        icon: Icons.notifications_none_rounded,
                        title: 'Заботливые напоминания',
                        subtitle: 'Вода, обед и итоги дня',
                        trailing: Switch(value: _notificationsEnabled, onChanged: _toggleNotifications),
                        onTap: () => _toggleNotifications(!_notificationsEnabled),
                      ),
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService().themeModeNotifier,
                        builder: (context, mode, _) {
                          const labels = {ThemeMode.system: 'Как в системе', ThemeMode.light: 'Светлая', ThemeMode.dark: 'Тёмная'};
                          return EvaMenuTile(
                            icon: Icons.palette_outlined,
                            title: 'Тема оформления',
                            subtitle: labels[mode],
                            onTap: () => EvaSheet.show<void>(
                              context,
                              builder: (ctx) => Padding(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const EvaSheetHeader(title: 'Тема оформления'),
                                    ...labels.entries.map((e) => EvaOptionTile(
                                          title: e.value,
                                          selected: e.key == mode,
                                          onTap: () {
                                            ThemeService().toggleTheme(e.key);
                                            Navigator.pop(ctx);
                                          },
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  EvaMenuGroup(
                    title: 'Помощь и документы',
                    children: [
                      EvaMenuTile(
                        icon: Icons.support_agent_rounded,
                        title: 'Написать в поддержку',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: supportAdminUid, otherUserName: 'Поддержка «Моя Ева»')),
                        ),
                      ),
                      EvaMenuTile(
                        icon: Icons.description_outlined,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        title: 'Пользовательское соглашение',
                        onTap: () => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication),
                      ),
                      EvaMenuTile(
                        icon: Icons.privacy_tip_outlined,
                        iconColor: theme.colorScheme.onSurfaceVariant,
                        title: 'Политика конфиденциальности',
                        onTap: () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  EvaMenuGroup(
                    title: 'Аккаунт',
                    children: [
                      EvaMenuTile(icon: Icons.lock_reset_rounded, iconColor: palette.lavender, title: 'Сменить пароль', onTap: _changePassword),
                      EvaMenuTile(icon: Icons.logout_rounded, iconColor: theme.colorScheme.onSurfaceVariant, title: 'Выйти из аккаунта', onTap: _isLoading ? null : _logout),
                      EvaMenuTile(icon: Icons.delete_outline_rounded, title: 'Удалить аккаунт', destructive: true, onTap: _showDeleteAccountDialog),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(child: Text('Моя Ева · сделано с заботой', style: theme.textTheme.bodySmall)),
                ],
              ),
      ),
    );
  }
}
