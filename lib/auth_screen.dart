import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

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

  String _selectedRole = 'user'; 

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("fill_all_fields".tr());
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(email)) {
      _showError("Введите корректный email адрес");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
      } else {
        UserCredential cred = await _auth.createUserWithEmailAndPassword(
          email: email, 
          password: password
        );
        
        if (cred.user != null) {
          await _db.collection('users').doc(cred.user!.uid).set({
            'name': name,
            'email': email,
            'registeredRole': _selectedRole,
            'activeRole': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
            // По умолчанию подписка отключена
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
      final userCredential = await AuthService().signInWithGoogle();

      if (userCredential?.user != null) {
        final uid = userCredential!.user!.uid;
        final userDoc = await _db.collection('users').doc(uid).get();
        
        if (!userDoc.exists) {
          await _db.collection('users').doc(uid).set({
            'name': userCredential.user!.displayName ?? 'client_default'.tr(),
            'email': userCredential.user!.email,
            'registeredRole': _selectedRole,
            'activeRole': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
            'isPro': false,
          });
        }
      }
    } catch (e) {
      _showError("${"google_error".tr()} $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent)
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Image.asset(
                  'assets/images/logo_tonna.png', 
                  height: 80, 
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 40),

                if (!_isLogin) ...[
                  _buildInput(_nameController, "name_upper".tr(), Icons.person),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "email_upper".tr(), Icons.email),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "password_upper".tr(), Icons.lock, isPassword: true),
                const SizedBox(height: 24),

                if (!_isLogin) ...[
                  Text(
                    "choose_role".tr(), 
                    style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildRoleCard('user', 'role_client_upper'.tr(), Icons.fitness_center)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildRoleCard('coach', 'role_coach_upper'.tr(), Icons.sports)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  _buildLegalCheckbox(),
                  const SizedBox(height: 24),
                ],

                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    onPressed: (_isLoading || (!_isLogin && !_acceptedTerms)) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCCFF00),
                      disabledBackgroundColor: const Color(0xFFCCFF00).withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(_isLogin ? "login_button_upper".tr() : "create_account_button".tr(), 
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
                  ),
                ),

                _buildDivider(),

                OutlinedButton.icon(
                  onPressed: (_isLoading || (!_isLogin && !_acceptedTerms)) ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    backgroundColor: const Color(0xFF1C1C1E),
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Image.network('https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png', height: 22),
                  label: Text(_isLoading ? "ЗАГРУЗКА..." : "sign_in_google_upper".tr(), 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),

                const SizedBox(height: 24),

                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? "no_account".tr() : "have_account".tr(),
                    style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegalCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _acceptedTerms,
          onChanged: (val) => setState(() => _acceptedTerms = val ?? false),
          activeColor: const Color(0xFFCCFF00),
          checkColor: Colors.black,
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              children: [
                const TextSpan(text: "Я согласен с "),
                _linkSpan("Политикой конфиденциальности", "https://docs.google.com/document/d/1LZXjxv2vJYXOkicb_zsul8NM4VNoBAQhuw7hycOiyBQ/edit?usp=sharing"),
                const TextSpan(text: " и "),
                _linkSpan("Пользовательским соглашением", "https://docs.google.com/document/d/1aZNeAoui_eiEuxMTW3KEJNo9fMktMt-esbsrEmKgi6I/edit?usp=sharing"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _linkSpan(String text, String url) {
    return TextSpan(
      text: text,
      style: const TextStyle(color: Color(0xFFCCFF00), decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[900])),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("ИЛИ", style: TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(child: Divider(color: Colors.grey[900])),
        ],
      ),
    );
  }

  Widget _buildRoleCard(String role, String title, IconData icon) {
    final bool isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFCCFF00).withOpacity(0.1) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFFCCFF00) : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFFCCFF00) : Colors.grey),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: isSelected ? const Color(0xFFCCFF00) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
      child: TextField(
        controller: controller, obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey, size: 20),
          hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}