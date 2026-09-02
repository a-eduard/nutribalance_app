// Файл: lib/paywall_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'screens/dashboard_screen.dart';

class PaywallScreen extends StatefulWidget {
  final bool isFromProfile;

  const PaywallScreen({super.key, this.isFromProfile = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;
  String _selectedPlan = 'month';
  String? _appliedPromo;

  final double _basePriceMonth = 299;
  final double _basePriceYear = 1490;

  // АРХИТЕКТУРНОЕ ИСПРАВЛЕНИЕ: Предотвращение утечки памяти
  late final TextEditingController _promoController;

  @override
  void initState() {
    super.initState();
    _promoController = TextEditingController();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  void _closePaywall() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _applyPromoCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);

    if (cleanCode == 'START3') {
      setState(() => _appliedPromo = cleanCode);
      nav.pop();
      _processPayment();
    } else if (cleanCode == 'SALE50EVA' || cleanCode == 'SALE50') {
      setState(() => _appliedPromo = 'SALE50');
      nav.pop();
      msg.showSnackBar(
        SnackBar(
          content: const Text(
            "Промокод активирован! Скидка 50% применена ✨",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } else {
      msg.showSnackBar(
        const SnackBar(
          content: Text("Неверный промокод"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showPromoDialog() {
    final theme = Theme.of(context);
    _promoController.clear(); // Очищаем поле при каждом новом открытии
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          "Промокод",
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: _promoController,
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: "Введите код (START3, SALE50)",
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontWeight: FontWeight.normal,
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
          cursorColor: theme.colorScheme.primary,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Отмена", style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => _applyPromoCode(_promoController.text),
            child: Text(
              "Применить",
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buySubscription(String productId, int daysToAdd) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    String pToken = '';

    // БЛОК 1: Нативная покупка (RuStore)
    try {
      final purchaseResult = await RustoreBillingClient.purchase(
        productId,
        user.uid,
      );

      if (purchaseResult.successPurchase == null) {
        debugPrint("Оплата отменена пользователем или не удалась на устройстве.");
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      pToken = purchaseResult.successPurchase!.purchaseId ?? '';
      
    } catch (nativeError) {
      debugPrint("🔥 Ошибка SDK RuStore: $nativeError");
      if (mounted) {
        final errorText = nativeError.toString().toLowerCase();
        
        if (errorText.contains('already') || 
            errorText.contains('purchased') || 
            errorText.contains('owned') || 
            errorText.contains('приобретен')) {
          
          msg.showSnackBar(
            SnackBar(
              content: const Text(
                "Подписка уже активна! Пытаемся восстановить доступ... ✨",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: theme.colorScheme.primary,
              duration: const Duration(seconds: 4),
            ),
          );
          _restorePurchases();
        } else {
          msg.showSnackBar(
            const SnackBar(
              content: Text(
                "Оплата отменена или магазин не найден",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() => _isLoading = false);
        }
      }
      return; // Прерываем выполнение, если нативная оплата провалилась
    }

    // БЛОК 2: Серверная валидация (Firebase Cloud Functions)
    // Выполняется ТОЛЬКО если RuStore успешно списал деньги (выдал токен)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyRuStorePurchase');
      await callable.call({'productId': productId, 'purchaseToken': pToken});

      if (mounted) {
        msg.showSnackBar(
          SnackBar(
            content: const Text(
              "Оплата прошла успешно! Добро пожаловать в Моя Ева Премиум ✨",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: theme.colorScheme.primary,
          ),
        );

        if (widget.isFromProfile) {
          nav.pop();
        } else {
          nav.pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        }
      }
    } catch (serverError) {
      debugPrint("🔥 Ошибка Firebase Cloud Function: $serverError");
      if (mounted) {
        // Мы НЕ говорим пользователю "Ошибка оплаты", потому что деньги уже списаны!
        msg.showSnackBar(
          const SnackBar(
            content: Text(
              "Оплата прошла, но серверная проверка задерживается. Пожалуйста, нажмите 'Восстановить покупки' через пару минут.",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _processPayment() async {
    setState(() => _isLoading = true);
    
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);

    try {
      if (_appliedPromo == 'START3') {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final userData = userDoc.data() ?? {};
          final List<dynamic> usedPromos = userData['usedPromoCodes'] ?? [];

          if (usedPromos.contains('START3')) {
            if (mounted) {
              msg.showSnackBar(
                const SnackBar(
                  content: Text(
                    "Вы уже использовали этот промокод 😔",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
              setState(() => _isLoading = false);
            }
            return;
          }

          final untilDate = DateTime.now().add(const Duration(days: 3));
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
                'isPro': true,
                'proUntil': Timestamp.fromDate(untilDate),
                'usedPromoCodes': FieldValue.arrayUnion(['START3']),
              });
        }

        if (mounted) {
          msg.showSnackBar(
            SnackBar(
              content: const Text(
                "Промокод активирован! Премиум доступен ✨",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
          if (widget.isFromProfile) {
            nav.pop();
          } else {
            nav.pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );
          }
        }
        return;
      }

      bool hasDiscount = _appliedPromo == 'SALE50';

      String monthProductId = hasDiscount
          ? 'eva_sub_1_month_promo'
          : 'eva_sub_1_month';
      String yearProductId = hasDiscount
          ? 'eva_sub_1_year_promo'
          : 'eva_sub_1_year';

      if (_selectedPlan == 'month') {
        await _buySubscription(monthProductId, 30);
      } else if (_selectedPlan == 'year') {
        await _buySubscription(yearProductId, 365);
      }
    } catch (e) {
      debugPrint("🔥 ОШИБКА ИНИЦИАЛИЗАЦИИ ПЛАТЕЖА: $e");
      if (mounted) {
        msg.showSnackBar(
          SnackBar(
            content: Text(
              'Системная ошибка: $e',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => _isLoading = true);
    
    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await RustoreBillingClient.purchases();
      final purchasesList = response.purchases; 

      bool hasActiveSub = false;

      for (var p in purchasesList) {
        if (p == null) continue; 
        final stateStr = p.purchaseState?.toString().toUpperCase() ?? '';
        if (stateStr.contains('PAID') ||
            stateStr.contains('CONFIRMED') ||
            stateStr.contains('COMPLETED')) {
          
          String pToken = p.purchaseId ?? "";
          String pId = p.productId ?? "";

          if (pToken.isNotEmpty) {
            try {
              final callable = FirebaseFunctions.instance.httpsCallable('verifyRuStorePurchase');
              await callable.call({'productId': pId, 'purchaseToken': pToken});
              hasActiveSub = true;
            } catch (cfError) {
              debugPrint("🔥 Ошибка восстановления чека $pToken: $cfError");
              // Продолжаем цикл: если серверов RuStore (502) не отвечает на один чек, 
              // попытаемся восстановить другие, не краша весь процесс.
            }
          }
        }
      }

      if (hasActiveSub) {
        if (mounted) {
          msg.showSnackBar(
            SnackBar(
              content: const Text(
                "Покупки успешно восстановлены! ✨",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: theme.colorScheme.primary,
            ),
          );
          if (widget.isFromProfile) {
            nav.pop();
          } else {
            nav.pushReplacement(
              MaterialPageRoute(builder: (_) => const DashboardScreen()),
            );
          }
        }
      } else {
        if (mounted) {
          msg.showSnackBar(
            const SnackBar(
              content: Text(
                "Сервер временно недоступен или активных подписок нет.",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Ошибка нативного восстановления: $e");
      if (mounted) {
        msg.showSnackBar(
          const SnackBar(
            content: Text(
              "Ошибка при связи с магазином на устройстве",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    String ctaText = "НАЧАТЬ ПРЕОБРАЖЕНИЕ";
    if (_appliedPromo == 'START3') ctaText = "Начать 3 дня бесплатно";
    if (_appliedPromo == 'SALE50') ctaText = "ОПЛАТИТЬ СО СКИДКОЙ";

    return PopScope(
      canPop: widget.isFromProfile,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closePaywall();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0, top: 8.0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 24,
                    ), 
                    onPressed: _closePaywall,
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "✨ Забота о себе,\nа не строгие диеты",
                        style: TextStyle(
                          fontSize: 28, 
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.onSurface,
                          height: 1.1, 
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8), 
                      Text(
                        "Твой личный ИИ-коуч и подруга. Поможет с питанием, женским здоровьем и мотивацией без ругани за калории.",
                        style: TextStyle(
                          fontSize: 14, 
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 16), 
                      
                      _buildFeatureItem(
                        Icons.auto_awesome,
                        "Умный план питания",
                        "Индивидуальное меню на основе анализов.",
                        theme,
                      ),
                      _buildFeatureItem(
                        Icons.health_and_safety,
                        "Анализ симптомов",
                        "Мгновенная расшифровка самочувствия.",
                        theme,
                      ),
                      _buildFeatureItem(
                        Icons.support_agent,
                        "Поддержка 24/7",
                        "Приоритетные ответы от специалистов.",
                        theme,
                      ),

                      const SizedBox(height: 16), 

                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPlanCard(
                              'month',
                              '1 месяц',
                              _basePriceMonth,
                              theme,
                              oldPrice: 590,
                            ),
                            const SizedBox(width: 16),
                            _buildPlanCard(
                              'year',
                              '1 год',
                              _basePriceYear,
                              theme,
                              oldPrice: 3588,
                              label: 'ВЫГОДА 58%',
                              subtitle: 'Всего 124 ₽ в месяц!',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      if (!widget.isFromProfile)
                        Center(
                          child: TextButton(
                            onPressed: _closePaywall,
                            child: Text(
                              "Уже есть аккаунт? Войти",
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
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
                    Container(
                      width: double.infinity,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _processPayment,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
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
                                ctaText,
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedPlan == 'month'
                          ? "3 дня бесплатно, затем ${(_appliedPromo == 'SALE50' ? _basePriceMonth / 2 : _basePriceMonth).toInt()} ₽ / месяц"
                          : "3 дня бесплатно, затем ${(_appliedPromo == 'SALE50' ? _basePriceYear / 2 : _basePriceYear).toInt()} ₽ / год",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7), 
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _showPromoDialog,
                      child: Text(
                        _appliedPromo != null
                            ? "Промокод $_appliedPromo применен"
                            : "У меня есть промокод",
                        style: TextStyle(
                          color: _appliedPromo != null
                              ? Colors.teal
                              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: _appliedPromo != null
                              ? Colors.teal
                              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _isLoading ? null : _restorePurchases,
                      child: Text(
                        "Восстановить покупки",
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
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
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0), 
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8), 
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10), 
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 20,
            ), 
          ),
          const SizedBox(width: 12), 
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    String planId,
    String title,
    double basePrice,
    ThemeData theme, {
    double? oldPrice,
    String? label,
    String? subtitle,
  }) {
    bool isSelected = _selectedPlan == planId;
    bool hasDiscount = _appliedPromo == 'SALE50';

    double finalPrice = hasDiscount ? basePrice / 2 : basePrice;
    double finalOldPrice = oldPrice ?? (basePrice * 2.5);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlan = planId),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (label != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15, 
                  fontWeight: FontWeight.w800,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4), 

              Text(
                "${finalOldPrice.toInt()} ₽",
                style: TextStyle(
                  fontSize: 13, 
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                  fontWeight: FontWeight.w600,
                ),
              ),

              Text(
                "${finalPrice.toInt()} ₽",
                style: TextStyle(
                  fontSize: 26, 
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -1.0,
                ),
              ),

              if (subtitle != null) ...[
                const SizedBox(height: 8), 
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}