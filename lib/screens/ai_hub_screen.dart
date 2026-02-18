import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'ai_workout_screen.dart';
import 'ai_chat_screen.dart';

class AiHubScreen extends StatelessWidget {
  const AiHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("ИИ АССИСТЕНТЫ", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildAiTile(
              context,
              title: "AI ТРЕНЕР",
              subtitle: "Создать персональный план тренировок",
              icon: Icons.bolt,
              color: const Color(0xFFCCFF00),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIWorkoutScreen())),
            ),
            const SizedBox(height: 16),
            _buildAiTile(
              context,
              title: "AI ДИЕТОЛОГ",
              subtitle: "План питания и расчет КБЖУ",
              icon: Icons.restaurant,
              color: Colors.white,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiTile(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }
}