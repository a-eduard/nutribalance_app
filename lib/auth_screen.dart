import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
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
  static const Color _bgColor = Color(0xFFF9F9F9); // Светлый фон
  static const Color _textColor = Color(0xFF2D2D2D); // Темный текст

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("fill_all_fields".tr());
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
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "error_msg".tr());
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
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'MyEva',
                  style: TextStyle(color: _accentColor, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
                const SizedBox(height: 8),
                const Text('Гармония в каждой калории', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 40),

                if (!_isLogin) ...[
                  _buildInput(_nameController, "Имя", Icons.person),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "Email", Icons.email),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "Пароль", Icons.lock, isPassword: true),

                if (!_isLogin) ...[
                  const SizedBox(height: 24),
                  _buildLegalCheckbox(),
                ],
                
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ", style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16, letterSpacing: 1.0)),
                  ),
                ),

                const SizedBox(height: 20),

                // Возвращенная кнопка Google
                SizedBox(
                  width: double.infinity, height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: Image.network('https://upload.wikimedia.org/wikipedia/commons/archive/c/c1/20230822192910%21Google_%22G%22_logo.svg', width: 24), // Google Logo
                    label: const Text("Войти через Google", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 0,
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? "Нет аккаунта? Зарегистрироваться" : "Уже есть аккаунт? Войти",
                    style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.2))),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: const TextStyle(color: _textColor),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey, size: 20),
          hintText: hint, hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: _acceptedTerms, onChanged: (val) => setState(() => _acceptedTerms = val ?? false), activeColor: _accentColor),
        const Expanded(
          child: Text("Я соглашаюсь с Политикой конфиденциальности", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      ],
    );
  }
}