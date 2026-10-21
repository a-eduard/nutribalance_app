// Файл: lib/paywall_screen.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/subscription_service.dart';
import 'theme/eva_colors.dart';
import 'widgets/eva_ui.dart';
import 'services/analytics_service.dart';

class PaywallScreen extends StatefulWidget {
  final bool isFromProfile;

  /// Откуда открыт пейвол — для статистики (profile, eva_limit, scan_limit…).
  final String? source;

  const PaywallScreen({super.key, this.isFromProfile = false, this.source});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;
  String _selectedPlan = 'year';
  String? _appliedPromo;

  static const double _basePriceMonth = 299;
  static const double _basePriceYear = 1490;

  late final TextEditingController _promoController;

  @override
  void initState() {
    super.initState();
    _promoController = TextEditingController();
    Analytics.event('paywall_view', {'source': widget.source ?? (widget.isFromProfile ? 'profile' : 'other')});
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  void _close() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  // ---------------------------------------------------------------------------
  // Промокоды (проверяются на сервере)
  // ---------------------------------------------------------------------------

  Future<void> _applyPromoCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return;

    // Скидочные коды применяются локально (цена фиксируется продуктом RuStore).
    if (cleanCode == 'SALE50EVA' || cleanCode == 'SALE50') {
      setState(() => _appliedPromo = 'SALE50');
      Analytics.event('promo_redeemed', {'code': cleanCode, 'type': 'discount'});
      EvaSnack.show(context, 'Промокод применён: скидка 50% ✨', type: EvaSnackType.success);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('redeemPromo', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
          .call({'code': cleanCode});
      if (!mounted) return;
      final data = res.data is Map ? res.data as Map : const {};
      Analytics.event('promo_redeemed', {'code': cleanCode, 'type': (data['type'] ?? 'trial').toString()});
      if (data['type'] == 'discount') {
        setState(() => _appliedPromo = (data['code'] ?? 'SALE50').toString());
        EvaSnack.show(context, 'Промокод применён: скидка ${data['percent'] ?? 50}% ✨', type: EvaSnackType.success);
      } else {
        EvaSnack.show(context, 'Промокод активирован! Premium на ${data['days'] ?? 3} дн. ✨', type: EvaSnackType.success);
        _close();
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final String msg = switch (e.code) {
        'already-exists' => 'Вы уже использовали этот промокод',
        'not-found' => 'Неверный промокод',
        'unauthenticated' => 'Войдите в аккаунт, чтобы применить промокод',
        _ => 'Не удалось проверить промокод. Попробуйте позже.',
      };
      EvaSnack.show(context, msg, type: EvaSnackType.error);
    } catch (e) {
      if (mounted) EvaSnack.show(context, 'Нет соединения. Попробуйте позже.', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPromoDialog() {
    _promoController.clear();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Промокод'),
        content: TextField(
          controller: _promoController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Например, START3'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final code = _promoController.text;
              Navigator.pop(ctx);
              _applyPromoCode(code);
            },
            child: const Text('Применить'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Покупка через RuStore
  // ---------------------------------------------------------------------------

  Future<void> _buySubscription(String productId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String pToken = '';
    try {
      final purchaseResult = await RustoreBillingClient.purchase(productId, user.uid);
      if (purchaseResult.successPurchase == null) {
        Analytics.event('purchase_cancelled', {'product_id': productId});
        debugPrint("Оплата отменена пользователем или не удалась на устройстве.");
        return;
      }
      pToken = purchaseResult.successPurchase!.purchaseId;
    } catch (nativeError) {
      debugPrint("🔥 Ошибка SDK RuStore: $nativeError");
      if (!mounted) return;
      final errorText = nativeError.toString().toLowerCase();
      if (errorText.contains('already') || errorText.contains('purchased') || errorText.contains('owned') || errorText.contains('приобретен')) {
        EvaSnack.show(context, 'Подписка уже активна — восстанавливаем доступ…');
        await _restorePurchases();
      } else {
        EvaSnack.show(
          context,
          'Оплата отменена или RuStore недоступен. Для оплаты нужен установленный RuStore и российский сервер (без VPN).',
          type: EvaSnackType.error,
          duration: const Duration(seconds: 6),
        );
      }
      return;
    }

    // Деньги списаны — подтверждаем на сервере.
    try {
      await FirebaseFunctions.instance
          .httpsCallable('verifyRuStorePurchase', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'productId': productId, 'purchaseToken': pToken});
      if (!mounted) return;
      Analytics.purchase(productId: productId);
      EvaSnack.show(context, 'Добро пожаловать в Моя Ева Premium ✨', type: EvaSnackType.success);
      _close();
    } catch (serverError) {
      debugPrint("🔥 Ошибка Firebase Cloud Function: $serverError");
      if (!mounted) return;
      EvaSnack.show(
        context,
        "Оплата прошла, но подтверждение задерживается. Нажмите «Восстановить покупки» через пару минут.",
        type: EvaSnackType.info,
        duration: const Duration(seconds: 8),
      );
    }
  }

  Future<void> _processPayment() async {
    setState(() => _isLoading = true);
    try {
      final bool discount = _appliedPromo == 'SALE50';
      final String productId = _selectedPlan == 'month'
          ? (discount ? 'eva_sub_1_month_promo' : 'eva_sub_1_month')
          : (discount ? 'eva_sub_1_year_promo' : 'eva_sub_1_year');
      await _buySubscription(productId);
    } catch (e) {
      debugPrint("🔥 ОШИБКА ИНИЦИАЛИЗАЦИИ ПЛАТЕЖА: $e");
      if (mounted) EvaSnack.show(context, 'Системная ошибка: $e', type: EvaSnackType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    try {
      final bool ok = await SubscriptionService().restorePurchases();
      if (!mounted) return;
      if (ok) {
        EvaSnack.show(context, 'Покупки восстановлены ✨', type: EvaSnackType.success);
        _close();
      } else {
        EvaSnack.show(context, 'Активных подписок не найдено.', type: EvaSnackType.info);
      }
    } catch (e) {
      debugPrint("Ошибка восстановления: $e");
      if (mounted) {
        EvaSnack.show(context, 'Не удалось связаться с RuStore. Проверьте, что он установлен и VPN выключен.', type: EvaSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool discount = _appliedPromo == 'SALE50';
    final int price = (_selectedPlan == 'month' ? _basePriceMonth : _basePriceYear).toInt() ~/ (discount ? 2 : 1);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: EvaBackground(
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
                    child: EvaCircleButton(icon: Icons.close_rounded, size: 40, onTap: _close, tooltip: 'Закрыть'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    children: [
                      EvaOverline('Моя Ева Premium', color: context.eva.gold),
                      const SizedBox(height: 10),
                      Text('Забота о себе,\nа не строгие диеты', style: theme.textTheme.displaySmall),
                      const SizedBox(height: 10),
                      Text(
                        'Личный ИИ-нутрициолог и подруга: питание, женское здоровье и мотивация — без ругани за калории.',
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      _feature(theme, Icons.auto_awesome_rounded, 'Ева без ограничений', 'Чат, фото тарелки и рецепты — сколько угодно'),
                      _feature(theme, Icons.description_outlined, 'Расшифровка анализов', 'PDF с результатами — простым языком'),
                      _feature(theme, Icons.spa_outlined, 'Питание по фазе цикла', 'Меню, которое подстраивается под тебя'),
                      _feature(theme, Icons.insights_rounded, 'Итоги недели', 'Разбор привычек и персональные советы'),
                      const SizedBox(height: 22),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _planCard(theme, 'month', '1 месяц', _basePriceMonth, 590)),
                            const SizedBox(width: 12),
                            Expanded(child: _planCard(theme, 'year', '1 год', _basePriceYear, 3588, badge: 'Выгода 58%', note: '≈ 124 ₽ в месяц')),
                          ],
                        ),
                      ),
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
                      EvaPrimaryButton(
                        label: discount ? 'Оплатить со скидкой' : 'Начать 3 дня бесплатно',
                        loading: _isLoading,
                        onPressed: _processPayment,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '3 дня бесплатно, затем $price ₽ / ${_selectedPlan == 'month' ? 'месяц' : 'год'}. Отмена в любой момент в RuStore.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(onPressed: _isLoading ? null : _showPromoDialog, child: Text(_appliedPromo != null ? 'Промокод $_appliedPromo ✓' : 'Промокод')),
                          TextButton(onPressed: _isLoading ? null : _restorePurchases, child: const Text('Восстановить покупки')),
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse('https://docs.google.com/document/d/1GpHL1IbLlklUrKQ2jShjlNIrXd2V4V1H/edit?usp=sharing'),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text('Условия'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _feature(ThemeData theme, IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          EvaIconBubble(icon: icon, size: 42, iconSize: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 1),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(ThemeData theme, String planId, String title, double basePrice, double oldPrice, {String? badge, String? note}) {
    final bool selected = _selectedPlan == planId;
    final bool discount = _appliedPromo == 'SALE50';
    final int finalPrice = (discount ? basePrice / 2 : basePrice).toInt();
    final palette = context.eva;

    return EvaPressable(
      onTap: () => setState(() => _selectedPlan = planId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: selected ? palette.hero : null,
          color: selected ? null : palette.hairline,
          borderRadius: BorderRadius.circular(24),
          boxShadow: selected ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))] : null,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(22)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badge != null) ...[
                EvaPill(text: badge, color: palette.gold, solid: true),
                const SizedBox(height: 10),
              ] else
                const SizedBox(height: 32),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface)),
              const SizedBox(height: 6),
              Text(
                '${oldPrice.toInt()} ₽',
                style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
              ),
              Text('$finalPrice ₽', style: theme.textTheme.headlineLarge),
              if (note != null) ...[
                const SizedBox(height: 6),
                Text(note, style: theme.textTheme.labelMedium?.copyWith(color: palette.gold)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
