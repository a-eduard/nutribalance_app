import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../paywall_screen.dart';
import 'home_wrapper.dart';

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
  static const Color _bgColor = Color(0xFFF9F9F9); 
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("fill_all_fields".tr());
      return;
    }

    if (!_isLogin && !_acceptedTerms) {
      _showError("Примите условия соглашения");
      return;
    }

    setState(() => _isLoading = true);

    try {
      UserCredential cred;
      if (_isLogin) {
        cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      } else {
        cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
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
      
      if (cred.user != null && mounted) {
        final userDoc = await _db.collection('users').doc(cred.user!.uid).get();
        final isPro = userDoc.data()?['isPro'] ?? false;
        
        if (!isPro) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeWrapper())); 
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
        
        if (mounted) {
           final updatedDoc = await _db.collection('users').doc(uid).get();
           final isPro = updatedDoc.data()?['isPro'] ?? false;
           
           if (!isPro) {
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
           } else {
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeWrapper())); 
           }
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
                  'NutriBalance',
                  style: TextStyle(color: _accentColor, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                const Text('Гармония в каждой калории', style: TextStyle(color: _subTextColor, fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 48),

                if (!_isLogin) ...[
                  _buildInput(_nameController, "Имя", Icons.person_outline),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "Email", Icons.email_outlined),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "Пароль", Icons.lock_outline, isPassword: true),

                if (!_isLogin) ...[
                  const SizedBox(height: 24),
                  _buildLegalCheckbox(),
                ],
                
                const SizedBox(height: 40),

                Container(
                  width: double.infinity, 
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_accentColor, Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ", style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 16, letterSpacing: 1.0)),
                  ),
                ),

                const SizedBox(height: 20),

                // ИСПРАВЛЕНО: Ссылка заменена на PNG-версию логотипа
                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: Image.network(
                      'https://cdn-icons-png.flaticon.com/512/2991/2991148.png', // Надежный и качественный PNG
                       width: 22,
                    ),
                    label: const Text("Войти через Google", style: TextStyle(color: _textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: Colors.transparent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: const TextStyle(color: _textColor, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: const Color(0xFFC7C7CC), size: 22),
          hintText: hint, 
          hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontWeight: FontWeight.w400),
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: _acceptedTerms, 
          onChanged: (val) => setState(() => _acceptedTerms = val ?? false), 
          activeColor: _accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        const Expanded(
          child: Text("Я соглашаюсь с Политикой конфиденциальности", style: TextStyle(color: _subTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}