import 'package:flutter/material.dart';
import 'ai_chat_screen.dart';

class AiSelectionScreen extends StatelessWidget {
  const AiSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("ИИ АССИСТЕНТЫ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildBotCard(
              context,
              title: "ИИ-Тренер",
              subtitle: "Составит программу тренировок, проанализирует технику, адаптирует упражнения под ваши травмы.",
              icon: Icons.fitness_center,
              color: const Color(0xFFCCFF00),
              botType: 'trainer',
            ),
            const SizedBox(height: 20),
            _buildBotCard(
              context,
              title: "ИИ-Нутрициолог",
              subtitle: "Персональный план питания, расчет КБЖУ, разбор анализов и советы по спортивным добавкам.",
              icon: Icons.health_and_safety,
              color: const Color(0xFF00E5FF),
              botType: 'dietitian',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required String botType}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context, 
          MaterialPageRoute(builder: (_) => AIChatScreen(botType: botType))
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 36),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}