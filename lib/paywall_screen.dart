import 'package:flutter/material.dart';
import '../services/database_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _isLoading = false;
  
  static const Color _accentColor = Color(0xFFB76E79); // Rose Gold
  static const Color _textColor = Color(0xFF2D2D2D);

  Future<void> _startTrial() async {
    setState(() => _isLoading = true);
    try {
      // Активируем пробный период на 7 дней
      await DatabaseService().activateTrial(7);
      
      if (!mounted) return;
      Navigator.pop(context); // Закрываем экран оплаты
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✨ Подписка активирована! Добро пожаловать в премиум.", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: _accentColor,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Произошла ошибка. Попробуйте позже.')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9), // Светлый фон
      body: SafeArea(
        child: Column(
          children: [
            // Кнопка закрытия (крестик) в правом верхнем углу
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    // Заголовок
                    const Text(
                      "✨ Обрети гармонию\nс телом",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: _textColor,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Подзаголовок
                    const Text(
                      "Твой личный ИИ-нутрициолог, который заботится о тебе, а не ругает за калории.",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Блок преимуществ
                    _buildFeatureItem(
                      emoji: "🌸",
                      title: "Питание по фазам цикла",
                      description: "Ева адаптирует твой рацион под гормональный фон. Больше никакой борьбы с организмом.",
                    ),
                    _buildFeatureItem(
                      emoji: "🧘‍♀️",
                      title: "Без чувства вины и стресса",
                      description: "Мы убрали красные полоски. Если ты съела десерт — мы просто мягко сбалансируем завтрашний день.",
                    ),
                    _buildFeatureItem(
                      emoji: "🥑",
                      title: "Магия холодильника",
                      description: "Сфоткай полку с продуктами — Ева придумает быстрый и полезный рецепт за 5 секунд.",
                    ),
                    _buildFeatureItem(
                      emoji: "🩺",
                      title: "Чтение твоих анализов",
                      description: "Загрузи результаты анализов (PDF/фото), и Ева поможет восполнить дефициты витаминов через еду.",
                    ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Закрепленный подвал с кнопкой и текстом
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Кнопка CTA
                  Container(
                    width: double.infinity,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_accentColor, Color(0xFFD49A89)], // Rose Gold градиент
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _startTrial,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text(
                            "НАЧАТЬ ПРЕОБРАЖЕНИЕ\n(7 дней бесплатно)",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                              height: 1.2
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Мелкий текст под кнопкой
                  const Text(
                    "Далее 490 ₽ в месяц. Отмени в любой момент.",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  // Виджет для одного буллита
  Widget _buildFeatureItem({required String emoji, required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Иконка
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFDECE8), // Очень нежный персиковый фон
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 16),
          // Текст
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
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
}