// Новая функция: «Питание по фазе цикла».
// Подсказывает, на что сделать упор в питании сегодня, и одним нажатием
// просит Еву составить меню с учётом фазы.

import 'package:flutter/material.dart';

import '../../screens/ai_chat_screen.dart';
import '../../theme/eva_colors.dart';
import '../eva_ui.dart';

class CyclePhaseNutrition {
  final String key;
  final String title;
  final String subtitle;
  final List<String> focus;
  final List<String> foods;
  final String tip;
  final Color color;
  final IconData icon;

  const CyclePhaseNutrition({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.focus,
    required this.foods,
    required this.tip,
    required this.color,
    required this.icon,
  });

  static CyclePhaseNutrition forPhase(String phaseType) {
    switch (phaseType) {
      case 'menstruation':
        return const CyclePhaseNutrition(
          key: 'menstruation',
          title: 'Восполняем железо',
          subtitle: 'Менструация',
          focus: ['Железо', 'Витамин C', 'Магний'],
          foods: ['Гречка', 'Говядина', 'Шпинат', 'Гранат', 'Тёмный шоколад'],
          tip: 'Сочетай железо с витамином C — так оно усвоится лучше. Тёплые супы и имбирный чай мягко снимают спазмы.',
          color: EvaColors.menstruation,
          icon: Icons.water_drop_rounded,
        );
      case 'fertile':
      case 'ovulation':
        return const CyclePhaseNutrition(
          key: 'ovulation',
          title: 'Пик энергии',
          subtitle: 'Овуляция',
          focus: ['Цинк', 'Омега‑3', 'Антиоксиданты'],
          foods: ['Тыквенные семечки', 'Лосось', 'Брокколи', 'Морковь', 'Цитрусы'],
          tip: 'Больше овощей и воды — поддержим естественный подъём энергии и сияние кожи.',
          color: EvaColors.ovulation,
          icon: Icons.auto_awesome_rounded,
        );
      case 'pms':
        return const CyclePhaseNutrition(
          key: 'luteal',
          title: 'Мягко к себе',
          subtitle: 'Лютеиновая фаза',
          focus: ['Магний', 'Витамины B', 'Сложные углеводы'],
          foods: ['Банан', 'Орехи', 'Бурый рис', 'Тыква', 'Тёмный шоколад'],
          tip: 'Тяга к сладкому — это нормально. Сложные углеводы и магний помогут сохранить ровное настроение.',
          color: EvaColors.luteal,
          icon: Icons.nightlight_round,
        );
      case 'follicular':
        return const CyclePhaseNutrition(
          key: 'follicular',
          title: 'Энергия растёт',
          subtitle: 'Фолликулярная фаза',
          focus: ['Белок', 'Клетчатка', 'Пробиотики'],
          foods: ['Яйца', 'Индейка', 'Квашеная капуста', 'Овсянка', 'Ягоды'],
          tip: 'Отличное время для активных тренировок и новых привычек — делай упор на белок и овощи.',
          color: EvaColors.follicular,
          icon: Icons.eco_rounded,
        );
      case 'pregnancy':
        return const CyclePhaseNutrition(
          key: 'pregnancy',
          title: 'Питание для двоих',
          subtitle: 'Беременность',
          focus: ['Фолаты', 'Кальций', 'Железо'],
          foods: ['Зелёные овощи', 'Творог', 'Нежирное мясо', 'Бобовые', 'Цельнозерновой хлеб'],
          tip: 'Избегай сырой рыбы и непастеризованных сыров. Витамины и добавки — только по назначению врача.',
          color: EvaColors.pregnancy,
          icon: Icons.favorite_rounded,
        );
      case 'menopause':
        return const CyclePhaseNutrition(
          key: 'menopause',
          title: 'Сила и лёгкость',
          subtitle: 'Менопауза',
          focus: ['Кальций', 'Витамин D', 'Белок'],
          foods: ['Творог', 'Рыба', 'Кунжут', 'Бобовые', 'Зелень'],
          tip: 'Кальций и белок поддерживают кости и мышцы; меньше кофеина и острого — реже приливы.',
          color: EvaColors.lavender,
          icon: Icons.spa_rounded,
        );
      default:
        return const CyclePhaseNutrition(
          key: 'none',
          title: 'Баланс на каждый день',
          subtitle: 'Питание сегодня',
          focus: ['Белок', 'Клетчатка', 'Вода'],
          foods: ['Яйца', 'Гречка', 'Овощи', 'Фрукты', 'Кефир'],
          tip: 'Отметь начало цикла в «Гармонии» — и я буду подсказывать питание под каждую фазу.',
          color: EvaColors.sage,
          icon: Icons.restaurant_rounded,
        );
    }
  }
}

class CycleNutritionCard extends StatelessWidget {
  final String phaseType;
  final String? phaseLabel;

  const CycleNutritionCard({super.key, required this.phaseType, this.phaseLabel});

  void _askEva(BuildContext context, CyclePhaseNutrition info) {
    final String phase = phaseLabel ?? info.subtitle;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatScreen(
          botType: 'dietitian',
          initialDisplayMessage: 'Что мне лучше есть сегодня? (${info.subtitle.toLowerCase()})',
          initialTechnicalPrompt:
              'Сейчас у меня: $phase. Составь меню на сегодня (завтрак, обед, ужин и перекус) с учётом этой фазы, '
              'моей нормы КБЖУ и простых продуктов из обычного супермаркета. Сделай упор на: ${info.focus.join(', ')}. '
              'Коротко объясни, почему это полезно именно сейчас. Это только идеи — не записывай еду в дневник и не добавляй JSON log_food. '
              'В конце выведи общий список ингредиентов в [SHOPPING_LIST].',
          initialMode: 'meal_plan',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = CyclePhaseNutrition.forPhase(phaseType);
    return EvaCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EvaIconBubble(icon: info.icon, color: info.color, size: 42, iconSize: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EvaOverline('Питание по фазе · ${info.subtitle}', color: info.color),
                    const SizedBox(height: 2),
                    Text(info.title, style: theme.textTheme.titleLarge),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: info.focus.map((f) => EvaPill(text: f, color: info.color)).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            info.foods.join(' · '),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(info.tip, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          Row(
            children: [
              EvaPressable(
                onTap: () => _askEva(context, info),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(gradient: context.eva.hero, borderRadius: BorderRadius.circular(100)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text('Меню от Евы', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Общие рекомендации, не заменяют консультацию врача',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
