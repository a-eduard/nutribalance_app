// Курс «30 дней с Евой»: обзор дней, урок, отметка «Готово».
// Прогресс — users/{uid}.course = { active, startedAt, done: [дни], lastDoneKey: 'YYYY-MM-DD' }.
// Один новый урок в день. Уроки 1–3 бесплатно, дальше — PRO.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';

import '../../paywall_screen.dart';
import '../../services/analytics_service.dart';
import '../../services/database_service.dart';
import '../../theme/eva_colors.dart';
import '../../widgets/eva_ui.dart';
import '../ai_chat_screen.dart';
import '../label_scanner_screen.dart';
import '../shopping_list_screen.dart';
import 'course_content.dart';

/// Состояние курса из документа пользователя.
class CourseState {
  final bool active;
  final Set<int> done;
  final String? lastDoneKey;
  final bool pro;
  const CourseState({required this.active, required this.done, required this.lastDoneKey, required this.pro});

  factory CourseState.from(Map<String, dynamic>? user) {
    final Map c = user?['course'] is Map ? user!['course'] as Map : const {};
    final Set<int> done = (c['done'] is List ? c['done'] as List : const []).map((e) => evaInt(e)).where((d) => d >= 1 && d <= 30).toSet();
    return CourseState(
      active: c['active'] == true,
      done: done,
      lastDoneKey: c['lastDoneKey']?.toString(),
      pro: DatabaseService.isProActive(user),
    );
  }

  static String todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  int get completed => done.length;
  bool get finished => done.length >= 30;
  bool get doneToday => lastDoneKey == todayKey();

  /// Следующий урок по порядку (1..30) или null, если всё пройдено.
  int? get nextDay {
    final int n = done.isEmpty ? 1 : done.reduce((a, b) => a > b ? a : b) + 1;
    return n > 30 ? null : n;
  }

  /// Урок можно открыть: пройденный — всегда, следующий — если сегодня ещё не проходили.
  bool isOpen(int day) => done.contains(day) || (day == nextDay && !doneToday);
  bool needsPro(int day) => day > CourseContent.freeDays && !pro && !done.contains(day);
}

Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
}

class CourseScreen extends StatefulWidget {
  const CourseScreen({super.key});

  @override
  State<CourseScreen> createState() => _CourseScreenState();
}

class _CourseScreenState extends State<CourseScreen> {
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream = _userStream();

  @override
  void initState() {
    super.initState();
    Analytics.event('course_open');
  }

  void _openDay(CourseState s, int day) {
    if (s.needsPro(day)) {
      Analytics.event('course_paywall', {'day': day});
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true, source: 'course')));
      return;
    }
    if (!s.isOpen(day)) {
      EvaSnack.show(context, s.doneToday ? 'Следующий урок откроется завтра 🌙' : 'Сначала пройди предыдущие уроки', type: EvaSnackType.info);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(day: day)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('30 дней с Евой'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final s = CourseState.from(snap.data!.data());
            final int? next = s.nextDay;
            return ListView(
              padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
              children: [
                EvaCard(
                  gradient: context.eva.hero,
                  border: false,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EvaOverline('Курс · ${s.completed} из 30', color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(height: 8),
                      Text(s.finished ? 'Курс пройден! 🏆' : 'Каждый день — 3 минуты заботы о себе',
                          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text('Короткий урок и одно маленькое задание. Без диет и запретов — только привычки, которые останутся.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: s.completed / 30,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.22),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 14),
                  EvaPrimaryButton(
                    label: s.doneToday ? 'Следующий урок — завтра' : (s.completed == 0 ? 'Начать курс' : 'Урок $next: ${CourseContent.lessons[next - 1].title}'),
                    icon: s.doneToday ? PhosphorIconsLight.moon : Icons.play_arrow_rounded,
                    onPressed: s.doneToday ? null : () => _openDay(s, next),
                  ),
                ],
                const SizedBox(height: 20),
                for (int w = 0; w < 5; w++) ...[
                  EvaOverline('Неделя ${w + 1} · ${CourseContent.weeks[w]}'),
                  const SizedBox(height: 8),
                  for (final l in CourseContent.lessons.where((l) => (l.day - 1) ~/ 7 == w)) _dayTile(theme, s, l),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dayTile(ThemeData theme, CourseState s, CourseLesson l) {
    final bool done = s.done.contains(l.day);
    final bool open = s.isOpen(l.day);
    final bool locked = s.needsPro(l.day);
    final Widget trailing = done
        ? Icon(Icons.check_circle_rounded, color: context.eva.success)
        : locked
            ? EvaPill(text: 'PRO', color: context.eva.gold)
            : open
                ? Icon(Icons.play_circle_fill_rounded, color: theme.colorScheme.primary)
                : Icon(PhosphorIconsLight.lock, size: 20, color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: EvaCard(
        onTap: () => _openDay(s, l.day),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          SizedBox(width: 30, child: Text(l.emoji, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('День ${l.day}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(
                  color: open || done ? null : theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
          trailing,
        ]),
      ),
    );
  }
}

class LessonScreen extends StatefulWidget {
  final int day;
  const LessonScreen({super.key, required this.day});

  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  bool _saving = false;
  bool _justDone = false;
  final Stream<DocumentSnapshot<Map<String, dynamic>>>? _stream = _userStream();

  CourseLesson get _l => CourseContent.lessons[widget.day - 1];

  @override
  void initState() {
    super.initState();
    Analytics.event('course_lesson_open', {'day': widget.day});
  }

  Future<void> _complete() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'course': {
          'active': widget.day < 30,
          'done': FieldValue.arrayUnion([widget.day]),
          'lastDoneKey': CourseState.todayKey(),
          if (widget.day == 1) 'startedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      Analytics.event('course_lesson_done', {'day': widget.day});
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _justDone = true);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Не удалось сохранить. Проверь соединение.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _action() {
    final l = _l;
    Analytics.event('course_action', {'day': l.day});
    switch (l.action) {
      case CourseAction.eva:
        Navigator.push(context, MaterialPageRoute(builder: (_) => AIChatScreen(
              botType: 'dietitian',
              initialDisplayMessage: l.evaPrompt != null ? l.actionLabel : null,
              initialTechnicalPrompt: l.evaPrompt,
            )));
      case CourseAction.cosmetologist:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'cosmetologist')));
      case CourseAction.scanner:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelScannerScreen()));
      case CourseAction.shopping:
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShoppingListScreen()));
      case CourseAction.calendar:
        EvaSnack.show(context, 'Календарь — вторая вкладка внизу экрана 📅', type: EvaSnackType.info);
      case CourseAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = _l;
    return Scaffold(
      appBar: AppBar(
        title: Text('День ${l.day} из 30'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            final s = CourseState.from(snap.data?.data());
            final bool done = _justDone || s.done.contains(l.day);
            return ListView(
              padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
              children: [
                EvaOverline('Неделя ${(l.day - 1) ~/ 7 + 1} · ${CourseContent.weekOf(l.day)}'),
                const SizedBox(height: 8),
                Text('${l.emoji} ${l.title}', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                for (final p in l.body.split('\n\n'))
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(p, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45))),
                const SizedBox(height: 6),
                EvaCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const EvaOverline('Задание на сегодня'),
                    const SizedBox(height: 8),
                    Text(l.task, style: theme.textTheme.titleMedium),
                    if (l.action != CourseAction.none) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(onPressed: _action, icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: Text(l.actionLabel)),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
                if (done)
                  EvaCard(
                    child: Column(children: [
                      Text(l.day == 30 ? '🏆' : '🌸', style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(l.day == 30 ? 'Курс пройден! Ты молодец' : 'День ${l.day} пройден!', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(l.day == 30 ? 'Ева гордится тобой 💗' : 'Следующий урок откроется завтра — я напомню вечером.',
                          textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  )
                else
                  EvaPrimaryButton(label: 'Готово, урок пройден', icon: Icons.check_rounded, loading: _saving, onPressed: _saving ? null : _complete),
              ],
            );
          },
        ),
      ),
    );
  }
}
