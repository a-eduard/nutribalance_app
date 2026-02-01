import 'package:flutter/material.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  // 0 = Годовая (по умолчанию), 1 = Месячная
  int _selectedPlanIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Цвета из нашей дизайн-системы
    const neonLime = Color(0xFFCCFF00);
    const surfaceColor = Color(0xFF1E1E1E);
    const secondaryText = Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Кнопка закрытия и Заголовок
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40), // Для центровки заголовка
                  const Text(
                    "PREMIUM",
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: neonLime,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 2. Список преимуществ (кратко)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, size: 60, color: neonLime),
                    const SizedBox(height: 24),
                    Text(
                      "РАЗБЛОКИРУЙ СВОЙ\nПОТЕНЦИАЛ",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold, height: 1.1),
                    ),
                    const SizedBox(height: 32),
                    _buildBenefitRow("Безлимитное создание тренировок"),
                    _buildBenefitRow("Расширенная статистика прогресса"),
                    _buildBenefitRow("Доступ ко всем упражнениям"),
                  ],
                ),
              ),
            ),

            // 3. Карточки Цен
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  // --- КАРТОЧКА 1: ГОДОВАЯ (BEST VALUE) ---
                  GestureDetector(
                    onTap: () => setState(() => _selectedPlanIndex = 0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: surfaceColor,
                            // Если выбран - рамка Neon Lime, иначе прозрачная
                            border: Border.all(
                              color: _selectedPlanIndex == 0
                                  ? neonLime
                                  : Colors.transparent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "1 ГОД",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "1 990 ₽",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              // Цена в месяц (расчет)
                              Text(
                                "166 ₽ / месяц",
                                style: TextStyle(
                                  color: neonLime,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Списывается раз в год. Экономия 45%",
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Плашка "ВЫГОДНО"
                        Positioned(
                          top: -12,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: neonLime,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              "ВЫГОДНО",
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- КАРТОЧКА 2: МЕСЯЧНАЯ ---
                  GestureDetector(
                    onTap: () => setState(() => _selectedPlanIndex = 1),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        border: Border.all(
                          color: _selectedPlanIndex == 1
                              ? neonLime
                              : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "1 МЕСЯЦ",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Списывается ежемесячно",
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "299 ₽",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 4. Кнопка CTA (Меняет текст)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ElevatedButton(
                onPressed: () {
                  // Логика покупки
                  final planName = _selectedPlanIndex == 0
                      ? "Годовая"
                      : "Месячная";
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Выбрана подписка: $planName')),
                  );
                },
                child: Text(
                  _selectedPlanIndex == 0
                      ? "ПОПРОБОВАТЬ ЗА 1 990 ₽"
                      : "ПОПРОБОВАТЬ ЗА 299 ₽",
                ),
              ),
            ),

            // 5. Footer (Юридический текст)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Подписка продлевается автоматически. Отмена в любой момент в настройках Apple ID / Google Play.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check, color: Color(0xFFCCFF00), size: 20),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 16, color: Colors.white)),
        ],
      ),
    );
  }
}
