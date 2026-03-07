import 'package:flutter/material.dart';

class BaseBackground extends StatelessWidget {
  final Widget child;
  
  const BaseBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity, 
      decoration: const BoxDecoration(
        color: Color(0xFFF9F9F9), // Базовый нежный цвет приложения
        // Темную картинку убрали, чтобы она не портила светлую тему
      ),
      child: child, 
    );
  }
}