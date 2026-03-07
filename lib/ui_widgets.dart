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

class HeavyInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Function(String) onChanged;
  final TextInputType keyboardType; 
  final bool obscureText;           
  final TextAlign textAlign;        

  const HeavyInput({super.key, required this.controller, required this.hint, required this.onChanged, this.keyboardType = TextInputType.number, this.obscureText = false, this.textAlign = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0), // Светло-серый фон поля ввода
        borderRadius: BorderRadius.circular(16)
      ),
      child: TextField(
        controller: controller, onChanged: onChanged, keyboardType: keyboardType, obscureText: obscureText,
        style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.bold, fontSize: 18), // Темный текст
        textAlign: textAlign,
        decoration: InputDecoration(
          hintText: hint, 
          hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.8)), 
          border: InputBorder.none, 
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
        ),
      ),
    );
  }
}