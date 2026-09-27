import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';

import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'p2p_chat_screen.dart';

class SpecialistPaywallScreen extends StatefulWidget {
  final bool isFromProfile;

  const SpecialistPaywallScreen({super.key, this.isFromProfile = false});

  @override
  State<SpecialistPaywallScreen> createState() => _SpecialistPaywallScreenState();
}

class _SpecialistPaywallScreenState extends State<SpecialistPaywallScreen> {
  static const String _supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  bool _isLoading = false;

  Future<void> _processPremiumPayment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isLoading = true);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    try {
      final purchaseResult = await RustoreBillingClient.purchase('specialist_chat_monthly', uid);
      if (purchaseResult.successPurchase == null) {
        throw Exception("Покупка не подтверждена на клиенте");
      }
      final String pToken = purchaseResult.successPurchase!.purchaseId;

      await FirebaseFunctions.instance
          .httpsCallable('verifyRuStorePurchase', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'productId': 'specialist_chat_monthly', 'purchaseToken': pToken});

      nav.pop();
      EvaSnack.showOn(messenger, theme, 'Оплата прошла! Чат со специалистом открыт ✨', type: EvaSnackType.success);
    } catch (e) {
      debugPrint('Ошибка покупки специалиста через RuStore: $e');
      EvaSnack.showOn(messenger, theme, 'Оплата отменена или RuStore недоступен.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _feature(ThemeData theme, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EvaIconBubble(icon: icon, color: context.eva.gold, size: 44, iconSize: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: EvaBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: EvaCircleButton(icon: Icons.arrow_back_ios_new_rounded, size: 40, onTap: () => Navigator.maybePop(context)),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    EvaOverline('Личный специалист', color: context.eva.gold),
                    const SizedBox(height: 10),
                    Text('Живой эксперт\nрядом с тобой', style: theme.textTheme.displaySmall),
                    const SizedBox(height: 12),
                    Text(
                      'Максимальная забота, индивидуальный подход и поддержка специалиста на каждом этапе — особенно во время беременности.',
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 28),
                    _feature(theme, Icons.medical_information_outlined, 'Разбор анализов', 'Эксперт лично расшифрует результаты и даст понятные рекомендации.'),
                    _feature(theme, Icons.chat_bubble_outline_rounded, 'Связь без очередей', 'Задавай вопросы в удобное время — без записи и ожидания.'),
                    _feature(theme, Icons.self_improvement_rounded, 'Спокойствие', 'Поможем отличить норму от поводов для беспокойства.'),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: context.eva.hairline)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EvaPrimaryButton(label: 'Оформить за 5 000 ₽ / мес', loading: _isLoading, onPressed: _processPremiumPayment),
                    TextButton(
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const P2PChatScreen(otherUserId: _supportAdminUid, otherUserName: 'Поддержка «Моя Ева»'),
                          ),
                        );
                      },
                      child: const Text('Остались вопросы? Написать в поддержку'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WaitingPaymentDialog extends StatefulWidget {
  final bool isSpecialist;
  final bool isFromProfile;

  const WaitingPaymentDialog({
    super.key,
    required this.isSpecialist,
    this.isFromProfile = false,
  });

  @override
  State<WaitingPaymentDialog> createState() => _WaitingPaymentDialogState();
}

class _WaitingPaymentDialogState extends State<WaitingPaymentDialog> {
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null && !_closed) {
          final bool hasAccess = widget.isSpecialist ? (data['hasSpecialistAccess'] == true) : (data['isPro'] == true);
          if (hasAccess) {
            _closed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final theme = Theme.of(context);
              nav.pop();
              if (widget.isFromProfile) nav.pop();
              EvaSnack.showOn(messenger, theme, 'Оплата подтверждена 🎉', type: EvaSnackType.success);
            });
          }
        }

        return AlertDialog(
          title: const Text('Ожидание оплаты'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Проверяем статус платежа. Окно закроется автоматически после подтверждения.'),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Скрыть')),
          ],
        );
      },
    );
  }
}
