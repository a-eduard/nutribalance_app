import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Auth
import 'package:cloud_firestore/cloud_firestore.dart'; // DB
import 'ui_widgets.dart';
import 'services/auth_service.dart'; // <--- ПОДКЛЮЧИЛИ СЕРВИС

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
  
  bool _isLoading = false; 

  // --- ОБЫЧНЫЙ ВХОД (Email/Pass) ---
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
        // ВХОД
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // РЕГИСТРАЦИЯ
        if (name.isEmpty) {
          _showError("Введите ваше Имя");
          setState(() => _isLoading = false);
          return;
        }

        UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

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

  // --- ВХОД ЧЕРЕЗ GOOGLE ---
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await AuthService().signInWithGoogle();
      // Навигация произойдет автоматически через StreamBuilder в main.dart
    } catch (e) {
      _showError("Ошибка входа через Google: $e");
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
                  "TONNA", // Новое название
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 2),
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
                  HeavyInput(
                    controller: _nameController, 
                    hint: "Алекс", 
                    keyboardType: TextInputType.name, 
                    textAlign: TextAlign.left,
                    onChanged: (val) {}, // <--- ДОБАВИЛИ ЗАГЛУШКУ
                  ),
                  const SizedBox(height: 16),
                ],

                _buildLabel("EMAIL"),
                HeavyInput(
                  controller: _emailController, 
                  hint: "example@mail.ru", 
                  keyboardType: TextInputType.emailAddress, 
                  textAlign: TextAlign.left,
                  onChanged: (val) {}, // <--- ДОБАВИЛИ ЗАГЛУШКУ
                ),
                const SizedBox(height: 16),

                _buildLabel("ПАРОЛЬ"),
                HeavyInput(
                  controller: _passwordController, 
                  hint: "••••••", 
                  keyboardType: TextInputType.visiblePassword, 
                  textAlign: TextAlign.left, 
                  obscureText: true,
                  onChanged: (val) {}, // <--- ДОБАВИЛИ ЗАГЛУШКУ
                ),

                // 4. ACTION BUTTON
                _isLoading 
                  ? const CircularProgressIndicator(color: Color(0xFFCCFF00))
                  : NeonActionButton(
                      text: isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ",
                      onTap: _submitAuth,
                    ),

                const SizedBox(height: 32),

                // 5. SOCIAL (Только Google)
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text("ИЛИ ЧЕРЕЗ", style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Кнопка Google
                GestureDetector(
                  onTap: _isLoading ? null : _handleGoogleSignIn,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Image.network(
                      'https://cdn-icons-png.flaticon.com/512/2991/2991148.png', // Google Logo
                      width: 30, 
                      height: 30,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, color: Colors.white, size: 30),
                    ),
                  ),
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
}