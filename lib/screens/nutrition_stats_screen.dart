import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/database_service.dart';
import 'ai_chat_screen.dart';

class NutritionStatsScreen extends StatefulWidget {
  const NutritionStatsScreen({super.key});

  @override
  State<NutritionStatsScreen> createState() => _NutritionStatsScreenState();
}

class _NutritionStatsScreenState extends State<NutritionStatsScreen> {
  String _selectedPeriod = 'day';

  String _getAIDietitianInsight(int maintenance, int consumed, int diff) {
    if (consumed == 0)
      return "Привет! Запиши свой первый прием пищи, и я посчитаю твой дефицит. 🍏";
    if (maintenance == 0)
      return "Попроси меня рассчитать твою норму калорий, чтобы я смог анализировать твой дефицит! 🤖";
    if (diff > 0)
      return "Супер! Твой дефицит составил $diff ккал от нормы поддержания. Жир горит, ты на верном пути! 🔥";
    if (diff == 0)
      return "Идеальный баланс! Ты питаешься ровно на поддержание веса. ⚖️";
    return "Внимание! Профицит ${diff.abs()} ккал. Если ты на массе — отличная работа! Если сушишься, стоит урезать угли. 💪";
  }

  void _showEditWeightDialog(BuildContext context, Map<String, dynamic> item) {
    final TextEditingController weightController = TextEditingController(
      text: item['weight_g'].toString(),
    );
    bool isSaving = false; // Состояние загрузки

    showDialog(
      context: context,
      barrierDismissible: false, // Запрещаем закрывать, пока идет сохранение
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2C2C2E),
            title: const Text(
              'Изменить порцию',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    color: Color(0xFFB76E79),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Вес (граммы)',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFB76E79)),
                    ),
                    suffixText: 'г',
                    suffixStyle: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text(
                  'Отмена',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB76E79),
                  foregroundColor: Colors.black,
                ),
                onPressed: isSaving
                    ? null
                    : () async {
                        final newWeight = int.tryParse(
                          weightController.text.trim(),
                        );
                        if (newWeight != null && newWeight > 0) {
                          setStateDialog(() => isSaving = true);
                          try {
                            // Ждем завершения транзакции
                            await DatabaseService().updateMealItemWeight(
                              item,
                              newWeight,
                            );
                            if (context.mounted)
                              Navigator.pop(ctx); // Закрываем только при успехе
                          } catch (e) {
                            setStateDialog(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Ошибка: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Сохранить',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: Colors.black);

    // QA FIX: Обернули в DefaultTabController для 2 вкладок
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            'Дневник питания',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1C1C1E),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            indicatorColor: Color(0xFFB76E79),
            labelColor: Color(0xFFB76E79),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'РАЦИОН'),
              Tab(text: 'СТАТИСТИКА'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildRationTab(uid), _buildStatsTab(uid)]),
      ),
    );
  }

  // ==========================================
  // Вкладка 1: РАЦИОН (Список еды)
  // ==========================================
  Widget _buildRationTab(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: DatabaseService().getTodayMealsDoc(),
      builder: (context, todaySnap) {
        if (todaySnap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFB76E79)),
          );
        }

        if (!todaySnap.hasData || !todaySnap.data!.exists) {
          return const Center(
            child: Text(
              "Вы еще ничего не записали сегодня",
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final data = todaySnap.data!.data() as Map<String, dynamic>;
        final List<dynamic> items = data['items'] ?? [];

        final int totalCals = (data['calories'] as num?)?.toInt() ?? 0;
        final int totalP = (data['protein'] as num?)?.toInt() ?? 0;
        final int totalF = (data['fat'] as num?)?.toInt() ?? 0;
        final int totalC = (data['carbs'] as num?)?.toInt() ?? 0;

        if (items.isEmpty) {
          return const Center(
            child: Text("Дневник пуст", style: TextStyle(color: Colors.grey)),
          );
        }

        return Column(
          children: [
            // Мини-сводка сверху списка
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Итого за день:",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      Text(
                        "$totalCals ккал",
                        style: const TextStyle(
                          color: Color(0xFFB76E79),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    "Б: $totalP  •  Ж: $totalF  •  У: $totalC",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            // Список продуктов
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index] as Map<String, dynamic>;

                  return Dismissible(
                    key: Key(item['id'] ?? index.toString()),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) {
                      // Получаем ID сегодняшнего документа и передаем его в метод удаления
                      final String todayDocId = DatabaseService().getTodayDocId();
                      DatabaseService().deleteMealItem(item, todayDocId);
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Удалено из дневника'),
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
                          color: const Color(0xFF1C1C1E).withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                          ),
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
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Б: ${item['protein']}г  •  Ж: ${item['fat']}г  •  У: ${item['carbs']}г",
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
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
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  "${item['weight_g']} г",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
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
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // Вкладка 2: СТАТИСТИКА (Графики и ИИ)
  // ==========================================
  Widget _buildStatsTab(String uid) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, userSnap) {
            final userData =
                userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final int userBmr = (userData['bmr'] as num?)?.toInt() ?? 0;
            final int userMaintenance =
                (userData['maintenanceCalories'] as num?)?.toInt() ?? 0;
            final bool hasMaintenance = userMaintenance > 0;

            return StreamBuilder<DocumentSnapshot>(
              stream: DatabaseService().getNutritionGoal(),
              builder: (context, goalSnapshot) {
                final goalData =
                    goalSnapshot.data?.data() as Map<String, dynamic>?;
                final int dailyTargetCals = goalData?['calories'] ?? 0;

                int daysMultiplier = 1;
                if (_selectedPeriod == 'week') daysMultiplier = 7;
                if (_selectedPeriod == 'month') daysMultiplier = 30;

                final int targetCalsTotal = dailyTargetCals * daysMultiplier;
                final int bmrTotal = userBmr * daysMultiplier;
                final int maintenanceTotal = userMaintenance * daysMultiplier;

                final logicalNow = DateTime.now().toLocal();
                DateTime startDate = DateTime(
                  logicalNow.year,
                  logicalNow.month,
                  logicalNow.day,
                );
                if (_selectedPeriod == 'week')
                  startDate = startDate.subtract(const Duration(days: 6));
                if (_selectedPeriod == 'month')
                  startDate = startDate.subtract(const Duration(days: 29));

                final startTs = Timestamp.fromDate(startDate);

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('meals')
                      .where('date', isGreaterThanOrEqualTo: startTs)
                      .snapshots(),
                  builder: (context, mealsSnapshot) {
                    int currentCals = 0;
                    if (mealsSnapshot.hasData) {
                      for (var doc in mealsSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        currentCals += (data['calories'] as num?)?.toInt() ?? 0;
                      }
                    }

                    int diff = 0;
                    String diffLabel = 'Осталось';
                    Color diffColor = Colors.grey;

                    if (hasMaintenance) {
                      diff = maintenanceTotal - currentCals;
                      if (diff > 0) {
                        diffLabel = 'Текущий Дефицит';
                        diffColor = const Color(0xFFB76E79);
                      } else if (diff < 0) {
                        diffLabel = 'Текущий Профицит';
                        diffColor = Colors.redAccent;
                      } else {
                        diffLabel = 'Идеальный баланс';
                        diffColor = const Color(0xFFB76E79);
                      }
                    } else {
                      diff = targetCalsTotal - currentCals;
                      if (diff < 0) diffColor = Colors.redAccent;
                    }

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ToggleButtons(
                              isSelected: [
                                _selectedPeriod == 'day',
                                _selectedPeriod == 'week',
                                _selectedPeriod == 'month',
                              ],
                              onPressed: (index) {
                                setState(() {
                                  if (index == 0) _selectedPeriod = 'day';
                                  if (index == 1) _selectedPeriod = 'week';
                                  if (index == 2) _selectedPeriod = 'month';
                                });
                              },
                              color: Colors.grey,
                              selectedColor: Colors.black,
                              fillColor: const Color(0xFFB76E79),
                              borderRadius: BorderRadius.circular(12),
                              constraints: BoxConstraints(
                                minHeight: 40,
                                minWidth:
                                    (MediaQuery.of(context).size.width - 36) /
                                    3,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                Text('day'.tr().toUpperCase()),
                                Text('seven_days'.tr()),
                                Text('thirty_days'.tr()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1E).withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFB76E79).withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildStatRow(
                                  'Базовый обмен (BMR)',
                                  userBmr > 0
                                      ? '$bmrTotal ккал'
                                      : 'Не рассчитан',
                                ),
                                const Divider(
                                  color: Colors.white10,
                                  height: 24,
                                ),
                                _buildStatRow(
                                  'Поддержание веса',
                                  hasMaintenance
                                      ? '$maintenanceTotal ккал'
                                      : 'Не рассчитано',
                                ),
                                const Divider(
                                  color: Colors.white10,
                                  height: 24,
                                ),
                                _buildStatRow(
                                  'Цель из профиля',
                                  targetCalsTotal > 0
                                      ? '$targetCalsTotal ккал'
                                      : 'Не задана',
                                ),
                                const Divider(
                                  color: Colors.white10,
                                  height: 24,
                                ),
                                _buildStatRow(
                                  'Употреблено калорий',
                                  '$currentCals ккал',
                                  valueColor: Colors.white,
                                ),
                                const Divider(
                                  color: Colors.white10,
                                  height: 24,
                                ),
                                _buildStatRow(
                                  diffLabel,
                                  diff == 0 && hasMaintenance
                                      ? '0 ккал'
                                      : '${diff.abs()} ккал',
                                  valueColor: diffColor,
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          const Text(
                            'Сводка от ИИ-Нутрициолога',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB76E79).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  color: Color(0xFFB76E79),
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _getAIDietitianInsight(
                                      maintenanceTotal,
                                      currentCals,
                                      diff,
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFFB76E79),
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (!hasMaintenance)
                            Padding(
                              padding: const EdgeInsets.only(top: 24.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const AIChatScreen(
                                          botType: 'dietitian',
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFB76E79,
                                    ).withOpacity(0.1),
                                    side: const BorderSide(
                                      color: Color(0xFFB76E79),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.auto_awesome,
                                    color: Color(0xFFB76E79),
                                  ),
                                  label: const Text(
                                    "Рассчитать норму с ИИ",
                                    style: TextStyle(
                                      color: Color(0xFFB76E79),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    String value, {
    Color valueColor = Colors.grey,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
