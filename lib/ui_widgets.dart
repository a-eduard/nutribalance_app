import 'package:flutter/material.dart';

// 1. ПРЕМИАЛЬНАЯ КАРТОЧКА
class PremiumGlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const PremiumGlassCard({super.key, required this.child, this.onTap, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        // Глубокий серый цвет с легкой прозрачностью
        color: const Color(0xFF1C1C1E).withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.8),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          highlightColor: const Color(0xFFCCFF00).withOpacity(0.05),
          splashColor: const Color(0xFFCCFF00).withOpacity(0.1),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20.0),
            child: child,
          ),
        ),
      ),
    );
  }
}

// 2. НЕОНОВАЯ КНОПКА
class NeonActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool isFullWidth;

  const NeonActionButton({super.key, required this.text, required this.onTap, this.isFullWidth = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFCCFF00), Color(0xFFAACC00)], // Лаймовый градиент
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCCFF00).withOpacity(0.3), // Свечение
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.black, // Черный текст для контраста
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.0,
            // fontFamily: 'Manrope', // Убрал, чтобы не крашилось без шрифта
          ),
        ),
      ),
    );
  }
}

// 3. ПОЛЕ ВВОДА (Универсальное)
class HeavyInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Function(String)? onChanged;
  final TextInputType? keyboardType;
  final TextAlign? textAlign;
  final bool obscureText;

  const HeavyInput({
    super.key, 
    required this.controller, 
    required this.hint, 
    this.onChanged,
    this.keyboardType,
    this.textAlign,
    this.obscureText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E), // Чуть светлее фона
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          obscureText: obscureText,
          // Если тип не передан, используем цифры
          keyboardType: keyboardType ?? TextInputType.number, 
          // Если выравнивание не передано, по центру
          textAlign: textAlign ?? TextAlign.center,
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 16, 
            fontWeight: FontWeight.w700,
            // fontFamily: 'Manrope',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
            border: InputBorder.none,
            // Сдвигаем контент, чтобы курсор был ровно
            contentPadding: const EdgeInsets.symmetric(horizontal: 16), 
          ),
        ),
      ),
    );
  }
}