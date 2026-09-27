// Файл: lib/widgets/eva_ui.dart
//
// Библиотека премиальных UI-компонентов Моя Ева.
// Экраны собираются из этих кирпичиков, чтобы дизайн был единым.

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/eva_colors.dart';

// ---------------------------------------------------------------------------
// Токены
// ---------------------------------------------------------------------------

class EvaSpace {
  EvaSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;
  static const double page = 20; // горизонтальный отступ экранов
}

class EvaRadius {
  EvaRadius._();
  static const double card = 24;
  static const double sheet = 32;
  static const double field = 18;
  static const double tile = 18;
}

class EvaFormat {
  EvaFormat._();
  static final NumberFormat _int = NumberFormat.decimalPattern('ru');

  static String number(num value) => _int.format(value.round());

  /// Русские окончания: 1 день, 2 дня, 5 дней.
  static String plural(int n, String one, String few, String many) {
    final int mod10 = n % 10;
    final int mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  static String capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Безопасное приведение чисел из Firestore (int/double/String).
int evaInt(dynamic v, [int fallback = 0]) {
  if (v is num) return v.round();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), ''))?.round() ?? fallback;
  return fallback;
}

double evaDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? fallback;
  return fallback;
}

// ---------------------------------------------------------------------------
// Фон с мягким сиянием
// ---------------------------------------------------------------------------

class EvaBackground extends StatelessWidget {
  final Widget child;
  final bool glow;

  const EvaBackground({super.key, required this.child, this.glow = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        children: [
          if (glow)
            Positioned(
              top: -140,
              left: -60,
              right: -60,
              height: 420,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.2),
                      radius: 0.85,
                      colors: [palette.glow, palette.glow.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Нажимаемая обёртка с лёгким «пружинящим» откликом
// ---------------------------------------------------------------------------

class EvaPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final bool haptic;

  const EvaPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.975,
    this.haptic = true,
  });

  @override
  State<EvaPressable> createState() => _EvaPressableState();
}

class _EvaPressableState extends State<EvaPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    if (!enabled) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Карточка
// ---------------------------------------------------------------------------

class EvaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Gradient? gradient;
  final double radius;
  final bool border;
  final bool shadow;
  final Color? borderColor;
  final bool clip;

  const EvaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.gradient,
    this.radius = EvaRadius.card,
    this.border = true,
    this.shadow = true,
    this.borderColor,
    this.clip = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    Widget content = Padding(padding: padding, child: child);
    if (clip) {
      content = ClipRRect(borderRadius: BorderRadius.circular(radius), child: content);
    }
    final Widget box = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? theme.colorScheme.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: borderColor ?? palette.hairline) : null,
        boxShadow: shadow ? palette.cardShadow : null,
      ),
      child: content,
    );
    if (onTap == null && onLongPress == null) return box;
    return EvaPressable(onTap: onTap, onLongPress: onLongPress, child: box);
  }
}

// ---------------------------------------------------------------------------
// Кнопки
// ---------------------------------------------------------------------------

class EvaPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final double height;
  final Gradient? gradient;

  const EvaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.height = 56,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final bool enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: EvaPressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: (onPressed == null && !loading) ? 0.5 : 1,
          child: Container(
            height: height,
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: gradient ?? palette.hero,
              borderRadius: BorderRadius.circular(100),
              boxShadow: enabled
                  ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))]
                  : null,
            ),
            child: loading
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class EvaSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final double height;
  final Color? foreground;
  final Widget? leading;

  const EvaSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.height = 54,
    this.foreground,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final Color fg = foreground ?? theme.colorScheme.onSurface;
    return EvaPressable(
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: palette.hairline, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 10)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: fg, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая иконка-кнопка в «стеклянном» кружке.
class EvaCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final Color? background;
  final String? tooltip;

  const EvaCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.color,
    this.background,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final Widget btn = EvaPressable(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: palette.hairline),
          boxShadow: palette.cardShadow,
        ),
        child: Icon(icon, size: size * 0.46, color: color ?? theme.colorScheme.onSurface),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

// ---------------------------------------------------------------------------
// Типографические элементы
// ---------------------------------------------------------------------------

class EvaOverline extends StatelessWidget {
  final String text;
  final Color? color;
  const EvaOverline(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class EvaSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const EvaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Иконки, бейджи, чипы
// ---------------------------------------------------------------------------

class EvaIconBubble extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final double? iconSize;
  final bool filled;

  const EvaIconBubble({super.key, required this.icon, this.color, this.size = 44, this.iconSize, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: context.isDark ? 0.2 : 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: filled ? Colors.white : c, size: iconSize ?? size * 0.5),
    );
  }
}

class EvaPill extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  final bool solid;
  final EdgeInsetsGeometry padding;

  const EvaPill({
    super.key,
    required this.text,
    this.color,
    this.icon,
    this.solid = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color c = color ?? theme.colorScheme.primary;
    final Color fg = solid ? Colors.white : c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: solid ? c : c.withValues(alpha: context.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

class EvaChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? emoji;

  const EvaChoiceChip({super.key, required this.label, required this.selected, this.onTap, this.icon, this.emoji});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final Color primary = theme.colorScheme.primary;
    return EvaPressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: context.isDark ? 0.25 : 0.12) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: selected ? primary : palette.hairline, width: selected ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[Text(emoji!, style: const TextStyle(fontSize: 15)), const SizedBox(width: 6)],
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? primary : theme.colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? primary : theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Аватар
// ---------------------------------------------------------------------------

class EvaAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  final bool ring;
  final IconData? fallbackIcon;

  const EvaAvatar({super.key, required this.name, this.photoUrl, this.size = 48, this.ring = false, this.fallbackIcon});

  @override
  Widget build(BuildContext context) {
    final palette = context.eva;
    final theme = Theme.of(context);
    final String trimmed = name.trim();
    final String initial = trimmed.isEmpty ? '' : trimmed.characters.first.toUpperCase();

    final Widget fallback = Container(
      decoration: BoxDecoration(gradient: palette.hero),
      alignment: Alignment.center,
      child: fallbackIcon != null || initial.isEmpty
          ? Icon(fallbackIcon ?? Icons.person_rounded, color: Colors.white, size: size * 0.5)
          : Text(
              initial,
              style: TextStyle(
                fontFamily: EvaFonts.serif,
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
    );

    final String url = photoUrl ?? '';
    final Widget image = url.startsWith('http')
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          )
        : fallback;

    return Container(
      width: size,
      height: size,
      padding: ring ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: ring
          ? BoxDecoration(shape: BoxShape.circle, gradient: palette.hero)
          : const BoxDecoration(shape: BoxShape.circle),
      child: Container(
        decoration: ring
            ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.surface, width: 3))
            : null,
        child: ClipOval(child: SizedBox.expand(child: image)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Шторки (bottom sheets)
// ---------------------------------------------------------------------------

class EvaSheet {
  EvaSheet._();

  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: builder,
    );
  }
}

class EvaSheetHandle extends StatelessWidget {
  const EvaSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4.5,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

class EvaSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const EvaSheetHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvaSheetHandle(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.headlineSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Список вариантов в шторке (цель, активность, тема и т.д.).
class EvaOptionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const EvaOptionTile({super.key, required this.title, required this.selected, required this.onTap, this.subtitle, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final Color primary = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EvaPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: selected ? primary.withValues(alpha: context.isDark ? 0.18 : 0.08) : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(EvaRadius.tile),
            border: Border.all(color: selected ? primary : palette.hairline, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: selected ? primary : theme.colorScheme.onSurfaceVariant, size: 22),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 15, color: selected ? primary : theme.colorScheme.onSurface)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), color: primary, size: 22)
                    : Icon(Icons.circle_outlined, key: const ValueKey('off'), color: theme.colorScheme.outline, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Меню профиля / настроек
// ---------------------------------------------------------------------------

class EvaMenuGroup extends StatelessWidget {
  final List<Widget> children;
  final String? title;
  const EvaMenuGroup({super.key, required this.children, this.title});

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [];
    for (int i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i != children.length - 1) {
        items.add(const Divider(indent: 68, endIndent: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: EvaOverline(title!),
          ),
        EvaCard(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: items)),
      ],
    );
  }
}

class EvaMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  const EvaMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color c = destructive ? theme.colorScheme.error : (iconColor ?? theme.colorScheme.primary);
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            EvaIconBubble(icon: icon, color: c, size: 38, iconSize: 19),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      color: destructive ? theme.colorScheme.error : theme.colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Уведомления (snackbar)
// ---------------------------------------------------------------------------

enum EvaSnackType { info, success, error }

class EvaSnack {
  EvaSnack._();

  static void show(
    BuildContext context,
    String message, {
    EvaSnackType type = EvaSnackType.info,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    showOn(messenger, Theme.of(context), message, type: type, action: action, duration: duration);
  }

  static void showOn(
    ScaffoldMessengerState messenger,
    ThemeData theme,
    String message, {
    EvaSnackType type = EvaSnackType.info,
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    final palette = theme.extension<EvaPalette>() ?? EvaPalette.light;
    final IconData icon = switch (type) {
      EvaSnackType.success => Icons.check_circle_rounded,
      EvaSnackType.error => Icons.error_outline_rounded,
      EvaSnackType.info => Icons.auto_awesome_rounded,
    };
    final Color iconColor = switch (type) {
      EvaSnackType.success => palette.success,
      EvaSnackType.error => const Color(0xFFF08C92),
      EvaSnackType.info => theme.colorScheme.inversePrimary,
    };
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        action: action,
        content: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Пустые состояния, скелетоны, баннеры
// ---------------------------------------------------------------------------

class EvaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? illustration;
  final bool card;

  const EvaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.illustration,
    this.card = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        illustration ?? EvaIconBubble(icon: icon, size: 64, iconSize: 28),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          EvaPrimaryButton(label: actionLabel!, onPressed: onAction, expand: false, height: 48),
        ],
      ],
    );
    if (!card) return Padding(padding: const EdgeInsets.all(24), child: content);
    return EvaCard(padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20), child: Center(child: content));
  }
}

class EvaSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const EvaSkeleton({super.key, this.width, this.height = 16, this.radius = 10});

  @override
  State<EvaSkeleton> createState() => _EvaSkeletonState();
}

class _EvaSkeletonState extends State<EvaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color base = context.eva.fieldFill;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_c),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// Плашка состояния соединения / системных сообщений.
class EvaStatusBanner extends StatelessWidget {
  final bool visible;
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  const EvaStatusBanner({
    super.key,
    required this.visible,
    required this.text,
    this.icon = Icons.cloud_off_rounded,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color c = color ?? context.eva.warning;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : GestureDetector(
              onTap: onTap,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: context.isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: c),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Прогресс: кольцо и полоса
// ---------------------------------------------------------------------------

class EvaProgressRing extends StatelessWidget {
  final double progress; // 0..1 (может быть > 1 — перебор)
  final double size;
  final double stroke;
  final List<Color>? colors;
  final Color? trackColor;
  final Widget? child;

  const EvaProgressRing({
    super.key,
    required this.progress,
    this.size = 120,
    this.stroke = 10,
    this.colors,
    this.trackColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.eva;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            progress: value,
            stroke: stroke,
            colors: colors ?? palette.heroGradient,
            track: trackColor ?? palette.fieldFill,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  final List<Color> colors;
  final Color track;

  _RingPainter({required this.progress, required this.stroke, required this.colors, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (math.min(size.width, size.height) - stroke) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (progress <= 0) return;
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: colors.length >= 2 ? colors : [colors.first, colors.first],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.track != track || old.stroke != stroke || old.colors != colors;
}

class EvaMacroBar extends StatelessWidget {
  final String label;
  final int current;
  final int target;
  final Color color;
  final String unit;

  const EvaMacroBar({super.key, required this.label, required this.current, required this.target, required this.color, this.unit = 'г'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double p = target > 0 ? (current / target).clamp(0.0, 1.0).toDouble() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: p),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.16),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        RichText(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          text: TextSpan(
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface),
            children: [
              TextSpan(text: '$current'),
              TextSpan(
                text: target > 0 ? ' / $target $unit' : ' $unit',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// «Ева печатает…»
// ---------------------------------------------------------------------------

class EvaTypingDots extends StatefulWidget {
  final Color? color;
  const EvaTypingDots({super.key, this.color});

  @override
  State<EvaTypingDots> createState() => _EvaTypingDotsState();
}

class _EvaTypingDotsState extends State<EvaTypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final double t = (_c.value - i * 0.18) % 1.0;
            final double y = math.sin(t * math.pi * 2).clamp(0.0, 1.0).toDouble();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 7,
              height: 7,
              transform: Matrix4.translationValues(0, -3 * y, 0),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.45 + 0.55 * y), shape: BoxShape.circle),
            );
          }),
        );
      },
    );
  }
}
