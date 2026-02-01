import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // DB
import 'ui_widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true; // true = Вход, false = Регистрация
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  
  bool _isLoading = false; // Чтобы блокировать кнопку во время загрузки

  // --- ЛОГИКА АВТОРИЗАЦИИ ---
  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Заполните Email и Пароль");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (isLogin) {
        // 1. ВХОД
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        // Переход случится автоматически благодаря StreamBuilder в main.dart
      } else {
        // 2. РЕГИСТРАЦИЯ
        if (name.isEmpty) {
          _showError("Введите ваше Имя");
          setState(() => _isLoading = false);
          return;
        }

        // Создаем юзера в Auth
        UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Сохраняем доп. данные в Firestore (имя)
        if (cred.user != null) {
          await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
            'uid': cred.user!.uid,
            'name': name,
            'email': email,
            'createdAt': DateTime.now().toIso8601String(),
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      // Обработка ошибок Firebase
      String message = "Произошла ошибка";
      if (e.code == 'user-not-found') {
        message = "Пользователь не найден";
      } else if (e.code == 'wrong-password') message = "Неверный пароль";
      else if (e.code == 'email-already-in-use') message = "Email уже занят";
      else if (e.code == 'weak-password') message = "Пароль слишком простой";
      else if (e.code == 'invalid-email') message = "Некорректный Email";
      
      _showError(message);
    } catch (e) {
      _showError("Ошибка: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 1. LOGO
                const Icon(Icons.fitness_center, size: 80, color: Color(0xFFCCFF00)),
                const SizedBox(height: 16),
                const Text(
                  "IRON TRACKER", 
                  style: TextStyle(color: Colors.white, fontFamily: 'Manrope', fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 2),
                ),
                const SizedBox(height: 40),

                // 2. TOGGLE
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    children: [
                      _buildToggleBtn("ВХОД", true),
                      _buildToggleBtn("РЕГИСТРАЦИЯ", false),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 3. INPUT FIELDS
                if (!isLogin) ...[
                  _buildLabel("ИМЯ"),
                  HeavyInput(controller: _nameController, hint: "Алекс", keyboardType: TextInputType.name, textAlign: TextAlign.left),
                  const SizedBox(height: 16),
                ],

                _buildLabel("EMAIL"),
                HeavyInput(controller: _emailController, hint: "example@mail.ru", keyboardType: TextInputType.emailAddress, textAlign: TextAlign.left),
                const SizedBox(height: 16),

                _buildLabel("ПАРОЛЬ"),
                HeavyInput(controller: _passwordController, hint: "••••••", keyboardType: TextInputType.visiblePassword, textAlign: TextAlign.left, obscureText: true),
                
                const SizedBox(height: 32),

                // 4. ACTION BUTTON
                _isLoading 
                  ? const CircularProgressIndicator(color: Color(0xFFCCFF00))
                  : NeonActionButton(
                      text: isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ",
                      onTap: _submitAuth,
                    ),

                const SizedBox(height: 32),

                // 5. SOCIAL (Визуал)
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("ИЛИ", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSocialBtn(Icons.g_mobiledata),
                    const SizedBox(width: 20),
                    _buildSocialBtn(Icons.apple),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBtn(String text, bool isLoginMode) {
    bool isActive = isLogin == isLoginMode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => isLogin = isLoginMode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFCCFF00) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.black : Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ),
    );
  }

  Widget _buildSocialBtn(IconData icon) {
    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}