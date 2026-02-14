import 'package:flutter/material.dart';
import '../services/coach_service.dart';
import 'coach_profile_screen.dart';
import 'dart:convert';
import 'public_coach_profile_screen.dart';

class CoachListScreen extends StatelessWidget {
  const CoachListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "НАЙТИ ТРЕНЕРА",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<Coach>>(
        stream: CoachService().getCoaches(),
        builder: (context, snapshot) {
          // 1. ОБРАБОТКА ОШИБОК
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 60,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка загрузки:\n${snapshot.error}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // 2. ОЖИДАНИЕ ДАННЫХ
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFCCFF00)),
            );
          }

          // 3. ПУСТОЙ СПИСОК
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 60,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Тренеров пока нет",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // 4. ОТРИСОВКА СПИСКА
          final coaches = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: coaches.length,
            itemBuilder: (context, index) {
              final coach = coaches[index];
              return _buildCoachCard(context, coach);
            },
          );
        },
      ),
    );
  }

  Widget _buildCoachCard(BuildContext context, Coach coach) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PublicCoachProfileScreen(coach: coach)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            // АВАТАРКА BASE64
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF1C1C1E),
              backgroundImage: (coach.photoUrl.isNotEmpty)
                  ? MemoryImage(base64Decode(coach.photoUrl))
                  : null,
              child: (coach.photoUrl.isEmpty)
                  ? const Icon(Icons.person, color: Colors.grey, size: 30)
                  : null,
            ),
            const SizedBox(width: 16),

            // Инфо
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coach.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    coach.specialization,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Color(0xFFCCFF00),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        coach.rating.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Цена
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  coach.price,
                  style: const TextStyle(
                    color: Color(0xFFCCFF00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "за сессию",
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
