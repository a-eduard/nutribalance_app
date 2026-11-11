// «Для тебя сегодня» — горизонтальная лента подсказок на главном экране.
// Заменяет отдельные карточки «Питание по фазе» и «Итоги недели».

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../screens/ai_chat_screen.dart';
import '../../screens/course/course_content.dart';
import '../../screens/course/course_screen.dart';
import '../../screens/label_scanner_screen.dart';
import '../../screens/weekly_insights_screen.dart';
import '../../services/analytics_service.dart';
import '../../theme/eva_colors.dart';
import '../eva_ui.dart';
import 'cycle_nutrition_card.dart';

class ForYouStrip extends StatelessWidget {
  final String phaseType;
  final String? phaseLabel;
  /// Документ пользователя — для карточки курса.
  final Map<String, dynamic>? userData;
  const ForYouStrip({super.key, required this.phaseType, this.phaseLabel, this.userData});

  static (String, String) _skin(String phase) => switch (phase) {
        'menstruation' => ('Кожа чувствительнее', 'Мягкое очищение и больше увлажнения'),
        'follicular' => ('Время для активов', 'Кожа хорошо принимает кислоты и процедуры'),
        'ovulation' || 'fertile' => ('Кожа сияет', 'Лёгкие текстуры и обязательно SPF'),
        'pms' || 'luteal' => ('Больше высыпаний', 'Точечный уход, без новых средств'),
        'pregnancy' => ('Бережный уход', 'Без ретиноидов и сильных кислот'),
        _ => ('Простой уход', 'Очищение, увлажнение и SPF'),
      };

  void _tap(BuildContext context, String item, VoidCallback go) {
    Analytics.event('for_you_tap', {'item': item});
    go();
  }

  @override
  Widget build(BuildContext context) {
    final nutrition = CyclePhaseNutrition.forPhase(phaseType);
    final (skinTitle, skinSub) = _skin(phaseType);
    final String phaseName = phaseLabel ?? nutrition.subtitle;

    final course = CourseState.from(userData);
    final int? next = course.nextDay;
    final cards = <Widget>[
      if (!course.finished && !course.doneToday)
        _StripCard(
          icon: PhosphorIconsLight.flower,
          color: EvaColors.rose,
          overline: course.completed == 0 ? 'Новый курс' : 'Курс · день $next из 30',
          title: course.completed == 0 ? '30 дней с Евой' : CourseContent.lessons[(next ?? 1) - 1].title,
          subtitle: course.completed == 0 ? '3 минуты в день — привычки без диет' : 'Урок на 3 минуты и одно задание',
          onTap: () => _tap(context, 'course', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CourseScreen()))),
        ),
      _StripCard(
        icon: nutrition.icon,
        color: nutrition.color,
        overline: 'Питание по фазе',
        title: nutrition.title,
        subtitle: 'Упор: ${nutrition.focus.join(', ')}',
        onTap: () => _tap(context, 'nutrition', () {
          EvaSheet.show<void>(
            context,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: CycleNutritionCard(phaseType: phaseType, phaseLabel: phaseLabel),
              ),
            ),
          );
        }),
      ),
      _StripCard(
        icon: PhosphorIconsLight.flowerLotus,
        color: EvaColors.lavender,
        overline: 'Уход за кожей',
        title: skinTitle,
        subtitle: skinSub,
        onTap: () => _tap(context, 'skin', () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AIChatScreen(
                botType: 'cosmetologist',
                initialDisplayMessage: 'Как ухаживать за кожей сейчас?',
                initialTechnicalPrompt: 'Сейчас у меня: $phaseName. Подскажи уход за кожей на эти дни: утро и вечер, '
                    'что добавить и от чего отказаться. Учитывай мой тип кожи, если он известен, иначе спроси его в конце.',
              ),
            ),
          );
        }),
      ),
      _StripCard(
        icon: PhosphorIconsLight.chartLineUp,
        color: EvaColors.ovulation,
        overline: 'Итоги недели',
        title: 'Разбор от Евы',
        subtitle: 'Питание, самочувствие и 3 совета',
        onTap: () => _tap(context, 'insights', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyInsightsScreen()))),
      ),
      _StripCard(
        icon: PhosphorIconsLight.scan,
        color: EvaColors.rose,
        overline: 'В магазине',
        title: 'Брать или нет?',
        subtitle: 'Сфотографируй состав — Ева разберёт',
        onTap: () => _tap(context, 'scanner', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelScannerScreen()))),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvaOverline('Для тебя сегодня'),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }
}

class _StripCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String overline;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _StripCard({required this.icon, required this.color, required this.overline, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: EvaCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              EvaIconBubble(icon: icon, color: color, size: 34, iconSize: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(overline.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 1))),
            ]),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
