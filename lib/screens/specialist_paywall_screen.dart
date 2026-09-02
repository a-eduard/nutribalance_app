import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:cloud_functions/cloud_functions.dart'; 

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
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final purchaseResult = await RustoreBillingClient.purchase('specialist_chat_monthly', uid); 

      if (purchaseResult.successPurchase == null) {
        throw Exception("Покупка не подтверждена на клиенте");
      }
      
      // ИСПРАВЛЕНИЕ: Берем purchaseId
      String pToken = purchaseResult.successPurchase!.purchaseId;

      final callable = FirebaseFunctions.instance.httpsCallable('verifyRuStorePurchase');
      await callable.call({
        'productId': 'specialist_chat_monthly',
        'purchaseToken': pToken,
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Оплата успешна! Чат со специалистом открыт. ✨'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      debugPrint('Ошибка покупки специалиста через RuStore: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Отмена или ошибка оплаты.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
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
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 8.0),
              child: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, color: theme.colorScheme.onSurface),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Icon(
                        Icons.spa,
                        size: 80,
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Личный консультант\nпо беременности",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Максимальная забота, индивидуальный подход и поддержка живого эксперта на каждом этапе твоего пути.",
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildFeatureItem(
                      Icons.medical_information_outlined,
                      "Разбор анализов",
                      "Эксперт лично расшифрует твои результаты и даст понятные рекомендации.",
                      theme,
                    ),
                    _buildFeatureItem(
                      Icons.chat_bubble_outline,
                      "Связь 24/7",
                      "Задавай любые волнующие вопросы в удобное время без записи и очередей.",
                      theme,
                    ),
                    _buildFeatureItem(
                      Icons.psychology_outlined,
                      "Спокойствие",
                      "Мы развеем твои страхи и поможем отличить норму от поводов для беспокойства.",
                      theme,
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 32,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _processPremiumPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: theme.colorScheme.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              "Оформить за 5 000 ₽ / мес",
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const P2PChatScreen(
                            otherUserId: _supportAdminUid,
                            otherUserName: 'Поддержка Моя Ева',
                          ),
                        ),
                      );
                    },
                    child: Text(
                      "Остались вопросы? Написать в поддержку",
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final bool hasAccess = widget.isSpecialist
              ? (data['hasSpecialistAccess'] == true)
              : (data['isPro'] == true);

          if (hasAccess) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.pop(context); 
              if (widget.isFromProfile) {
                Navigator.pop(context); 
              } 
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Оплата успешно подтверждена! 🎉"),
                  backgroundColor: Colors.green,
                ),
              );
            });
          }
        }

        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: Text("Ожидание оплаты ⏳", style: TextStyle(color: theme.colorScheme.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Мы проверяем статус платежа. Окно закроется автоматически после подтверждения транзакции.",
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              CircularProgressIndicator(color: theme.colorScheme.primary),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Скрыть", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        );
      },
    );
  }
}