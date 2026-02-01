import 'package:flutter/material.dart';

// 1. ПРЕМИАЛЬНАЯ КАРТОЧКА
class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  
  const GlassCard({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), // Глубокий серый
        borderRadius: BorderRadius.circular(24), // Сильное скругление
        border: Border.all(color: Colors.white.withOpacity(0.08)), // Тонкая рамка
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 10), // Глубокая тень
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          splashColor: const Color(0xFFCCFF00).withOpacity(0.1),
          highlightColor: const Color(0xFFCCFF00).withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: child,
          ),
        ),
      ),
    );
  }
}

// 2. НЕОНОВАЯ КНОПКА
class NeonButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final IconData? icon; // Добавил опциональную иконку для гибкости

  const NeonButton({super.key, required this.text, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCCFF00), Color(0xFFB2E600)], // Лаймовый градиент
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCCFF00).withOpacity(0.4), // Свечение
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.black), const SizedBox(width: 8)],
            Text(
              text.toUpperCase(),
              style: const TextStyle(
                color: Colors.black, // Черный текст на лаймовом
                fontWeight: FontWeight.w800,
                fontSize: 16,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 3. ПОЛЕ ВВОДА
class ModernInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Function(String)? onChanged;

  const ModernInput({super.key, required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212), // Очень темный фон внутри
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 20, 
          fontWeight: FontWeight.bold,
          // fontFamily: 'Manrope', // Убрал, чтобы не крашилось если шрифт не подключен
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}