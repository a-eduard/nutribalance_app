import 'package:flutter/material.dart';
// ВОЗВРАЩЕНО: Импорт экрана чата
import '../../screens/ai_chat_screen.dart';

class AIAssistantsCard extends StatelessWidget {
  final bool isPro;
  const AIAssistantsCard({super.key, required this.isPro});

  Widget _buildActionCard(BuildContext context, {required String title, required String imagePath, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          // ДИЗАЙН СОХРАНЕН: Единый лаймовый стиль для всех карточек ИИ
          border: Border.all(color: const Color(0xFF9CD600).withValues(alpha: 0.3), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(imagePath, width: 32, height: 32, fit: BoxFit.contain),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  // ДИЗАЙН СОХРАНЕН: Текст белый
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), 
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ДИЗАЙН СОХРАНЕН: Заголовок лаймовый
        const Text('ИИ-АССИСТЕНТЫ', style: TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                title: 'Питание',
                imagePath: 'assets/icons/ai_dietitian.png',
                onTap: () {
                  if (isPro) {
                    // ВОЗВРАЩЕНО: Навигация к ИИ-нутрициологу
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
                  } else {
                    Navigator.pushNamed(context, '/paywall'); 
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                title: 'Тренер',
                imagePath: 'assets/icons/ai_trainer.png',
                onTap: () {
                  if (isPro) {
                    // ВОЗВРАЩЕНО: Навигация к ИИ-тренеру
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'trainer')));
                  } else {
                    Navigator.pushNamed(context, '/paywall'); 
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}