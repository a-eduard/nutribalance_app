// Кнопки по бокам кольца цикла на главном экране: «Начало цикла» и «О фазах».
// Иконки нарисованы вручную в стиле приложения (тонкая линия, мягкий градиент,
// акцент цветом фазы), вместо стандартных Material-иконок.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/eva_colors.dart';
import 'eva_ui.dart';

enum CycleIconKind { calendar, phases }

class CycleActionButton extends StatelessWidget {
  final CycleIconKind kind;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const CycleActionButton({
    super.key,
    required this.kind,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final bool dark = theme.brightness == Brightness.dark;
    final Color line = theme.colorScheme.primary;
    final Color accent = kind == CycleIconKind.calendar ? EvaColors.menstruation : palette.lavender;
    const double size = 50;

    return Tooltip(
      message: tooltip,
      child: EvaPressable(
        onTap: onTap,
        pressedScale: 0.92,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? [line.withValues(alpha: 0.20), palette.gold.withValues(alpha: 0.10)]
                        : [palette.blush, palette.goldSoft],
                  ),
                  border: Border.all(color: line.withValues(alpha: dark ? 0.35 : 0.22)),
                  boxShadow: [BoxShadow(color: line.withValues(alpha: dark ? 0.10 : 0.14), blurRadius: 14, offset: const Offset(0, 5))],
                ),
                child: Center(
                  child: CustomPaint(
                    size: const Size.square(26),
                    painter: kind == CycleIconKind.calendar
                        ? _CalendarDropPainter(line: line, accent: accent)
                        : _MoonPhasePainter(line: line, accent: accent),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Календарь с капелькой — «отметить начало цикла».
class _CalendarDropPainter extends CustomPainter {
  final Color line;
  final Color accent;
  _CalendarDropPainter({required this.line, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final RRect body = RRect.fromRectAndRadius(Rect.fromLTRB(s * 0.12, s * 0.20, s * 0.88, s * 0.90), Radius.circular(s * 0.16));
    canvas.drawRRect(body, stroke);
    canvas.drawLine(Offset(s * 0.12, s * 0.40), Offset(s * 0.88, s * 0.40), stroke);
    // кольца переплёта
    canvas.drawLine(Offset(s * 0.34, s * 0.10), Offset(s * 0.34, s * 0.28), stroke);
    canvas.drawLine(Offset(s * 0.66, s * 0.10), Offset(s * 0.66, s * 0.28), stroke);

    // капля
    final double cx = s * 0.5, top = s * 0.50, r = s * 0.12, cy = s * 0.70;
    final Path drop = Path()
      ..moveTo(cx, top)
      ..cubicTo(cx + r * 0.35, top + r * 0.8, cx + r, cy - r * 0.55, cx + r, cy)
      ..arcToPoint(Offset(cx - r, cy), radius: Radius.circular(r), clockwise: true)
      ..cubicTo(cx - r, cy - r * 0.55, cx - r * 0.35, top + r * 0.8, cx, top)
      ..close();
    canvas.drawPath(drop, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _CalendarDropPainter old) => old.line != line || old.accent != accent;
}

/// Луна в фазе с искоркой — «о фазах цикла».
class _MoonPhasePainter extends CustomPainter {
  final Color line;
  final Color accent;
  _MoonPhasePainter({required this.line, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Offset c = Offset(s * 0.46, s * 0.54);
    final double r = s * 0.36;
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;

    // освещённая половина — мягкая заливка цветом фазы
    final Path lit = Path()
      ..addArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi)
      ..quadraticBezierTo(c.dx + r * 0.25, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(lit, Paint()..color = accent.withValues(alpha: 0.85));
    canvas.drawCircle(c, r, stroke);

    // искорка справа сверху
    final Offset sp = Offset(s * 0.86, s * 0.16);
    final double a = s * 0.11;
    final Path spark = Path()
      ..moveTo(sp.dx, sp.dy - a)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx + a, sp.dy)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx, sp.dy + a)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx - a, sp.dy)
      ..quadraticBezierTo(sp.dx, sp.dy, sp.dx, sp.dy - a)
      ..close();
    canvas.drawPath(spark, Paint()..color = EvaColors.champagne);
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter old) => old.line != line || old.accent != accent;
}
