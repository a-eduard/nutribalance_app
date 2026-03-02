import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/base_background.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  String _userRole = 'user'; // По умолчанию ставим 'user'
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          // Читаем роль. Если её нет, считаем, что это 'user'
          _userRole = doc.data()?['registeredRole'] ?? 'user';
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTariffCard({required String title, required String price, required String oldPrice, required List<String> features, required VoidCallback onBuy, bool isPopular = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPopular ? const Color(0xFF9CD600) : Colors.white10, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF9CD600), borderRadius: BorderRadius.circular(8)),
              child: const Text('ВЫГОДНО', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
            ),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: TextStyle(color: isPopular ? const Color(0xFF9CD600) : Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              if (oldPrice.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(oldPrice, style: const TextStyle(color: Colors.grey, fontSize: 16, decoration: TextDecoration.lineThrough)),
              ]
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF9CD600), size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(f, style: const TextStyle(color: Colors.white70, fontSize: 14))),
              ],
            ),
          )),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onBuy,
              style: ElevatedButton.styleFrom(
                backgroundColor: isPopular ? const Color(0xFF9CD600) : Colors.white10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Выбрать', style: TextStyle(color: isPopular ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _handleGoBack() async {
    if (Navigator.canPop(context)) {
      Navigator.pop(context); 
    } else {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFF9CD600))));

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleGoBack,
          ),
        ),
        body: SingleChildScrollView( 
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Открой все возможности\nTONNA", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
              const SizedBox(height: 8),
              const Text("ИИ-Ассистенты, умный трекинг и маркетплейс.", style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 32),

              // ИСПРАВЛЕНИЕ ЗДЕСЬ: Добавлена проверка на 'user'
              if (_userRole == 'athlete' || _userRole == 'user') ...[
                _buildTariffCard(
                  title: "Tonna AI Premium (Месяц)",
                  price: "499 ₽",
                  oldPrice: "",
                  features: [
                    "Безлимитный ИИ-Нутрициолог",
                    "Генерация программ от ИИ-Тренера",
                    "Доступ к Маркетплейсу тренеров",
                    "Умная аналитика прогресса"
                  ],
                  onBuy: () {}, 
                ),

                _buildTariffCard(
                  title: "Tonna AI Premium (Год)",
                  price: "3 990 ₽",
                  oldPrice: "5 988 ₽",
                  isPopular: true,
                  features: [
                    "Все функции подписки на месяц",
                    "Экономия 33% (2 месяца в подарок)",
                    "Приоритетная поддержка"
                  ],
                  onBuy: () {}, 
                ),
              ],

              if (_userRole == 'coach') ...[
                _buildTariffCard(
                  title: "Подписка Тренера",
                  price: "1 990 ₽ / мес",
                  oldPrice: "",
                  features: [
                    "Размещение в Маркетплейсе",
                    "Прием заявок от клиентов",
                    "Назначение тренировок клиентам",
                    "Доступ к дневникам клиентов"
                  ],
                  onBuy: () {}, 
                ),
                
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _handleGoBack,
                    child: const Text(
                      "Выйти и зарегистрироваться как Клиент", 
                      style: TextStyle(color: Colors.grey, decoration: TextDecoration.underline)
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}