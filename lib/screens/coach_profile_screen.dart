import 'package:flutter/material.dart';
import '../services/coach_service.dart';
import '../services/database_service.dart'; // ИМПОРТ НУЖЕН ДЛЯ connectWithCoach
import 'p2p_chat_screen.dart';

class CoachProfileScreen extends StatelessWidget {
  final Coach coach;

  const CoachProfileScreen({super.key, required this.coach});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("ПРОФИЛЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Большое фото
            Container(
              width: double.infinity,
              height: 300,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                image: coach.photoUrl.isNotEmpty
                    ? DecorationImage(image: NetworkImage(coach.photoUrl), fit: BoxFit.cover)
                    : null,
              ),
              child: coach.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 100) : null,
            ),
            
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(coach.name, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900))),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Color(0xFFCCFF00), size: 24),
                          const SizedBox(width: 4),
                          Text(coach.rating.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(coach.specialization.toUpperCase(), style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  
                  const SizedBox(height: 24),
                  const Text("О ТРЕНЕРЕ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Text(
                    coach.bio.isEmpty ? "Информация отсутствует." : coach.bio,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                  
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Стоимость сессии:", style: TextStyle(color: Colors.grey, fontSize: 14)),
                      Text(coach.price, style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Кнопка Написать
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFCCFF00).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => P2PChatScreen(otherUserId: coach.id, otherUserName: coach.name),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCCFF00),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("НАПИСАТЬ СООБЩЕНИЕ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // НОВАЯ КНОПКА: Начать работу
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () async {
                        await DatabaseService().connectWithCoach(coach.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Заявка отправлена тренеру!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              backgroundColor: Color(0xFFCCFF00),
                              behavior: SnackBarBehavior.floating,
                            )
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCCFF00), width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("НАЧАТЬ РАБОТУ", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}