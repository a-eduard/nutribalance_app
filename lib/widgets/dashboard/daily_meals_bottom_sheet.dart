import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/database_service.dart';

class DailyMealsBottomSheet extends StatelessWidget {
  const DailyMealsBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // ФИКС ТЕМЫ: Светлый премиум фон
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)), // Глубокое скругление
      ),
      builder: (context) => const DailyMealsBottomSheet(),
    );
  }

  void _showEditWeightDialog(BuildContext context, Map<String, dynamic> item) {
    final TextEditingController weightController = TextEditingController(
      text: item['weight_g'].toString(),
    );
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Colors.white, // Светлая тема диалога
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text(
              'Изменить порцию',
              style: TextStyle(
                color: Color(0xFF2D2D2D), // Темно-серый текст
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    color: Color(0xFFB76E79), // Rose Gold
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Color(0xFF2D2D2D),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Вес (граммы)',
                    labelStyle: TextStyle(color: Color(0xFF8E8E93)),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFE5E5EA)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFB76E79), width: 2),
                    ),
                    suffixText: 'г',
                    suffixStyle: TextStyle(color: Color(0xFF2D2D2D), fontSize: 20),
                  ),
                  cursorColor: const Color(0xFFB76E79),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB76E79),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final newWeight = int.tryParse(weightController.text.trim());
                        if (newWeight != null && newWeight > 0) {
                          setStateDialog(() => isSaving = true);
                          try {
                            await DatabaseService().updateMealItemWeight(item, newWeight);
                            if (context.mounted) Navigator.pop(ctx); 
                          } catch (e) {
                            setStateDialog(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85, 
      child: Column(
        children: [
          // Элегантный ползунок сверху
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Дневник питания",
                style: TextStyle(
                  color: Color(0xFF2D2D2D),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: DatabaseService().getTodayMealsDoc(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFB76E79)),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant_menu, size: 64, color: const Color(0xFF8E8E93).withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          "Дневник пуст",
                          style: TextStyle(color: Color(0xFF2D2D2D), fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Отправь Еве фото своей еды,\nчтобы записать первый прием",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final List<dynamic> items = data['items'] ?? [];

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant_menu, size: 64, color: const Color(0xFF8E8E93).withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          "Дневник пуст",
                          style: TextStyle(color: Color(0xFF2D2D2D), fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Отправь Еве фото своей еды,\nчтобы записать первый прием",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 40),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;

                    return Dismissible(
                      key: Key(item['id'] ?? index.toString()),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.1), // Нежный красный фон для удаления
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                      ),
                      onDismissed: (_) {
                      // Даем методу ту самую дату (сегодняшнюю), чтобы он знал, где искать блюдо
                      final String todayDocId = DatabaseService().getTodayDocId();
                      DatabaseService().deleteMealItem(item, todayDocId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Блюдо удалено из дневника ✨', style: TextStyle(fontWeight: FontWeight.bold)),
                            backgroundColor: Colors.teal,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: GestureDetector(
                        onTap: () => _showEditWeightDialog(context, item),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 4))],
                            border: Border.all(color: const Color(0xFFB76E79).withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] ?? 'Блюдо',
                                      style: const TextStyle(
                                        color: Color(0xFF2D2D2D),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Б: ${item['protein']}г  •  Ж: ${item['fat']}г  •  У: ${item['carbs']}г",
                                      style: const TextStyle(
                                        color: Color(0xFF8E8E93),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "${item['calories']} ккал",
                                    style: const TextStyle(
                                      color: Color(0xFFB76E79),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.5
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F2F7),
                                      borderRadius: BorderRadius.circular(8)
                                    ),
                                    child: Text(
                                      "${item['weight_g']} г",
                                      style: const TextStyle(
                                        color: Color(0xFF8E8E93),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}