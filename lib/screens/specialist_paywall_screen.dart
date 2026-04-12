import 'package:flutter/material.dart';
import 'p2p_chat_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart'; // <-- ДОБАВЛЕНО ДЛЯ RUSTORE
import 'package:cloud_functions/cloud_functions.dart'; // <-- ДОБАВЛЕНО ДЛЯ СЕРВЕРНОЙ ПРОВЕРКИ


class SpecialistPaywallScreen extends StatefulWidget {
  final bool isFromProfile; // <-- Добавили переменную

  const SpecialistPaywallScreen({super.key, this.isFromProfile = false}); // <-- Добавили в конструктор

  @override
  State<SpecialistPaywallScreen> createState() =>
      _SpecialistPaywallScreenState();
}

class _SpecialistPaywallScreenState extends State<SpecialistPaywallScreen> {
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);
  static const String SUPPORT_ADMIN_UID = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  bool _isLoading = false;

  Future<void> _processPremiumPayment() async {
    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // 1. Вызываем стандартный SDK RuStore с новым ID продукта
      final purchaseResult = await RustoreBillingClient.purchase('specialist_chat_monthly', uid); 

      // Пытаемся достать токен
      String pToken = "mock_token_specialist";
      try {
        if (purchaseResult != null) {
          pToken = (purchaseResult as dynamic).purchaseToken?.toString() ?? "mock_token_specialist";
        }
      } catch (_) {}

      // 2. БЕЗОПАСНАЯ СЕРВЕРНАЯ ПРОВЕРКА (Cloud Functions)
      final callable = FirebaseFunctions.instance.httpsCallable('verifyRuStorePurchase');
      await callable.call({
        'productId': 'specialist_chat_monthly',
        'purchaseToken': pToken,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Оплата успешна! Чат со специалистом открыт. ✨'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка покупки специалиста через RuStore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Отмена или ошибка оплаты.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECE8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: _accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _subTextColor,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 8.0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: _textColor),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === ИСПРАВЛЕНО: Убрана ошибка загрузки ассета (черный квадрат) ===
                    const SizedBox(height: 24),
                    Center(
                      child: Icon(
                        Icons.spa,
                        size: 80,
                        color: _accentColor.withValues(alpha: 0.2),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "Личный консультант\nпо беременности",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _textColor,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Максимальная забота, индивидуальный подход и поддержка живого эксперта на каждом этапе твоего пути.",
                      style: TextStyle(
                        fontSize: 16,
                        color: _subTextColor,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildFeatureItem(
                      Icons.medical_information_outlined,
                      "Разбор анализов",
                      "Эксперт лично расшифрует твои результаты и даст понятные рекомендации.",
                    ),
                    _buildFeatureItem(
                      Icons.chat_bubble_outline,
                      "Связь 24/7",
                      "Задавай любые волнующие вопросы в удобное время без записи и очередей.",
                    ),
                    _buildFeatureItem(
                      Icons.psychology_outlined,
                      "Спокойствие",
                      "Мы развеем твои страхи и поможем отличить норму от поводов для беспокойства.",
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
              decoration: BoxDecoration(
                color: Colors.white,
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
                      // 1. Блокируем нажатие, если уже идет загрузка (защита от двойного списания)
                      onPressed: _isLoading ? null : _processPremiumPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                      ),
                      // 2. Показываем крутилку (CircularProgressIndicator) или текст
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Оформить за 5 000 ₽ / мес",
                              style: TextStyle(
                                color: Colors.white,
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
                            otherUserId: SUPPORT_ADMIN_UID,
                            otherUserName: 'Поддержка MyEva',
                          ),
                        ),
                      );
                    },
                    child: const Text(
                      "Остались вопросы? Написать в поддержку",
                      style: TextStyle(
                        color: _subTextColor,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
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

class _WaitingPaymentDialog extends StatefulWidget {
  final bool isSpecialist;
  final bool isFromProfile;

  const _WaitingPaymentDialog({
    required this.isSpecialist,
    this.isFromProfile = false,
  });

  @override
  State<_WaitingPaymentDialog> createState() => _WaitingPaymentDialogState();
}

class _WaitingPaymentDialogState extends State<_WaitingPaymentDialog> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final bool hasAccess = widget.isSpecialist
              ? (data['hasSpecialistAccess'] == true)
              : (data['isPro'] == true);

          // Если вебхук выдал доступ - автоматически закрываем окна
          // Если вебхук выдал доступ - автоматически закрываем окна
          if (hasAccess) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.pop(context); // 1. Закрываем диалог
                if (widget.isFromProfile) {
                  Navigator.pop(context); // 2. Возвращаемся в профиль
                } else {
                  Navigator.pop(context); // Безопасный фоллбэк
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Оплата успешно подтверждена! 🎉"),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            });
          }
        }

        return AlertDialog(
          title: const Text("Ожидание оплаты ⏳"),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Мы проверяем статус платежа. Окно закроется автоматически после подтверждения транзакции.",
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(color: Color(0xFFB76E79)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Скрыть", style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }
}