import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart'; // <-- ИМПОРТ THEME SERVICE

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

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  Future<void> _showForgotPasswordDialog() async {
    final theme = Theme.of(context);
    final TextEditingController resetEmailController = TextEditingController(text: _emailController.text);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Восстановление пароля", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: "Введите ваш Email",
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.normal),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary)),
          ),
          cursorColor: theme.colorScheme.primary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Отмена", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isNotEmpty) {
                final msg = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                  if (!mounted) return;
                  msg.showSnackBar(
                    const SnackBar(
                      content: Text("Письмо с инструкцией отправлено на ваш Email 💌", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                      backgroundColor: Colors.teal
                    )
                  );
                } catch (e) {
                  if (!mounted) return;
                  msg.showSnackBar(SnackBar(content: Text("Ошибка: ${e.toString()}"), backgroundColor: Colors.redAccent));
                }
              }
            },
            child: Text("Отправить", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final msg = ScaffoldMessenger.of(context);

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("Заполните все поля", msg);
      return;
    }

    if (!_isLogin && !_acceptedTerms) { 
      msg.showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, примите Политику конфиденциальности и Пользовательское соглашение.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return; 
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      } else {
        UserCredential cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
        if (cred.user != null) {
          await _db.collection('users').doc(cred.user!.uid).set({
            'name': name,
            'email': email,
            'activeRole': 'user',
            'createdAt': FieldValue.serverTimestamp(),
            'isPro': false, 
            'isOnboardingCompleted': false, 
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Ошибка авторизации", msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final msg = ScaffoldMessenger.of(context);
    
    if (!_isLogin && !_acceptedTerms) {
      _showError("Примите условия соглашения", msg);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await AuthService().signInWithGoogle();
          if (result is UserCredential && result.user != null) {
            final uid = result.user!.uid;
            
            final userDoc = await _db.collection('users').doc(uid).get();
            
            final hasOnboardingData = userDoc.exists &&
                userDoc.data() != null &&
                userDoc.data()!.containsKey('weight') && 
                userDoc.data()!.containsKey('height');

            if (!hasOnboardingData) {
              await _db.collection('users').doc(uid).set({
                'email': result.user!.email,
                'name': result.user!.displayName ?? 'Пользователь',
                'activeRole': 'user',
                'createdAt': FieldValue.serverTimestamp(),
                'isPro': false,
                'isOnboardingCompleted': false, 
              }, SetOptions(merge: true));
            } else {
              await _db.collection('users').doc(uid).set({
                'isOnboardingCompleted': true,
              }, SetOptions(merge: true));
            }
          } else if (result is String) {
        _showError(result, msg);
      }
    } catch (e) {
      _showError("Произошла ошибка авторизации", msg);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String text, ScaffoldMessengerState messenger) {
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // === КНОПКА СМЕНЫ ТЕМЫ ===
                Align(
                  alignment: Alignment.topRight,
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeService().themeModeNotifier,
                    builder: (context, currentMode, _) {
                      final isDark = currentMode == ThemeMode.dark || 
                                    (currentMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);
                      return IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          ThemeService().toggleTheme(isDark ? ThemeMode.light : ThemeMode.dark);
                        },
                        tooltip: isDark ? 'Включить светлую тему' : 'Включить темную тему',
                      );
                    },
                  ),
                ),
                
                Text(
                  'Моя Ева',
                  style: TextStyle(color: theme.colorScheme.primary, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'Гармония в каждой калории', 
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16, fontWeight: FontWeight.w500)
                ),
                const SizedBox(height: 32), // Чуть уменьшили отступ, чтобы кнопка темы не сдвигала всё сильно вниз

                if (!_isLogin) ...[
                  _buildInput(_nameController, "Имя", Icons.person_outline, theme),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "Email", Icons.email_outlined, theme),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "Пароль", Icons.lock_outline, theme, isPassword: true),

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPasswordDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8), 
                        minimumSize: Size.zero, 
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap
                      ),
                      child: Text("Забыли пароль?", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),

                if (!_isLogin) ...[
                  const SizedBox(height: 24),
                  _buildLegalCheckbox(theme),
                ],
                
                const SizedBox(height: 48),

                Container(
                  width: double.infinity, 
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    ),
                    child: _isLoading 
                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: theme.colorScheme.onPrimary, strokeWidth: 2))
                      : Text(
                          _isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ", 
                          style: TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary, fontSize: 16, letterSpacing: 1.2)
                        ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: _isLoading ? null : _handleGoogleSignIn,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.network(
                          'https://' 'cdn-icons-png.flaticon.com/512/2991/2991148.png', 
                          width: 24,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, color: Colors.blue, size: 32),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "Войти через Google", 
                          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 16)
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  style: TextButton.styleFrom(
                    splashFactory: NoSplash.splashFactory,
                  ),
                  child: Text(
                    _isLogin ? "Нет аккаунта? Зарегистрироваться" : "Уже есть аккаунт? Войти",
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, IconData icon, ThemeData theme, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 4))
        ],
      ),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: theme.colorScheme.primary.withValues(alpha: 0.7), size: 22),
          hintText: hint, 
          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontWeight: FontWeight.w400),
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
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
          child: Checkbox(
            value: _acceptedTerms, 
            onChanged: (val) => setState(() => _acceptedTerms = val ?? false), 
            activeColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: RichText(
              text: TextSpan(
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500, height: 1.5),
                children: [
                  const TextSpan(text: "Я соглашаюсь с "),
                  TextSpan(
                    text: "Пользовательским соглашением",
                    style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {
                      const String url = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing";
                      launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication);
                    }
                  ),
                  const TextSpan(text: " и "),
                  TextSpan(
                    text: "Политикой конфиденциальности",
                    style: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {
                      const String url = "https://docs.google.com/document/d/1ak-7-B2_uvmY1O7b6kJu-rUEOa5e_sDY/edit?usp=sharing";
                      launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication);
                    }
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}