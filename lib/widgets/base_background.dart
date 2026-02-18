import 'package:flutter/material.dart';

class BaseBackground extends StatelessWidget {
  final Widget child;
  
  const BaseBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity, // Жестко растягиваем на весь экран
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E), // Резервный цвет фона
        image: DecorationImage(
          image: AssetImage('assets/images/app_bg_silhouette.png'),
          fit: BoxFit.cover, // Обрезает края, чтобы заполнить всё пространство
          alignment: Alignment.center,
        ),
      ),
      // UI FIX: Убрали SafeArea. Теперь контент (фон) заходит под статус-бар и home-индикатор.
      // SafeArea нужно использовать внутри экранов (Scaffold body), если нужно отступить.
      child: child, 
    );
  }
}