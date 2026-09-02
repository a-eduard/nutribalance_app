// Файл: lib/theme/app_theme.dart

import 'package:flutter/material.dart';

class AppTheme {
  static const Color accentColor = Color(0xFFB76E79);

  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF9F9F9),
    primaryColor: accentColor,
    colorScheme: const ColorScheme.light(
      primary: accentColor,
      secondary: Color(0xFFD49A89),
      surface: Colors.white,
      onSurface: Color(0xFF2D2D2D), // Основной текст
      onSurfaceVariant: Color(0xFF8E8E93), // Вторичный текст
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: const Color(0xFF2D2D2D),
      displayColor: const Color(0xFF2D2D2D),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF9F9F9),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF2D2D2D)),
      titleTextStyle: TextStyle(color: Color(0xFF2D2D2D), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      selectedItemColor: accentColor,
      unselectedItemColor: Color(0xFF8E8E93),
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      type: BottomNavigationBarType.fixed,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    primaryColor: accentColor,
    colorScheme: const ColorScheme.dark(
      primary: accentColor,
      secondary: Color(0xFFD49A89),
      surface: Color(0xFF1E1E1E), // Карточки
      onSurface: Color(0xFFE0E0E0), // Основной текст
      onSurfaceVariant: Color(0xFFA0A0A0), // Вторичный текст
    ),
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: const Color(0xFFE0E0E0),
      displayColor: const Color(0xFFE0E0E0),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF121212),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFFE0E0E0)),
      titleTextStyle: TextStyle(color: Color(0xFFE0E0E0), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      elevation: 0,
      selectedItemColor: accentColor,
      unselectedItemColor: Color(0xFFA0A0A0),
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
      type: BottomNavigationBarType.fixed,
    ),
  );
}