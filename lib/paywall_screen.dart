import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/dashboard_screen.dart'; 
import 'screens/auth_screen.dart'; 
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart'; // Добавляем наш сервис

class PaywallScreen extends StatefulWidget {
  final bool isFromProfile;
  
  const PaywallScreen({super.key, this.isFromProfile = false});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;
  String _selectedPlan = 'year'; 
  String? _appliedPromo; 

  static const Color _accentColor = Color(0xFFB76E79); 
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  final double _basePriceMonth = 199;
  final double _basePriceYear = 990;

  void _closePaywall() {
    if (widget.isFromProfile) {
      Navigator.pop(context);
    } else {
      // Если это онбординг - принудительный разлогин и возврат на вход
      FirebaseAuth.instance.signOut();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  void _applyPromoCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode == 'START3') {
      setState(() => _appliedPromo = cleanCode);
      Navigator.pop(context); 
      _processPayment(); 
    } else if (cleanCode == 'SALE50') {
      setState(() => _appliedPromo = cleanCode);
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Промокод на скидку 50% успешно применен! ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.teal,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Неверный промокод"), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showPromoDialog() {
    final TextEditingController promoController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Промокод", style: TextStyle(color: _textColor, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: promoController,
          style: const TextStyle(color: _textColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: "Введите код (START3, SALE50)",
            hintStyle: TextStyle(color: _subTextColor.withValues(alpha: 0.5), fontWeight: FontWeight.normal),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accentColor)),
          ),
          cursorColor: _accentColor,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Отмена", style: TextStyle(color: _subTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => _applyPromoCode(promoController.text),
            child: const Text("Применить", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment() async {
    setState(() => _isLoading = true);

    try {
      // === 1. ЛОГИКА ДЛЯ ПРОМОКОДА START3 (БЕСПЛАТНЫЙ ТРИАЛ) ===
      if (_appliedPromo == 'START3') {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          
          // НОВЫЙ КОД: Читаем профиль пользователя для проверки
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          final userData = userDoc.data() as Map<String, dynamic>? ?? {};
          final List<dynamic> usedPromos = userData['usedPromoCodes'] ?? [];

          // Если промокод уже использован - выдаем ошибку и останавливаем процесс
          if (usedPromos.contains('START3')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Вы уже использовали этот промокод 😔", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                  backgroundColor: Colors.redAccent
                ),
              );
              setState(() => _isLoading = false);
            }
            return; // СТОП!
          }

          // Если промокода нет - даем доступ и записываем код в базу
          final untilDate = DateTime.now().add(const Duration(days: 3));
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'isPro': true,
            'proUntil': Timestamp.fromDate(untilDate),
            'usedPromoCodes': FieldValue.arrayUnion(['START3']), // Навсегда сохраняем в профиль
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Добро пожаловать в премиум! ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Color(0xFFB76E79)),
          );
          if (widget.isFromProfile) {
            Navigator.pop(context);
          } else {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardScreen()));
          }
        }
        return; // Выходим отсюда, ЮKassa для триала не нужна.
      }

      // === 2. ЛОГИКА ДЛЯ ПЛАТНОЙ ПОДПИСКИ (ЮKASSA) ===
      double amount = _selectedPlan == 'month' ? _basePriceMonth : _basePriceYear;
      int days = _selectedPlan == 'month' ? 30 : 365;
      
      if (_appliedPromo == 'SALE50') amount = amount / 2;

      // Вызываем нашу облачную функцию
      final String? confirmationUrl = await DatabaseService().createYookassaPayment(
        amount: amount,
        description: 'Подписка MyEva Premium',
        paymentType: 'premium',
        durationDays: days,
      );

      if (confirmationUrl != null) {
        await launchUrl(Uri.parse(confirmationUrl), mode: LaunchMode.externalApplication);
        
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _WaitingPaymentDialog(isSpecialist: false, isFromProfile: widget.isFromProfile),
          );
        }
      } else {
        throw Exception("Бэкенд не вернул ссылку на оплату");
      }
    } catch (e) {
      debugPrint("🔥 ОШИБКА КАССЫ: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка бэкенда: $e', style: const TextStyle(fontSize: 12)), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String ctaText = "НАЧАТЬ ПРЕОБРАЖЕНИЕ";
    if (_appliedPromo == 'START3') ctaText = "Начать 3 дня бесплатно";
    if (_appliedPromo == 'SALE50') ctaText = "ОПЛАТИТЬ СО СКИДКОЙ";

    // ПЕРЕХВАТ КНОПКИ НАЗАД
    return PopScope(
      canPop: widget.isFromProfile, 
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closePaywall(); 
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F9F9),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: _textColor),
                  onPressed: _closePaywall, 
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "✨ Забота о себе,\nа не строгие диеты",
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _textColor, height: 1.2, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Твой личный ИИ-коуч и подруга. Поможет с питанием, женским здоровьем и мотивацией без ругани за калории.",
                        style: TextStyle(fontSize: 16, color: _subTextColor, height: 1.5, fontWeight: FontWeight.w500),
                      ),

                      const SizedBox(height: 32),

                      // ИСПРАВЛЕНЫ ИМЕНА ИКОНОК (auto_awesome, health_and_safety, support_agent)
                      _buildFeatureItem(Icons.auto_awesome, "Умный план питания", "Индивидуальное меню на основе анализов."),
                      _buildFeatureItem(Icons.health_and_safety, "Анализ симптомов", "Мгновенная расшифровка самочувствия."),
                      _buildFeatureItem(Icons.support_agent, "Поддержка 24/7", "Приоритетные ответы от специалистов."),

                      const SizedBox(height: 32),

                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPlanCard(
                              'month', 
                              '1 месяц', 
                              _basePriceMonth, 
                              oldPrice: 490
                            ),
                            const SizedBox(width: 16),
                            _buildPlanCard(
                              'year', 
                              '1 год', 
                              _basePriceYear, 
                              oldPrice: 2388, 
                              label: 'ВЫГОДА 58%', 
                              subtitle: 'Всего 82 ₽ в месяц!'
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      Center(
                        child: TextButton(
                          onPressed: _showPromoDialog,
                          child: Text(
                            _appliedPromo != null ? "Промокод $_appliedPromo применен" : "У меня есть промокод",
                            style: TextStyle(color: _appliedPromo != null ? Colors.teal : _subTextColor, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                          ),
                        ),
                      ),
                      
                      if (!widget.isFromProfile)
                        Center(
                          child: TextButton(
                            onPressed: _closePaywall, 
                            child: const Text(
                              "Уже есть аккаунт? Войти",
                              style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
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
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 32, offset: const Offset(0, -8))], 
                ),
                child: Container(
                  width: double.infinity,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_accentColor, Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _processPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(ctaText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _accentColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: _subTextColor, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String planId, String title, double basePrice, {double? oldPrice, String? label, String? subtitle}) {
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
            color: isSelected ? const Color(0xFFFDECE8) : Colors.white,
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(color: isSelected ? _accentColor : Colors.transparent, width: 2),
            boxShadow: [BoxShadow(color: isSelected ? _accentColor.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.04), blurRadius: 32, offset: const Offset(0, 8))], 
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (label != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                ),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: isSelected ? _accentColor : _subTextColor)),
              const SizedBox(height: 8),
              
              Text("${finalOldPrice.toInt()} ₽", style: const TextStyle(fontSize: 14, color: _subTextColor, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w600)),
              
              Text("${finalPrice.toInt()} ₽", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -1.0)),
              
              if (subtitle != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)
                  ),
                  child: Text(subtitle, style: const TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.w800)),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingPaymentDialog extends StatefulWidget {
  final bool isSpecialist;
  final bool isFromProfile;

  const _WaitingPaymentDialog({required this.isSpecialist, this.isFromProfile = false});

  @override
  State<_WaitingPaymentDialog> createState() => _WaitingPaymentDialogState();
}

class _WaitingPaymentDialogState extends State<_WaitingPaymentDialog> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
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
                Navigator.pop(context); // 1. Закрываем диалог ожидания
                if (widget.isFromProfile) {
                  Navigator.pop(context); // 2. Закрываем пейвол
                } else {
                  // ИСПРАВЛЕНИЕ: Безопасный переход на главный экран (без черного экрана)
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const DashboardScreen()),
                    (route) => false,
                  );
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Оплата успешно подтверждена! 🎉"), backgroundColor: Colors.green)
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
              Text("Мы проверяем статус платежа. Окно закроется автоматически после подтверждения транзакции."),
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
      }
    );
  }
}