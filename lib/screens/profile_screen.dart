import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../paywall_screen.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'p2p_chat_screen.dart';
import 'profile_settings_screen.dart';
import 'progress_screen.dart';
import 'smart_questionnaire_screen.dart';
import 'specialist_paywall_screen.dart';
import 'weekly_insights_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  bool _openingSpecialist = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось открыть ссылку', type: EvaSnackType.error);
    }
  }

  static bool _specialistActive(Map<String, dynamic> data) {
    if (data['hasSpecialistAccess'] != true) return false;
    final dynamic until = data['specialistUntil'];
    if (until is Timestamp) return until.toDate().isAfter(DateTime.now());
    return true;
  }

  Future<void> _openSpecialist(bool hasAccess) async {
    if (_openingSpecialist) return;
    setState(() => _openingSpecialist = true);
    final nav = Navigator.of(context);
    try {
      final bool inReview = hasAccess ? false : await DatabaseService().isAppInReview().timeout(const Duration(seconds: 6), onTimeout: () => false);
      if (hasAccess || inReview) {
        final spec = await DatabaseService().getSpecialistInfo().timeout(
              const Duration(seconds: 6),
              onTimeout: () => {'uid': ProfileScreen.supportAdminUid, 'name': 'Личный специалист'},
            );
        nav.push(MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: spec['uid']!, otherUserName: spec['name']!)));
      } else {
        nav.push(MaterialPageRoute(builder: (_) => const SpecialistPaywallScreen()));
      }
    } catch (e) {
      debugPrint('specialist: $e');
    } finally {
      if (mounted) setState(() => _openingSpecialist = false);
    }
  }

  Future<void> _runBackfill() async {
    EvaSnack.show(context, 'Обновляю публичные профили…');
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('backfillPublicProfiles', options: HttpsCallableOptions(timeout: const Duration(minutes: 9)))
          .call();
      if (!mounted) return;
      final count = res.data is Map ? (res.data as Map)['count'] : null;
      EvaSnack.show(context, 'Готово: $count профилей', type: EvaSnackType.success);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Ошибка: $e', type: EvaSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _userStream == null) return const SizedBox.shrink();

    return EvaBackground(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!.data() ?? <String, dynamic>{};
          final String name = (data['name']?.toString().trim().isNotEmpty ?? false) ? data['name'].toString().trim() : 'Пользователь';
          final String photoUrl = (data['photoUrl'] ?? '').toString();
          final String nickname = (data['nickname'] ?? '').toString().trim();
          final bool pro = DatabaseService.isProActive(data);
          final DateTime? proUntil = DatabaseService.proUntil(data);
          final bool specialist = _specialistActive(data);
          final int freeLeft = data['free_messages_left'] is num ? (data['free_messages_left'] as num).toInt() : 5;

          return SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(EvaSpace.page, 14, EvaSpace.page, 130),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Профиль', style: theme.textTheme.displaySmall)),
                    EvaCircleButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Настройки',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(child: EvaAvatar(name: name, photoUrl: photoUrl, size: 108, ring: true)),
                const SizedBox(height: 14),
                Center(child: Text(name, textAlign: TextAlign.center, style: theme.textTheme.headlineLarge)),
                if (nickname.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Center(child: Text('@$nickname', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                  ),
                const SizedBox(height: 10),
                Center(
                  child: pro
                      ? EvaPill(
                          text: proUntil != null ? 'Premium до ${DateFormat('d MMMM', 'ru').format(proUntil)}' : 'Premium',
                          icon: Icons.workspace_premium_rounded,
                          color: context.eva.gold,
                        )
                      : EvaPill(text: 'Бесплатный план', icon: Icons.spa_outlined, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                if (!pro) _buildPremiumCard(theme, freeLeft),
                if (!pro) const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.insights_rounded,
                        color: context.eva.lavender,
                        title: 'Итоги недели',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeeklyInsightsScreen())),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickTile(
                        icon: Icons.show_chart_rounded,
                        color: context.eva.sage,
                        title: 'Мой прогресс',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen())),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                EvaMenuGroup(
                  title: 'Персонализация',
                  children: [
                    EvaMenuTile(
                      icon: Icons.psychology_alt_outlined,
                      title: 'Сделать Еву умнее',
                      subtitle: 'Короткая анкета о привычках и здоровье',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartQuestionnaireScreen())),
                    ),
                    EvaMenuTile(
                      icon: Icons.tune_rounded,
                      title: 'Мои параметры',
                      subtitle: 'Вес, рост, цель, активность',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                EvaMenuGroup(
                  title: 'Забота и поддержка',
                  children: [
                    EvaMenuTile(
                      icon: Icons.star_rounded,
                      iconColor: context.eva.gold,
                      title: 'Личный специалист',
                      subtitle: specialist ? 'Чат открыт' : 'Консультации живого эксперта',
                      trailing: _openingSpecialist ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                      onTap: () => _openSpecialist(specialist),
                    ),
                    EvaMenuTile(
                      icon: Icons.favorite_border_rounded,
                      title: 'Заботливая поддержка',
                      subtitle: 'Вопросы о приложении и подписке',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: ProfileScreen.supportAdminUid, otherUserName: 'Поддержка «Моя Ева»')),
                      ),
                    ),
                    EvaMenuTile(
                      icon: FontAwesomeIcons.vk,
                      iconColor: const Color(0xFF4C75A3),
                      title: 'Наше комьюнити в VK',
                      onTap: () => _openUrl('https://vk.com/club237160300'),
                    ),
                    EvaMenuTile(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Видео-обзор приложения',
                      onTap: () => _openUrl('https://vkvideo.ru/video-237160300_456239022'),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                EvaMenuGroup(
                  title: 'Подписка',
                  children: [
                    EvaMenuTile(
                      icon: Icons.workspace_premium_outlined,
                      iconColor: context.eva.gold,
                      title: pro ? 'Моя подписка' : 'Оформить Premium',
                      subtitle: pro
                          ? (proUntil != null ? 'Активна до ${DateFormat('d MMMM yyyy', 'ru').format(proUntil)}' : 'Активна')
                          : 'Безлимитное общение с Евой',
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true))),
                    ),
                  ],
                ),
                if (uid == ProfileScreen.supportAdminUid) ...[
                  const SizedBox(height: 22),
                  EvaMenuGroup(
                    title: 'Администратор',
                    children: [
                      EvaMenuTile(
                        icon: Icons.manage_accounts_outlined,
                        title: 'Обновить публичные профили',
                        subtitle: 'Один раз после обновления сервера — для поиска в чатах',
                        onTap: _runBackfill,
                      ),
                      EvaMenuTile(
                        icon: Icons.bug_report_outlined,
                        title: 'Тестовый сбой Crashlytics',
                        subtitle: 'Приложение закроется. Откройте его снова — отчёт уйдёт в Firebase',
                        onTap: Analytics.testCrash,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPremiumCard(ThemeData theme, int freeLeft) {
    return EvaCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true))),
      gradient: LinearGradient(
        colors: [const Color(0xFF2E2226), Color.lerp(const Color(0xFF2E2226), context.eva.gold, 0.35)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: false,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EvaOverline('Моя Ева Premium', color: context.eva.gold),
                const SizedBox(height: 6),
                Text('Ева без ограничений', style: theme.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  freeLeft > 0 ? 'Осталось бесплатных сообщений: $freeLeft' : 'Бесплатные сообщения закончились',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: context.eva.gold, borderRadius: BorderRadius.circular(100)),
            child: Text('Подробнее', style: theme.textTheme.labelLarge?.copyWith(color: const Color(0xFF2E2226))),
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _QuickTile({required this.icon, required this.color, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EvaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaIconBubble(icon: icon, color: color, size: 38, iconSize: 20),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
