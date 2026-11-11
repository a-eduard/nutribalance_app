// «Анализ кожи по фото»: согласие → подсказки по съёмке → фото → разбор Евы.
// Фото не сохраняется (анализ на сервере в памяти), история — только текстовые результаты.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../paywall_screen.dart';
import '../services/analytics_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';

class SkinAnalysisScreen extends StatefulWidget {
  const SkinAnalysisScreen({super.key});

  @override
  State<SkinAnalysisScreen> createState() => _SkinAnalysisScreenState();
}

class _SkinAnalysisScreenState extends State<SkinAnalysisScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final ImagePicker _picker = ImagePicker();
  bool? _consent;
  bool _agree = false;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>>? get _userRef => _uid == null ? null : FirebaseFirestore.instance.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    Analytics.event('skin_open');
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    try {
      final d = await _userRef?.get();
      if (mounted) setState(() => _consent = d?.data()?['skinConsentAt'] != null);
    } catch (_) {
      if (mounted) setState(() => _consent = false);
    }
  }

  Future<void> _giveConsent() async {
    await _userRef?.set({'skinConsentAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    Analytics.event('skin_consent');
    if (mounted) setState(() => _consent = true);
  }

  Future<void> _revokeConsent() async {
    await _userRef?.set({'skinConsentAt': FieldValue.delete()}, SetOptions(merge: true));
    Analytics.event('skin_consent_revoked');
    if (mounted) {
      setState(() {
        _consent = false;
        _agree = false;
      });
      EvaSnack.show(context, 'Согласие отозвано', type: EvaSnackType.info);
    }
  }

  Future<void> _shoot(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    Analytics.event('skin_analysis_start');
    try {
      final String b64 = base64Encode(await file.readAsBytes());
      final res = await FirebaseFunctions.instance
          .httpsCallable('skinAnalysis', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call({'imageBase64': b64});
      if (!mounted) return;
      final Map<String, dynamic> data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      if (data['ok'] != true) {
        Analytics.event('skin_analysis_retake');
        EvaSnack.show(context, (data['reason'] ?? 'Не получилось оценить фото').toString(), type: EvaSnackType.error, duration: const Duration(seconds: 6));
        return;
      }
      Analytics.event('skin_analysis_done');
      Navigator.push(context, MaterialPageRoute(builder: (_) => SkinResultScreen(data: data)));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      if (e.code == 'resource-exhausted') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true, source: 'skin_limit')));
      } else {
        EvaSnack.show(context, e.message ?? 'Не удалось проанализировать фото', type: EvaSnackType.error);
      }
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Нет соединения. Попробуй ещё раз.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Анализ кожи'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [
          if (_consent == true)
            PopupMenuButton<String>(
              onSelected: (_) => _revokeConsent(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'revoke', child: Text('Отозвать согласие на фото'))],
            ),
        ],
      ),
      body: EvaBackground(
        child: _consent == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                children: [
                  EvaCard(
                    gradient: const LinearGradient(colors: [Color(0xFF9A87B5), Color(0xFFC98FA6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: false,
                    padding: const EdgeInsets.all(22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      EvaOverline('Ева-косметолог', color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(height: 8),
                      Text('Что сейчас с твоей кожей?', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                      const SizedBox(height: 8),
                      Text('Сделай селфи — Ева определит тип кожи, увидит, на что обратить внимание, и соберёт уход утром и вечером под твою фазу цикла.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (_consent != true) _consentCard(theme) else ...[
                    _tipsCard(theme),
                    const SizedBox(height: 16),
                    if (_busy)
                      EvaCard(
                        child: Column(children: [
                          const SizedBox(height: 6),
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text('Ева смотрит на кожу…', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text('Обычно 10–20 секунд. Фото не сохраняется.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                        ]),
                      )
                    else ...[
                      EvaPrimaryButton(label: 'Сделать селфи', icon: Icons.photo_camera_front_rounded, onPressed: () => _shoot(ImageSource.camera)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _shoot(ImageSource.gallery),
                        icon: const Icon(PhosphorIconsLight.images),
                        label: const Text('Выбрать из галереи'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _History(uid: _uid),
                  ],
                  // На экране согласия этот текст уже есть в карточке — не дублируем.
                  if (_consent == true) ...[
                    const SizedBox(height: 12),
                    Text('Это косметическая оценка, а не диагноз. Родинки и новообразования Ева не оценивает — с ними к дерматологу.',
                        textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _consentCard(ThemeData theme) {
    Widget line(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
          ]),
        );
    return EvaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const EvaOverline('Перед первым фото'),
        const SizedBox(height: 12),
        line(PhosphorIconsLight.lock, 'Фото отправляется на анализ ИИ (Google Gemini) и не сохраняется — хранится только текстовый результат.'),
        line(Icons.face_outlined, 'Фото не используется для распознавания личности.'),
        line(Icons.medical_information_outlined, 'Это косметическая оценка, а не медицинский диагноз.'),
        line(Icons.undo_rounded, 'Согласие можно отозвать в любой момент в меню этого экрана.'),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agree,
          onChanged: (v) => setState(() => _agree = v == true),
          title: Text('Согласна на обработку фото лица для анализа кожи по Политике конфиденциальности', style: theme.textTheme.bodySmall),
        ),
        const SizedBox(height: 6),
        EvaPrimaryButton(label: 'Продолжить', onPressed: _agree ? _giveConsent : null),
      ]),
    );
  }

  Widget _tipsCard(ThemeData theme) {
    Widget tip(String e, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [Text(e, style: const TextStyle(fontSize: 20)), const SizedBox(width: 10), Expanded(child: Text(t, style: theme.textTheme.bodyMedium))]),
        );
    return EvaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const EvaOverline('Как сделать хорошее фото'),
        const SizedBox(height: 10),
        tip('☀️', 'Дневной свет, лицом к окну'),
        tip('🧼', 'Без макияжа и фильтров'),
        tip('🙂', 'Анфас, волосы убраны со лба'),
        tip('📱', 'Телефон на расстоянии вытянутой руки'),
      ]),
    );
  }
}

class _History extends StatelessWidget {
  final String? uid;
  const _History({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('skin_checks').orderBy('at', descending: true).limit(10).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const EvaOverline('Мои проверки'),
          const SizedBox(height: 8),
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: EvaCard(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SkinResultScreen(data: d.data()))),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        d.data()['at'] is Timestamp ? DateFormat('d MMMM, HH:mm', 'ru').format((d.data()['at'] as Timestamp).toDate()) : 'Только что',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        [
                          if ((d.data()['skinType'] ?? '').toString().isNotEmpty) '${d.data()['skinType']} кожа',
                          ...((d.data()['concerns'] as List?) ?? const []).whereType<Map>().take(2).map((c) => c['name'].toString().toLowerCase()),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class SkinResultScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const SkinResultScreen({super.key, required this.data});

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Map> concerns = data['concerns'] is List ? (data['concerns'] as List).whereType<Map>().toList() : const [];
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: EvaCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [EvaOverline(title), const SizedBox(height: 10), ...children])),
        );
    Widget steps(List<String> items) => Column(children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary))),
                Expanded(child: Text(items[i], style: theme.textTheme.bodyMedium)),
              ]),
            ),
        ]);
    final morning = _strings(data['morning']);
    final evening = _strings(data['evening']);
    final weekly = _strings(data['weekly']);
    final avoid = _strings(data['avoid']);
    final strengths = _strings(data['strengths']);
    final String skinType = (data['skinType'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Твоя кожа'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            EvaCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (skinType.isNotEmpty) EvaPill(text: '$skinType кожа', color: EvaColors.lavender, solid: true),
                  if (data['sensitivity'] == true) ...[const SizedBox(width: 8), const EvaPill(text: 'чувствительная', color: EvaColors.rose)],
                ]),
                const SizedBox(height: 12),
                Text((data['summary'] ?? '').toString(), style: theme.textTheme.bodyLarge),
                if (data['quality'] == 'fair' && (data['qualityTip'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('📸 ${data['qualityTip']}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            if (data['seeDoctor'] == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: EvaCard(
                  color: EvaColors.warning.withValues(alpha: 0.12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.medical_services_outlined, color: EvaColors.warning),
                    const SizedBox(width: 10),
                    Expanded(child: Text((data['seeDoctorReason'] ?? 'Лучше показать кожу дерматологу.').toString(), style: theme.textTheme.bodyMedium)),
                  ]),
                ),
              ),
            if (concerns.isNotEmpty)
              section('На что обратить внимание', [
                for (final c in concerns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${_cap(c['name'].toString())}${(c['zone'] ?? '').toString().isNotEmpty ? ' · ${c['zone']}' : ''}', style: theme.textTheme.titleSmall)),
                        for (int i = 1; i <= 3; i++)
                          Container(
                            margin: const EdgeInsets.only(left: 3),
                            width: 18,
                            height: 6,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: i <= evaInt(c['level'], 1) ? EvaColors.rose : EvaColors.rose.withValues(alpha: 0.15),
                            ),
                          ),
                      ]),
                      if ((c['tip'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(c['tip'].toString(), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                    ]),
                  ),
              ]),
            if (strengths.isNotEmpty) section('Что уже хорошо', [for (final s in strengths) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('✨ $s', style: theme.textTheme.bodyMedium))]),
            if (morning.isNotEmpty) section('Утренний уход', [steps(morning)]),
            if (evening.isNotEmpty) section('Вечерний уход', [steps(evening)]),
            if (weekly.isNotEmpty) section('Раз в неделю', [steps(weekly)]),
            if (avoid.isNotEmpty) section('Лучше избегать', [for (final a in avoid) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('— $a', style: theme.textTheme.bodyMedium))]),
            if ((data['phaseTip'] ?? '').toString().isNotEmpty) section('В твою фазу цикла', [Text(data['phaseTip'].toString(), style: theme.textTheme.bodyMedium)]),
            EvaPrimaryButton(
              label: 'Подобрать средства с Евой',
              icon: PhosphorIconsLight.chatCircleDots,
              onPressed: () {
                Analytics.event('skin_to_cosmetologist');
                final summary = [
                  'Я сделала анализ кожи по фото.',
                  if (skinType.isNotEmpty) 'Тип кожи: $skinType${data['sensitivity'] == true ? ', чувствительная' : ''}.',
                  if (concerns.isNotEmpty) 'Ева увидела: ${concerns.map((c) => '${c['name']} (${c['zone']}, уровень ${c['level']} из 3)').join('; ')}.',
                  'Помоги подобрать конкретные средства из российских магазинов под этот уход. Тип кожи и проблемы уже известны — не переспрашивай. Если бюджета нет в анкете, спроси только его.',
                ].join(' ');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AIChatScreen(
                      botType: 'cosmetologist',
                      initialDisplayMessage: 'Помоги подобрать средства под мой анализ кожи',
                      initialTechnicalPrompt: summary,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text('Косметическая оценка ИИ, не диагноз. Родинки и новообразования показывай дерматологу.',
                textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
