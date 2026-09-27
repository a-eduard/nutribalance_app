// Файл: lib/theme/eva_colors.dart
//
// Палитра «Soft Luxury» для Моя Ева.
// Все цвета приложения собраны здесь, чтобы экраны не хардкодили оттенки.

import 'package:flutter/material.dart';

/// Семейства шрифтов (бандлятся в assets/fonts, работают без интернета и VPN).
class EvaFonts {
  EvaFonts._();
  static const String sans = 'Inter';
  static const String serif = 'NotoSerifDisplay';
}

/// Базовые цвета бренда.
class EvaColors {
  EvaColors._();

  // --- Светлая тема ---
  static const Color ivory = Color(0xFFFAF6F1); // фон
  static const Color pearl = Color(0xFFFFFFFF); // карточки
  static const Color sand = Color(0xFFF5EEE7); // заливки полей
  static const Color linen = Color(0xFFEFE6DE); // приподнятые заливки
  static const Color hairlineLight = Color(0xFFECE2DA);

  static const Color rose = Color(0xFFB76E79); // бренд
  static const Color roseDeep = Color(0xFF9E5663);
  static const Color blush = Color(0xFFF7E4E5);
  static const Color champagne = Color(0xFFC6A27C);
  static const Color champagneLight = Color(0xFFF3E8DB);
  static const Color lavender = Color(0xFF9A87B5);
  static const Color lavenderLight = Color(0xFFEDE7F5);
  static const Color sage = Color(0xFF7FB095);

  static const Color ink = Color(0xFF2A2226); // основной текст
  static const Color mauveGrey = Color(0xFF857A7E); // вторичный текст

  // --- Тёмная тема ---
  static const Color night = Color(0xFF121012);
  static const Color nightSurface = Color(0xFF1C181B);
  static const Color nightLow = Color(0xFF181517);
  static const Color nightHigh = Color(0xFF262024);
  static const Color hairlineDark = Color(0xFF2F282C);
  static const Color roseNight = Color(0xFFC47A86);
  static const Color moon = Color(0xFFF4ECEE);
  static const Color moonGrey = Color(0xFFB3A6AB);

  // --- Функциональные ---
  static const Color error = Color(0xFFC0474F);
  static const Color success = Color(0xFF5E9C83);
  static const Color warning = Color(0xFFD99A4E);

  // --- Макронутриенты (единые во всём приложении) ---
  static const Color protein = Color(0xFFD98A92);
  static const Color fat = Color(0xFFD6AE67);
  static const Color carbs = Color(0xFF86A9D6);
  static const Color fiber = Color(0xFF86BC9C);
  static const Color water = Color(0xFF7DB8E8);

  // --- Фазы цикла ---
  static const Color menstruation = Color(0xFFD06A77);
  static const Color follicular = Color(0xFF7FB095);
  static const Color ovulation = Color(0xFF9A87B5);
  static const Color luteal = Color(0xFFD6AE67);
  static const Color pregnancy = Color(0xFFC98FA6);
}

/// Расширение темы с «премиальными» токенами, которых нет в ColorScheme.
@immutable
class EvaPalette extends ThemeExtension<EvaPalette> {
  final Color gold;
  final Color goldSoft;
  final Color blush;
  final Color lavender;
  final Color lavenderSoft;
  final Color sage;
  final Color hairline;
  final Color fieldFill;
  final Color glow;
  final Color success;
  final Color warning;
  final List<Color> heroGradient;
  final List<BoxShadow> cardShadow;
  final List<BoxShadow> floatingShadow;

  const EvaPalette({
    required this.gold,
    required this.goldSoft,
    required this.blush,
    required this.lavender,
    required this.lavenderSoft,
    required this.sage,
    required this.hairline,
    required this.fieldFill,
    required this.glow,
    required this.success,
    required this.warning,
    required this.heroGradient,
    required this.cardShadow,
    required this.floatingShadow,
  });

  static const EvaPalette light = EvaPalette(
    gold: EvaColors.champagne,
    goldSoft: EvaColors.champagneLight,
    blush: EvaColors.blush,
    lavender: EvaColors.lavender,
    lavenderSoft: EvaColors.lavenderLight,
    sage: EvaColors.sage,
    hairline: EvaColors.hairlineLight,
    fieldFill: EvaColors.sand,
    glow: Color(0xFFF3DCDD),
    success: EvaColors.success,
    warning: EvaColors.warning,
    heroGradient: [Color(0xFFC07C86), Color(0xFFB76E79), Color(0xFFC6A27C)],
    cardShadow: [
      BoxShadow(color: Color(0x0F6B3A44), blurRadius: 24, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1)),
    ],
    floatingShadow: [
      BoxShadow(color: Color(0x1F6B3A44), blurRadius: 32, offset: Offset(0, 14)),
    ],
  );

  static const EvaPalette dark = EvaPalette(
    gold: Color(0xFFD8B892),
    goldSoft: Color(0xFF342A1F),
    blush: Color(0xFF3A252B),
    lavender: Color(0xFFBBA8D6),
    lavenderSoft: Color(0xFF2C2636),
    sage: Color(0xFF93C4A9),
    hairline: EvaColors.hairlineDark,
    fieldFill: EvaColors.nightHigh,
    glow: Color(0xFF2A1B21),
    success: Color(0xFF7DBFA3),
    warning: Color(0xFFE5AE6A),
    heroGradient: [Color(0xFF9E5A67), Color(0xFFB36E7A), Color(0xFFA8865F)],
    cardShadow: [
      BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8)),
    ],
    floatingShadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12)),
    ],
  );

  LinearGradient get hero => LinearGradient(
        colors: heroGradient,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  EvaPalette copyWith({
    Color? gold,
    Color? goldSoft,
    Color? blush,
    Color? lavender,
    Color? lavenderSoft,
    Color? sage,
    Color? hairline,
    Color? fieldFill,
    Color? glow,
    Color? success,
    Color? warning,
    List<Color>? heroGradient,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? floatingShadow,
  }) {
    return EvaPalette(
      gold: gold ?? this.gold,
      goldSoft: goldSoft ?? this.goldSoft,
      blush: blush ?? this.blush,
      lavender: lavender ?? this.lavender,
      lavenderSoft: lavenderSoft ?? this.lavenderSoft,
      sage: sage ?? this.sage,
      hairline: hairline ?? this.hairline,
      fieldFill: fieldFill ?? this.fieldFill,
      glow: glow ?? this.glow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      heroGradient: heroGradient ?? this.heroGradient,
      cardShadow: cardShadow ?? this.cardShadow,
      floatingShadow: floatingShadow ?? this.floatingShadow,
    );
  }

  @override
  EvaPalette lerp(ThemeExtension<EvaPalette>? other, double t) {
    if (other is! EvaPalette) return this;
    return EvaPalette(
      gold: Color.lerp(gold, other.gold, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      blush: Color.lerp(blush, other.blush, t)!,
      lavender: Color.lerp(lavender, other.lavender, t)!,
      lavenderSoft: Color.lerp(lavenderSoft, other.lavenderSoft, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      fieldFill: Color.lerp(fieldFill, other.fieldFill, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      heroGradient: t < 0.5 ? heroGradient : other.heroGradient,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      floatingShadow: t < 0.5 ? floatingShadow : other.floatingShadow,
    );
  }
}

/// Удобный доступ: `context.eva.gold`.
extension EvaThemeContext on BuildContext {
  EvaPalette get eva => Theme.of(this).extension<EvaPalette>() ?? EvaPalette.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
