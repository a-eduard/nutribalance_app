import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/coach_service.dart'; // Путь к модели Coach
import '../services/database_service.dart'; // Путь к сервису базы данных

class PublicCoachProfileScreen extends StatefulWidget {
  final Coach coach;

  const PublicCoachProfileScreen({super.key, required this.coach});

  @override
  State<PublicCoachProfileScreen> createState() => _PublicCoachProfileScreenState();
}

class _PublicCoachProfileScreenState extends State<PublicCoachProfileScreen> {

  // МЕТОД ПОКАЗА ДИАЛОГА ОЦЕНКИ
  void _showRatingDialog(BuildContext context) {
    int selectedStars = 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("ОЦЕНИТЕ ТРЕНЕРА", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Пожалуйста, поставьте оценку от 1 до 5 звезд.", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < selectedStars ? Icons.star : Icons.star_border,
                          color: const Color(0xFFCCFF00),
                          size: 36,
                        ),
                        onPressed: () {
                          setStateDialog(() => selectedStars = index + 1);
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("ОТМЕНА", style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    if (selectedStars == 0) return;
                    Navigator.pop(ctx);
                    await _submitRating(selectedStars);
                  },
                  child: const Text("ОТПРАВИТЬ", style: TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ТРАНЗАКЦИЯ В FIRESTORE
  Future<void> _submitRating(int selectedStars) async {
    final coachRef = FirebaseFirestore.instance.collection('coaches').doc(widget.coach.id);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(coachRef);
        if (!snapshot.exists) return;

        double currentRating = (snapshot.data()?['rating'] ?? 5.0).toDouble();
        int count = snapshot.data()?['ratingCount'] ?? 0;

        // Высчитываем новое среднее значение
        double newRating = ((currentRating * count) + selectedStars) / (count + 1);

        transaction.update(coachRef, {
          'rating': newRating,
          'ratingCount': count + 1,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Спасибо за оценку!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFFCCFF00),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true, // ВАЖНО: AppBar поверх контента
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ВЕРХНИЙ БЛОК: ФОТОГРАФИЯ
            Container(
              width: double.infinity,
              height: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                image: (widget.coach.photoUrl.isNotEmpty)
                    ? DecorationImage(
                        image: MemoryImage(base64Decode(widget.coach.photoUrl)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (widget.coach.photoUrl.isEmpty)
                  ? const Icon(Icons.person, size: 100, color: Colors.grey)
                  // Градиент для плавного перехода фото в черный фон
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                            Colors.black,
                          ],
                        ),
                      ),
                    ),
            ),

            // ИНФОРМАЦИОННЫЙ БЛОК
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.coach.name,
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.coach.specialization.toUpperCase(),
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 16),

                  // РЕЙТИНГ
                  Row(
                    children: [
                      const Icon(Icons.star, color: Color(0xFFCCFF00), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        widget.coach.rating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "(${widget.coach.ratingCount} оценок)",
                        style: const TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  const Text("О СЕБЕ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  Text(
                    widget.coach.bio.isEmpty ? "Тренер пока не добавил информацию о себе." : widget.coach.bio,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                  
                  const SizedBox(height: 32),
                  const Text("СТОИМОСТЬ", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  Text(
                    widget.coach.price,
                    style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  
                  const SizedBox(height: 40),

                  // КНОПКИ ВНИЗУ
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        await DatabaseService().connectWithCoach(widget.coach.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Заявка успешно отправлена тренеру!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              backgroundColor: Color(0xFFCCFF00),
                              behavior: SnackBarBehavior.floating,
                            )
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCCFF00),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("НАЧАТЬ РАБОТУ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => _showRatingDialog(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1C1C1E), width: 2),
                        backgroundColor: const Color(0xFF1C1C1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("ОЦЕНИТЬ ТРЕНЕРА", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.0)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}