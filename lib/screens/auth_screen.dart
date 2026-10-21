import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import '../services/analytics_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _isLogin = true;
  bool _isLoading = false;
  bool _acceptedTerms = false;
  bool _obscure = true;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  static const String _termsUrl = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing";
  static const String _privacyUrl = "https://docs.google.com/document/d/1ak-7-B2_uvmY1O7b6kJu-rUEOa5e_sDY/edit?usp=sharing";

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Понятные сообщения вместо англоязычных ошибок Firebase.
  String _authErrorText(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Проверьте email — кажется, в нём опечатка';
      case 'user-disabled':
        return 'Этот аккаунт заблокирован';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Неверный email или пароль';
      case 'email-already-in-use':
        return 'Аккаунт с таким email уже есть — попробуйте войти';
      case 'weak-password':
        return 'Пароль слишком простой — минимум 6 символов';
      case 'too-many-requests':
        return 'Слишком много попыток. Подождите пару минут';
      case 'network-request-failed':
        return 'Нет соединения с сервером. Проверьте интернет или VPN';
      default:
        return e.message ?? 'Ошибка авторизации';
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final TextEditingController resetEmailController = TextEditingController(text: _emailController.text.trim());
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Восстановление пароля'),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ваш email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                EvaSnack.showOn(messenger, theme, 'Письмо для сброса пароля отправлено 💌', type: EvaSnackType.success);
              } on FirebaseAuthException catch (e) {
                EvaSnack.showOn(messenger, theme, _authErrorText(e), type: EvaSnackType.error);
              } catch (e) {
                EvaSnack.showOn(messenger, theme, 'Не удалось отправить письмо', type: EvaSnackType.error);
              }
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      EvaSnack.show(context, 'Заполните все поля', type: EvaSnackType.error);
      return;
    }
    if (!_isLogin && !_acceptedTerms) {
      EvaSnack.show(context, 'Примите Пользовательское соглашение и Политику конфиденциальности', type: EvaSnackType.error);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
        Analytics.login('email');
      } else {
        final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
        Analytics.signUp('email');
        if (cred.user != null) {
          // Не ждём сервер: профиль создастся локально сразу и досинхронизируется.
          _db.collection('users').doc(cred.user!.uid).set({
            'name': name,
            'email': email,
            'activeRole': 'user',
            'createdAt': FieldValue.serverTimestamp(),
            'isPro': false,
            'isOnboardingCompleted': false,
          }, SetOptions(merge: true)).catchError((e) => debugPrint('create user doc: $e'));
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) EvaSnack.show(context, _authErrorText(e), type: EvaSnackType.error);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Что-то пошло не так. Попробуйте ещё раз', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_isLogin && !_acceptedTerms) {
      EvaSnack.show(context, 'Примите условия соглашения', type: EvaSnackType.error);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await AuthService().signInWithGoogle();
      if (result is UserCredential && result.user != null) {
        final uid = result.user!.uid;
        if (result.additionalUserInfo?.isNewUser == true) {
          Analytics.signUp('google');
        } else {
          Analytics.login('google');
        }
        DocumentSnapshot<Map<String, dynamic>>? userDoc;
        try {
          userDoc = await _db.collection('users').doc(uid).get().timeout(const Duration(seconds: 10));
        } catch (_) {}
        final data = userDoc?.data();
        final bool hasOnboardingData = data != null && data.containsKey('weight') && data.containsKey('height');

        _db.collection('users').doc(uid).set(
              hasOnboardingData
                  ? {'isOnboardingCompleted': true}
                  : {
                      'email': result.user!.email,
                      'name': result.user!.displayName ?? 'Пользователь',
                      'activeRole': 'user',
                      'createdAt': FieldValue.serverTimestamp(),
                      'isPro': false,
                      'isOnboardingCompleted': false,
                    },
              SetOptions(merge: true),
            ).catchError((e) => debugPrint('google user doc: $e'));
      } else if (result is String && mounted) {
        EvaSnack.show(context, result, type: EvaSnackType.error);
      }
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Произошла ошибка авторизации', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;

    return Scaffold(
      body: EvaBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: ThemeService().themeModeNotifier,
                        builder: (context, mode, _) {
                          final bool isDark = mode == ThemeMode.dark || (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
                          return EvaCircleButton(
                            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            size: 40,
                            tooltip: isDark ? 'Светлая тема' : 'Тёмная тема',
                            onTap: () => ThemeService().toggleTheme(isDark ? ThemeMode.light : ThemeMode.dark),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(gradient: palette.hero, shape: BoxShape.circle, boxShadow: palette.floatingShadow),
                        child: const Icon(Icons.spa_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Моя Ева', textAlign: TextAlign.center, style: theme.textTheme.displayMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Гармония в каждой калории',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: EvaFonts.serif, fontStyle: FontStyle.italic, fontSize: 18, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: 32),
                    _ModeSwitch(
                      isLogin: _isLogin,
                      onChanged: (v) => setState(() => _isLogin = v),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: _isLogin
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(hintText: 'Имя', prefixIcon: Icon(Icons.person_outline_rounded)),
                              ),
                            ),
                    ),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(hintText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        hintText: 'Пароль',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (_isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: _showForgotPasswordDialog, child: const Text('Забыли пароль?')),
                      )
                    else ...[
                      const SizedBox(height: 16),
                      _buildLegalCheckbox(theme),
                    ],
                    const SizedBox(height: 20),
                    EvaPrimaryButton(
                      label: _isLogin ? 'Войти' : 'Создать аккаунт',
                      loading: _isLoading,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('или', style: theme.textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    EvaSecondaryButton(
                      label: 'Продолжить с Google',
                      leading: const FaIcon(FontAwesomeIcons.google, size: 18, color: Color(0xFFDB4437)),
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(value: _acceptedTerms, onChanged: (val) => setState(() => _acceptedTerms = val ?? false)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              children: [
                const TextSpan(text: 'Я соглашаюсь с '),
                TextSpan(
                  text: 'Пользовательским соглашением',
                  style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(_termsUrl), mode: LaunchMode.externalApplication),
                ),
                const TextSpan(text: ' и '),
                TextSpan(
                  text: 'Политикой конфиденциальности',
                  style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(_privacyUrl), mode: LaunchMode.externalApplication),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    Widget seg(String label, bool value) {
      final bool active = isLogin == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
              boxShadow: active ? palette.cardShadow : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: active ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: palette.fieldFill, borderRadius: BorderRadius.circular(100)),
      child: Row(children: [seg('Вход', true), seg('Регистрация', false)]),
    );
  }
}
