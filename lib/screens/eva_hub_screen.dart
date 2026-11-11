// Вкладка «Ева» — главный экран ИИ-помощниц и инструментов.
// Сюда же позже встанут курс «30 дней с Евой», челленджи и голосовая Ева.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/analytics_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/dashboard/cycle_nutrition_card.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';
import 'challenges/challenges_screen.dart';
import 'course/course_content.dart';
import 'course/course_screen.dart';
import 'health_screen.dart';
import 'cosmetic_shelf_screen.dart';
import 'label_scanner_screen.dart';
import 'skin_analysis_screen.dart';
import 'shopping_list_screen.dart';

class EvaHubScreen extends StatelessWidget {
  /// Текущая фаза — для «Меню на сегодня».
  final String phaseType;
  const EvaHubScreen({super.key, this.phaseType = ''});

  void _open(BuildContext context, Widget screen, String event) {
    Analytics.event('eva_hub_tap', {'item': event});
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: EvaBackground(
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(EvaSpace.page, 16, EvaSpace.page, 120),
            children: [
              const EvaOverline('Твои помощницы'),
              const SizedBox(height: 4),
              Text('Ева', style: theme.textTheme.displaySmall),
              const SizedBox(height: 18),
              _AssistantCard(
                emoji: '🥗',
                title: 'Питание',
                subtitle: 'Калории по фото, меню под фазу, вопросы о еде',
                gradient: context.eva.hero,
                onTap: () => _open(context, const AIChatScreen(botType: 'dietitian'), 'dietitian'),
              ),
              const SizedBox(height: 12),
              _AssistantCard(
                emoji: '💆‍♀️',
                title: 'Уход за кожей',
                subtitle: 'Косметолог: уход по фазе цикла, составы, анализ кожи',
                gradient: const LinearGradient(colors: [Color(0xFF9A87B5), Color(0xFFC98FA6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                onTap: () => _open(context, const AIChatScreen(botType: 'cosmetologist'), 'cosmetologist'),
              ),
              const SizedBox(height: 12),
              _AssistantCard(
                emoji: '🧪',
                title: 'Анализы и здоровье',
                subtitle: 'Расшифровка анализов из PDF или фото простым языком',
                gradient: const LinearGradient(colors: [Color(0xFF6E9E86), Color(0xFF9CB8A3)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                onTap: () => _open(context, const AIChatScreen(botType: 'analyses'), 'analyses'),
              ),
              const SizedBox(height: 24),
              const EvaOverline('Программы'),
              const SizedBox(height: 10),
              const _CourseCard(),
              const SizedBox(height: 12),
              EvaCard(
                onTap: () => _open(context, const ChallengesScreen(), 'challenges'),
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const EvaIconBubble(icon: PhosphorIconsLight.trophy, color: EvaColors.luteal, size: 46, iconSize: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Челленджи с подругами', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('Готовые и свои привычки — вместе с подругами', style: theme.textTheme.bodySmall),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
              const SizedBox(height: 24),
              const EvaOverline('Инструменты'),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.12,
                children: [
                  _ToolTile(
                    icon: PhosphorIconsLight.scanSmiley,
                    color: EvaColors.lavender,
                    title: 'Анализ кожи',
                    subtitle: 'Селфи — тип кожи и уход',
                    onTap: () => _open(context, const SkinAnalysisScreen(), 'skin_analysis'),
                  ),
                  _ToolTile(
                    icon: PhosphorIconsLight.scan,
                    color: EvaColors.rose,
                    title: 'Сканер состава',
                    subtitle: 'Продукты и косметика',
                    onTap: () => _open(context, const LabelScannerScreen(), 'scanner'),
                  ),
                  _ToolTile(
                    icon: PhosphorIconsLight.forkKnife,
                    color: EvaColors.follicular,
                    title: 'Меню на сегодня',
                    subtitle: 'Под фазу цикла и норму',
                    onTap: () {
                      Analytics.event('eva_hub_tap', {'item': 'meal_plan'});
                      CycleNutritionCard.askEvaForMenu(context, phaseType);
                    },
                  ),
                  _ToolTile(
                    icon: PhosphorIconsLight.shoppingBag,
                    color: EvaColors.luteal,
                    title: 'Список покупок',
                    subtitle: 'Из меню и рецептов Евы',
                    onTap: () => _open(context, const ShoppingListScreen(), 'shopping'),
                  ),
                  _ToolTile(
                    icon: PhosphorIconsLight.drop,
                    color: EvaColors.ovulation,
                    title: 'Моя полка',
                    subtitle: 'Косметика, которая есть дома',
                    onTap: () => _open(context, const CosmeticShelfScreen(), 'shelf'),
                  ),
                  _ToolTile(
                    icon: PhosphorIconsLight.personSimpleWalk,
                    color: EvaColors.sage,
                    title: 'Шаги и сон',
                    subtitle: 'Health Connect',
                    onTap: () => _open(context, const HealthScreen(), 'health'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final VoidCallback onTap;
  final bool isNew;
  const _AssistantCard({required this.emoji, required this.title, required this.subtitle, required this.gradient, required this.onTap}) : isNew = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvaCard(
      onTap: onTap,
      gradient: gradient,
      border: false,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(title, style: theme.textTheme.titleLarge?.copyWith(color: Colors.white))),
                  if (isNew) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                      child: Text('новое', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                const SizedBox(height: 10),
                Text('Открыть чат →', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ToolTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaIconBubble(icon: icon, color: color, size: 40, iconSize: 20),
          const Spacer(),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Карточка курса «30 дней с Евой» с прогрессом.
class _CourseCard extends StatelessWidget {
  const _CourseCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final s = CourseState.from(snap.data?.data());
        final int? next = s.nextDay;
        final String sub = s.finished
            ? 'Пройден 🏆 Перечитай любимые уроки'
            : s.completed == 0
                ? 'Урок и маленькое задание в день. Первые 3 урока бесплатно'
                : s.doneToday
                    ? 'Сегодня пройдено ✓ Следующий урок — завтра'
                    : 'Урок $next: ${CourseContent.lessons[(next ?? 1) - 1].title}';
        return EvaCard(
          onTap: () {
            Analytics.event('eva_hub_tap', {'item': 'course'});
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CourseScreen()));
          },
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🌸', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Курс «30 дней с Евой»', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(sub, style: theme.textTheme.bodySmall),
                ]),
              ),
              Text('${s.completed}/30', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
            ]),
            if (s.completed > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: s.completed / 30, minHeight: 6),
              ),
            ],
          ]),
        );
      },
    );
  }
}
