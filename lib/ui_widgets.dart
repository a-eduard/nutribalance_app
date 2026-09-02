import 'package:flutter/material.dart';

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
        color: Colors.white, // Чистый белый фон для светлой темы
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), // Мягкая, еле заметная тень
            blurRadius: 20, 
            offset: const Offset(0, 10)
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(padding: padding ?? const EdgeInsets.all(20.0), child: child),
        ),
      ),
    );
  }
}

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
          colors: [Color(0xFFB76E79), Color(0xFFD49A89)], // Rose Gold
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFFB76E79).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, 
          shadowColor: Colors.transparent, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
        ),
        child: Text(text.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0)),
      ),
    );
  }
}

// В файле: lib/ui_widgets.dart

class HeavyInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Function(String) onChanged;
  final TextInputType keyboardType; 
  final bool obscureText;           
  final TextAlign textAlign;        

  const HeavyInput({
    super.key, 
    required this.controller, 
    required this.hint, 
    required this.onChanged, 
    this.keyboardType = TextInputType.number, 
    this.obscureText = false, 
    this.textAlign = TextAlign.center
  });

  @override
  Widget build(BuildContext context) {
    // Получаем текущую тему (Светлая или Темная)
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        // Используем адаптивный цвет поверхности вместо жесткого Color(0xFFF0F0F0)
        color: theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(16),
        // Добавляем легкую границу, чтобы поле выделялось на фоне Scaffold
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller, 
        onChanged: onChanged, 
        keyboardType: keyboardType, 
        obscureText: obscureText,
        // Адаптивный цвет текста (белый в темной теме, черный в светлой)
        style: TextStyle(
          color: theme.colorScheme.onSurface, 
          fontWeight: FontWeight.bold, 
          fontSize: 18
        ), 
        textAlign: textAlign,
        cursorColor: theme.colorScheme.primary, // Цвет курсора в цвет бренда
        decoration: InputDecoration(
          hintText: hint, 
          // Адаптивный цвет плейсхолдера
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
          ), 
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        ),
      ),
    );
  }
}