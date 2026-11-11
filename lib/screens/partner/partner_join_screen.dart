// Вход партнёра: имя + код от неё. Сервер (partnerLink join) делает аккаунт
// партнёрским, дальше HomeWrapper сам откроет PartnerHomeScreen.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/analytics_service.dart';
import '../../widgets/eva_ui.dart';

class PartnerJoinScreen extends StatefulWidget {
  const PartnerJoinScreen({super.key});

  @override
  State<PartnerJoinScreen> createState() => _PartnerJoinScreenState();
}

class _PartnerJoinScreenState extends State<PartnerJoinScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _busy = false;
  /// Имя уже указано при регистрации — второй раз не спрашиваем.
  bool _hasName = false;

  @override
  void initState() {
    super.initState();
    Analytics.event('partner_join_open');
    _prefillName();
  }

  Future<void> _prefillName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String name = '';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      name = (doc.data()?['name'] ?? '').toString().trim();
    } catch (_) {}
    if (name.isEmpty) name = (user.displayName ?? '').trim();
    if (name.isEmpty || name == 'Пользователь' || !mounted) return;
    setState(() {
      _name.text = name;
      _hasName = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final String name = _name.text.trim();
    final String code = _code.text.trim().toUpperCase().replaceAll(' ', '');
    if (name.isEmpty) {
      EvaSnack.show(context, 'Напиши, как тебя зовут', type: EvaSnackType.error);
      return;
    }
    if (code.length < 8) {
      EvaSnack.show(context, 'Код из 8 символов, начинается с PR', type: EvaSnackType.error);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('partnerLink', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call({'action': 'join', 'code': code, 'name': name});
      Analytics.event('partner_joined');
      if (!mounted) return;
      // Профиль стал партнёрским — корневой экран переключится сам.
      Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final String msg = switch (e.code) {
        'not-found' => 'Такого кода нет. Проверь буквы и цифры.',
        'already-exists' || 'failed-precondition' => e.message ?? 'Код нельзя применить',
        _ => 'Не удалось подключиться. Попробуй позже.',
      };
      EvaSnack.show(context, msg, type: EvaSnackType.error);
    } catch (_) {
      if (mounted) EvaSnack.show(context, 'Нет соединения. Попробуй позже.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Я партнёр'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
      ),
      body: EvaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
          children: [
            Text('Будь рядом в нужный момент', style: theme.textTheme.displaySmall),
            const SizedBox(height: 10),
            Text(
              'Ты будешь видеть, какая у неё сейчас фаза цикла, получать подсказки, как поддержать, '
              'и напоминание за пару дней до месячных. Её дневник, вес и питание остаются только у неё.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (!_hasName) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Как тебя зовут'),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Код от неё', hintText: 'Например, PR7K2PQX'),
              onSubmitted: (_) => _join(),
            ),
            const SizedBox(height: 8),
            Text('Код она найдёт в «Моей Еве»: Профиль → «Режим партнёра».',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            EvaPrimaryButton(label: 'Подключиться', icon: PhosphorIconsLight.heart, loading: _busy, onPressed: _busy ? null : _join),
          ],
        ),
      ),
    );
  }
}
