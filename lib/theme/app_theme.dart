// Файл: lib/theme/app_theme.dart
//
// Дизайн-система «Soft Luxury»: айвори-фон, пудровая роза, шампань-золото,
// серифные заголовки (Noto Serif Display) и чистый интерфейсный Inter.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'eva_colors.dart';

class AppTheme {
  AppTheme._();

  /// Оставлено для обратной совместимости со старым кодом.
  static const Color accentColor = EvaColors.rose;

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: EvaColors.rose,
      onPrimary: Colors.white,
      primaryContainer: EvaColors.blush,
      onPrimaryContainer: Color(0xFF5E2A33),
      secondary: EvaColors.champagne,
      onSecondary: Colors.white,
      secondaryContainer: EvaColors.champagneLight,
      onSecondaryContainer: Color(0xFF5A4128),
      tertiary: EvaColors.lavender,
      onTertiary: Colors.white,
      tertiaryContainer: EvaColors.lavenderLight,
      onTertiaryContainer: Color(0xFF3E3152),
      error: EvaColors.error,
      onError: Colors.white,
      errorContainer: Color(0xFFFBE3E4),
      onErrorContainer: Color(0xFF5C1519),
      surface: EvaColors.pearl,
      onSurface: EvaColors.ink,
      onSurfaceVariant: EvaColors.mauveGrey,
      surfaceDim: Color(0xFFEDE5DE),
      surfaceBright: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xFFFCF9F6),
      surfaceContainer: EvaColors.sand,
      surfaceContainerHigh: EvaColors.linen,
      surfaceContainerHighest: Color(0xFFE8DDD4),
      outline: Color(0xFFD8CCC4),
      outlineVariant: EvaColors.hairlineLight,
      shadow: Color(0xFF3A2328),
      scrim: Colors.black,
      inverseSurface: Color(0xFF2E2529),
      onInverseSurface: Color(0xFFF7EFF0),
      inversePrimary: Color(0xFFF0B7BF),
      surfaceTint: Colors.transparent,
    ),
    background: EvaColors.ivory,
    palette: EvaPalette.light,
  );

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: EvaColors.roseNight,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF4A2A31),
      onPrimaryContainer: Color(0xFFF8DDE0),
      secondary: Color(0xFFD8B892),
      onSecondary: Color(0xFF3A2A18),
      secondaryContainer: Color(0xFF3B2F22),
      onSecondaryContainer: Color(0xFFF3E3CF),
      tertiary: Color(0xFFBBA8D6),
      onTertiary: Color(0xFF2B2140),
      tertiaryContainer: Color(0xFF342C40),
      onTertiaryContainer: Color(0xFFEDE3FA),
      error: Color(0xFFF08C92),
      onError: Color(0xFF4A0E13),
      errorContainer: Color(0xFF5C1D22),
      onErrorContainer: Color(0xFFFFDADC),
      surface: EvaColors.nightSurface,
      onSurface: EvaColors.moon,
      onSurfaceVariant: EvaColors.moonGrey,
      surfaceDim: EvaColors.night,
      surfaceBright: Color(0xFF2E272B),
      surfaceContainerLowest: Color(0xFF0E0C0D),
      surfaceContainerLow: EvaColors.nightLow,
      surfaceContainer: Color(0xFF201B1E),
      surfaceContainerHigh: EvaColors.nightHigh,
      surfaceContainerHighest: Color(0xFF2E272B),
      outline: Color(0xFF4A3F45),
      outlineVariant: EvaColors.hairlineDark,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: Color(0xFFF1E8EA),
      onInverseSurface: Color(0xFF2A2226),
      inversePrimary: EvaColors.rose,
      surfaceTint: Colors.transparent,
    ),
    background: EvaColors.night,
    palette: EvaPalette.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required EvaPalette palette,
  }) {
    final bool isDark = brightness == Brightness.dark;
    final TextTheme text = _textTheme(scheme);
    final RoundedRectangleBorder pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(100));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: EvaFonts.sans,
      textTheme: text,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[palette],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: palette.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        titleTextStyle: text.titleSmall?.copyWith(color: scheme.onSurface, fontSize: 15),
        subtitleTextStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.35),
          disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.8),
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
          shape: pill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.fieldFill,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.75)),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: palette.hairline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: scheme.error, width: 1.4)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.25),
        selectionHandleColor: scheme.primary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        dragHandleColor: scheme.outline,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
        actionTextColor: scheme.inversePrimary,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.fieldFill,
        selectedColor: scheme.primaryContainer,
        disabledColor: palette.fieldFill,
        side: BorderSide(color: palette.hairline),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        checkmarkColor: scheme.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : palette.fieldFill),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.transparent : scheme.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : Colors.transparent),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: scheme.outline, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : scheme.outline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.fieldFill,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: palette.fieldFill,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: Colors.white,
        textStyle: const TextStyle(fontFamily: EvaFonts.sans, fontSize: 10, fontWeight: FontWeight.w700),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(10)),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: scheme.primaryContainer,
        headerForegroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        todayBorder: BorderSide(color: scheme.primary),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle: const TextStyle(fontFamily: EvaFonts.sans, fontWeight: FontWeight.w700, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontFamily: EvaFonts.sans, fontWeight: FontWeight.w500, fontSize: 11),
        type: BottomNavigationBarType.fixed,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(pill),
          side: WidgetStateProperty.all(BorderSide(color: palette.hairline)),
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final Color ink = scheme.onSurface;
    TextStyle serif(double size, FontWeight weight, {double height = 1.15, double spacing = -0.3}) => TextStyle(
          fontFamily: EvaFonts.serif,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: ink,
        );
    TextStyle sans(double size, FontWeight weight, {double height = 1.4, double spacing = 0}) => TextStyle(
          fontFamily: EvaFonts.sans,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: ink,
        );

    return TextTheme(
      displayLarge: serif(46, FontWeight.w500, height: 1.05, spacing: -0.8),
      displayMedium: serif(38, FontWeight.w500, height: 1.08, spacing: -0.6),
      displaySmall: serif(32, FontWeight.w500, height: 1.1, spacing: -0.5),
      headlineLarge: serif(30, FontWeight.w500, spacing: -0.5),
      headlineMedium: serif(26, FontWeight.w500, spacing: -0.4),
      headlineSmall: serif(22, FontWeight.w500, spacing: -0.2),
      titleLarge: serif(20, FontWeight.w600, spacing: -0.1),
      titleMedium: sans(16, FontWeight.w600, height: 1.3),
      titleSmall: sans(14, FontWeight.w600, height: 1.3),
      bodyLarge: sans(16, FontWeight.w400, height: 1.5),
      bodyMedium: sans(14, FontWeight.w400, height: 1.45),
      bodySmall: sans(12.5, FontWeight.w400, height: 1.4).copyWith(color: scheme.onSurfaceVariant),
      labelLarge: sans(14, FontWeight.w600, spacing: 0.1),
      labelMedium: sans(12, FontWeight.w600, spacing: 0.2),
      labelSmall: sans(11, FontWeight.w600, spacing: 0.5),
    );
  }
}
