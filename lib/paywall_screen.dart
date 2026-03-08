import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/home_wrapper.dart'; 

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

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

  final double _basePriceMonth = 490;
  final double _basePriceYear = 2990;

  void _closePaywall() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeWrapper()),
      (route) => false,
    );
  }

  void _applyPromoCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode == 'START3' || cleanCode == 'SALE50') {
      setState(() => _appliedPromo = cleanCode);
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Промокод успешно применен! ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Future<void> _processMockPayment() async {
    setState(() => _isLoading = true);

    try {
      await Future.delayed(const Duration(seconds: 2));

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final db = FirebaseFirestore.instance;
        Map<String, dynamic> updates = {'isPro': true};

        DateTime untilDate = DateTime.now();
        if (_appliedPromo == 'START3') {
          untilDate = untilDate.add(const Duration(days: 3));
        } else if (_selectedPlan == 'month') {
          untilDate = untilDate.add(const Duration(days: 30));
        } else if (_selectedPlan == 'year') {
          untilDate = untilDate.add(const Duration(days: 365));
        }
        updates['proUntil'] = Timestamp.fromDate(untilDate);

        await db.collection('users').doc(user.uid).update(updates);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Оплата прошла успешно! Добро пожаловать в премиум ✨", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: _accentColor,
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeWrapper()), (route) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Произошла ошибка при оплате'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String ctaText = "НАЧАТЬ ПРЕОБРАЖЕНИЕ";
    if (_appliedPromo == 'START3') ctaText = "Начать 3 дня бесплатно";
    if (_appliedPromo == 'SALE50') ctaText = "ОПЛАТИТЬ СО СКИДКОЙ";

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFC7C7CC)),
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
                      "✨ Обрети гармонию\nс телом",
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _textColor, height: 1.2, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Твой личный ИИ-нутрициолог, который заботится о тебе, а не ругает за калории.",
                      style: TextStyle(fontSize: 16, color: _subTextColor, height: 1.5, fontWeight: FontWeight.w500),
                    ),

                    const SizedBox(height: 40),

                    _buildFeatureItem("🌸", "Питание по фазам цикла"),
                    _buildFeatureItem("🧘‍♀️", "Без чувства вины и стресса"),
                    _buildFeatureItem("🥑", "Рецепты по фото из холодильника"),
                    _buildFeatureItem("🩺", "Анализ твоих дефицитов и витаминов"),

                    const SizedBox(height: 40),

                    Row(
                      children: [
                        _buildPlanCard('month', '1 месяц', _basePriceMonth),
                        const SizedBox(width: 16),
                        _buildPlanCard('year', '1 год', _basePriceYear, label: 'ВЫГОДНО'),
                      ],
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
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, -8))],
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
                  onPressed: _isLoading ? null : _processMockPayment,
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
    );
  }

  Widget _buildFeatureItem(String emoji, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(16)),
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 20),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor))),
        ],
      ),
    );
  }

  Widget _buildPlanCard(String planId, String title, double basePrice, {String? label}) {
    bool isSelected = _selectedPlan == planId;
    bool hasDiscount = _appliedPromo == 'SALE50';
    double finalPrice = hasDiscount ? basePrice / 2 : basePrice;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlan = planId),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFDECE8) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isSelected ? _accentColor : Colors.transparent, width: 2),
            boxShadow: [BoxShadow(color: isSelected ? _accentColor.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _accentColor, borderRadius: BorderRadius.circular(10)),
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                ),
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isSelected ? _accentColor : _subTextColor)),
              const SizedBox(height: 8),
              if (hasDiscount) 
                Text("${basePrice.toInt()} ₽", style: const TextStyle(fontSize: 14, color: _subTextColor, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w600)),
              Text("${finalPrice.toInt()} ₽", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: _textColor, letterSpacing: -1.0)),
            ],
          ),
        ),
      ),
    );
  }
}