import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Предполагаем, что здесь лежит ваш метод signInWithGoogle
import 'services/auth_service.dart'; 

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

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  String _selectedRole = 'user'; // По умолчанию 'user'

  // --- ЛОГИКА EMAIL/PASSWORD ---
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && name.isEmpty)) {
      _showError("Пожалуйста, заполните все поля");
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
          // Записываем две роли: основную и текущую активную
          await _db.collection('users').doc(cred.user!.uid).set({
            'name': name,
            'email': email,
            'registeredRole': _selectedRole,
            'activeRole': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Произошла ошибка");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- ЛОГИКА GOOGLE SIGN IN ---
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final userCredential = await AuthService().signInWithGoogle();

      if (userCredential?.user != null) {
        final uid = userCredential!.user!.uid;
        final userDoc = await _db.collection('users').doc(uid).get();
        
        if (!userDoc.exists) {
          // Если первый вход через Google - создаем профиль
          await _db.collection('users').doc(uid).set({
            'name': userCredential.user!.displayName ?? 'Атлет',
            'email': userCredential.user!.email,
            'registeredRole': _selectedRole,
            'activeRole': _selectedRole,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      _showError("Ошибка Google: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent)
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
                // ЛОГОТИП
                const Text(
                  "TONNA GYM",
                  style: TextStyle(
                    color: Color(0xFFCCFF00), 
                    fontSize: 32, 
                    fontWeight: FontWeight.w900, 
                    letterSpacing: 2.0
                  ),
                ),
                const SizedBox(height: 40),

                // ПОЛЯ ВВОДА
                if (!_isLogin) ...[
                  _buildInput(_nameController, "ИМЯ", Icons.person),
                  const SizedBox(height: 16),
                ],
                _buildInput(_emailController, "EMAIL", Icons.email),
                const SizedBox(height: 16),
                _buildInput(_passwordController, "ПАРОЛЬ", Icons.lock, isPassword: true),
                const SizedBox(height: 24),

                // ВЫБОР РОЛИ (ТОЛЬКО ПРИ РЕГИСТРАЦИИ)
                if (!_isLogin) ...[
                  const Text(
                    "ВЫБЕРИТЕ ВАШУ РОЛЬ", 
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildRoleCard('user', 'КЛИЕНТ', Icons.fitness_center)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildRoleCard('coach', 'ТРЕНЕР', Icons.sports)),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],

                // ОСНОВНАЯ КНОПКА
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCCFF00),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          _isLogin ? "ВОЙТИ" : "СОЗДАТЬ АККАУНТ", 
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)
                        ),
                  ),
                ),

                // РАЗДЕЛИТЕЛЬ "ИЛИ"
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey[900])),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text("ИЛИ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(child: Divider(color: Colors.grey[900])),
                    ],
                  ),
                ),

                // КНОПКА GOOGLE
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    side: BorderSide(color: Colors.white.withOpacity(0.1)),
                    backgroundColor: const Color(0xFF1C1C1E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: Image.network(
                    'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                    height: 22,
                  ),
                  label: const Text(
                    "ВОЙТИ ЧЕРЕЗ GOOGLE", 
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                  ),
                ),

                const SizedBox(height: 24),

                // ПЕРЕКЛЮЧАТЕЛЬ РЕЖИМА
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin ? "НОВЫЙ АТЛЕТ? РЕГИСТРАЦИЯ" : "УЖЕ ЕСТЬ АККАУНТ? ВОЙТИ",
                    style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI КОМПОНЕНТЫ ---

  Widget _buildRoleCard(String role, String title, IconData icon) {
    final bool isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFCCFF00).withOpacity(0.1) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFCCFF00) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFFCCFF00) : Colors.grey, size: 28),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: isSelected ? const Color(0xFFCCFF00) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        cursorColor: const Color(0xFFCCFF00),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey, size: 20),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 14, fontWeight: FontWeight.bold),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }
}