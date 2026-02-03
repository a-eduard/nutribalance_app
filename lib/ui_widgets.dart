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
  final Function(String) onChanged;
  final VoidCallback? onPickerTap; 
  final TextInputType keyboardType; // <--- НОВОЕ ПОЛЕ
  final bool obscureText;           // <--- НОВОЕ ПОЛЕ (для пароля)
  final TextAlign textAlign;        // <--- НОВОЕ ПОЛЕ (для выравнивания)

  const HeavyInput({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.onPickerTap,
    this.keyboardType = TextInputType.number, // По умолчанию - цифры (для тренировок)
    this.obscureText = false,                 // По умолчанию - текст виден
    this.textAlign = TextAlign.center,        // По умолчанию - по центру
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        keyboardType: keyboardType, // <--- ИСПОЛЬЗУЕМ ПЕРЕДАННЫЙ ТИП
        obscureText: obscureText,   // <--- СКРЫВАЕМ ТЕКСТ ЕСЛИ НАДО
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        textAlign: textAlign,       // <--- ИСПОЛЬЗУЕМ ВЫРАВНИВАНИЕ
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: onPickerTap != null 
            ? GestureDetector(
                onTap: onPickerTap,
                child: Icon(Icons.unfold_more, color: Colors.white.withOpacity(0.3), size: 20),
              )
            : null,
        ),
      ),
    );
  }
}