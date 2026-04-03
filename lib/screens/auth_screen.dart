import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; 
import 'package:url_launcher/url_launcher.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';


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

  static const Color _accentColor = Color(0xFFB76E79); 
  static const Color _bgColor = Color(0xFFFCF9F9); 
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  Future<void> _showForgotPasswordDialog() async {
    final TextEditingController resetEmailController = TextEditingController(text: _emailController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Восстановление пароля", style: TextStyle(color: _textColor, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: resetEmailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: _textColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: "Введите ваш Email",
            hintStyle: TextStyle(color: _subTextColor.withValues(alpha: 0.5), fontWeight: FontWeight.normal),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
          ),
          cursorColor: _accentColor,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена", style: TextStyle(color: _subTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isNotEmpty) {
                Navigator.pop(ctx);
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Письмо с инструкцией отправлено на ваш Email 💌", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                        backgroundColor: Colors.teal
                      )
                    );
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: ${e.toString()}"), backgroundColor: Colors.redAccent));
                }
              }
            },
            child: const Text("Отправить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("Заполните все поля");
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
            'isOnboardingCompleted': false, // <--- МЕТКА НОВИЧКА
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Ошибка авторизации");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_isLogin && !_acceptedTerms) {
      _showError("Примите условия соглашения");
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await AuthService().signInWithGoogle();
      if (result is UserCredential && result.user != null) {
        final uid = result.user!.uid;
        final userDoc = await _db.collection('users').doc(uid).get();
        if (!userDoc.exists) {
          await _db.collection('users').doc(uid).set({
            'name': result.user!.displayName ?? 'Пользователь',
            'email': result.user!.email,
            'activeRole': 'user',
            'createdAt': FieldValue.serverTimestamp(),
            'isPro': false,
            'isOnboardingCompleted': false, // <--- МЕТКА НОВИЧКА
          });
        }
      } else if (result is String) {
        _showError(result);
      }
    } catch (e) {
      _showError("Произошла ошибка авторизации");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'MyEva',
                  style: TextStyle(color: _accentColor, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Гармония в каждой калории', 
                  style: TextStyle(color: _subTextColor, fontSize: 16, fontWeight: FontWeight.w500)
                ),
                const SizedBox(height: 56),

                if (!_isLogin) ...[
                  _buildInput(_nameController, "Имя", Icons.person_outline),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "Email", Icons.email_outlined),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "Пароль", Icons.lock_outline, isPassword: true),

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
                      child: const Text("Забыли пароль?", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),

                if (!_isLogin) ...[
                  const SizedBox(height: 24),
                  _buildLegalCheckbox(),
                ],
                
                const SizedBox(height: 48),

                Container(
                  width: double.infinity, 
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_accentColor, Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))
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
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ", 
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16, letterSpacing: 1.2)
                        ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: const Color(0xFFE5E5EA)),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: _isLoading ? null : _handleGoogleSignIn,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ФИКС: Разбитая строка и защита от ошибок загрузки
                        Image.network(
                          'https://' 'cdn-icons-png.flaticon.com/512/2991/2991148.png', 
                          width: 24,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, color: Colors.blue, size: 32),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          "Войти через Google", 
                          style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w600, fontSize: 16)
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
                    style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 4))
        ],
      ),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: const TextStyle(color: _textColor, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _accentColor.withValues(alpha: 0.7), size: 22),
          hintText: hint, 
          hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontWeight: FontWeight.w400),
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  // === ИСПРАВЛЕННЫЕ ССЫЛКИ С ЗАЩИТОЙ ОТ ПРОБЕЛОВ ===
  Widget _buildLegalCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _acceptedTerms, 
            onChanged: (val) => setState(() => _acceptedTerms = val ?? false), 
            activeColor: _accentColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: _subTextColor, fontSize: 13, fontWeight: FontWeight.w500, height: 1.5),
                children: [
                  const TextSpan(text: "Я соглашаюсь с "),
                  TextSpan(
                    text: "Пользовательским соглашением",
                    style: const TextStyle(color: _accentColor, decoration: TextDecoration.underline),
                    recognizer: TapGestureRecognizer()..onTap = () {
                      const String url = "https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing";
                      launchUrl(Uri.parse(url.trim()), mode: LaunchMode.externalApplication);
                    }
                  ),
                  const TextSpan(text: " и "),
                  TextSpan(
                    text: "Политикой конфиденциальности",
                    style: const TextStyle(color: _accentColor, decoration: TextDecoration.underline),
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