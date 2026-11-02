// Кнопки по бокам кольца цикла на главном экране: «Начало цикла» и «О фазах».
// Иконки нарисованы вручную в стиле приложения (тонкая линия, мягкий градиент,
// акцент цветом фазы), вместо стандартных Material-иконок.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../screens/ai_chat_screen.dart';
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

/// Шторка «Фазы цикла»: легенда кольца и 4 фазы с подсказками по питанию.
/// Прокручивается и не обрезается при крупном шрифте на маленьких экранах.
void showCyclePhasesSheet(BuildContext context, {String? currentPhaseType}) {
  final String? current = switch (currentPhaseType) {
    'menstruation' => 'menstruation',
    'follicular' => 'follicular',
    'ovulation' || 'fertile' => 'ovulation',
    'pms' || 'luteal' => 'luteal',
    _ => null,
  };
  EvaSheet.show<void>(
    context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final palette = ctx.eva;
      final phases = <(String, Color, String, String)>[
        ('menstruation', EvaColors.menstruation, 'Менструация', 'Организму нужны железо и тепло: красное мясо, гречка, тёплые супы.'),
        ('follicular', EvaColors.follicular, 'Фолликулярная', 'Растёт энергия — хорошо идут тренировки и новые дела.'),
        ('ovulation', palette.lavender, 'Овуляция', 'Пик сил и настроения. Налегай на овощи и клетчатку.'),
        ('luteal', EvaColors.luteal, 'Лютеиновая', 'Может тянуть на сладкое: помогут сложные углеводы, магний и белок.'),
      ];
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 10, EvaSpace.page, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: EvaSheetHandle()),
              const SizedBox(height: 14),
              Text('Фазы цикла', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Розовая дуга на кольце — дни менструации, лавандовая — окно овуляции, точка — сегодня.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              for (final ph in phases) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: ph.$1 == current ? ph.$2.withValues(alpha: 0.12) : palette.fieldFill,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: ph.$1 == current ? ph.$2.withValues(alpha: 0.55) : Colors.transparent),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: ph.$2, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(child: Text(ph.$3, style: theme.textTheme.titleSmall)),
                              if (ph.$1 == current) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: ph.$2, borderRadius: BorderRadius.circular(20)),
                                  child: Text('сейчас', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 3),
                            Text(ph.$4, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 10),
              EvaPrimaryButton(
                label: 'Спросить Еву о моей фазе',
                icon: Icons.auto_awesome_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AIChatScreen(
                      botType: 'dietitian',
                      initialDisplayMessage: 'Что мне лучше есть в мою текущую фазу цикла?',
                      initialTechnicalPrompt: 'Что мне лучше есть в текущей фазе цикла и почему? Дай короткое меню на сегодня под мою норму.',
                      initialMode: 'meal_plan',
                    ),
                  ));
                },
              ),
              const SizedBox(height: 8),
              Center(child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно'))),
            ],
          ),
        ),
      );
    },
  );
}
