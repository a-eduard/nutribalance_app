import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';

class MealDetailScreen extends StatefulWidget {
  final Map<String, dynamic> mealData; 
  final String dateDocId;

  const MealDetailScreen({super.key, required this.mealData, required this.dateDocId});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);
  static const Color _bgColor = Color(0xFFF9F9F9);

  void _showEditWeightDialog(Map<String, dynamic> ingredient, String mealId) {
    final TextEditingController weightController = TextEditingController(text: ingredient['weight_g'].toString());
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Вес ингредиента', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ingredient['name'], style: const TextStyle(color: _accentColor, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(
                    labelText: 'Граммы',
                    labelStyle: TextStyle(color: _subTextColor),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE5E5EA))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accentColor, width: 2)),
                    suffixText: 'г',
                    suffixStyle: TextStyle(color: _textColor, fontSize: 20),
                  ),
                  cursorColor: _accentColor,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx), 
                child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _accentColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: isSaving ? null : () {
                  final newWeight = int.tryParse(weightController.text.trim());
                  if (newWeight != null && newWeight > 0) {
                    setStateDialog(() => isSaving = true);
                    
                    // === ОПТИМИСТИЧНЫЙ UI: Не ждем Firebase App Check! ===
                    // Бросаем задачу в фон и сразу закрываем окно
                    try {
                      DatabaseService().updateIngredientWeight(mealId, ingredient, newWeight);
                      if (context.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setStateDialog(() => isSaving = false);
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold();

    return Scaffold(
      backgroundColor: _bgColor,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(widget.dateDocId).snapshots(),
        builder: (context, snapshot) {
          
          // === ЖЕЛЕЗОБЕТОННЫЙ ОПТИМИСТИЧНЫЙ UI ===
          // Мы ПОЛНОСТЬЮ убрали лоадеры ConnectionState.waiting. 
          // Теперь экран отрисуется мгновенно, используя данные с предыдущего экрана.
          
          Map<String, dynamic> currentMeal = widget.mealData;

          // Если Firebase проснулся и принес свежие данные из базы - аккуратно их подхватываем
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final List<dynamic> items = data['items'] ?? [];
            final mealIndex = items.indexWhere((m) => m['id'] == currentMeal['id']);
            if (mealIndex != -1) {
              currentMeal = items[mealIndex] as Map<String, dynamic>;
            }
          }

          final List<dynamic> ingredients = currentMeal['ingredients'] ?? [];
          
          // === БЕЗОПАСНЫЙ ПОДСЧЕТ ПОЛЬЗЫ ===
          int totalScore = 0;
          int validIngredientsCount = 0;
          
          for (var ing in ingredients) {
            if (ing is Map<String, dynamic>) {
              totalScore += (ing['health_score'] as num?)?.toInt() ?? 5; // Если null, берем 5
              validIngredientsCount++;
            }
          }
          
          int avgScore = validIngredientsCount > 0 ? (totalScore / validIngredientsCount).round() : 5;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 250.0,
                pinned: true,
                backgroundColor: Colors.white,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(icon: const Icon(Icons.arrow_back, color: _textColor), onPressed: () => Navigator.pop(context)),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: const Color(0xFFF2F2F7), child: const Icon(Icons.restaurant, size: 80, color: Color(0xFFC7C7CC))),
                      Positioned(
                        bottom: -2, left: 0, right: 0,
                        child: Container(height: 40, decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32)))),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Text(currentMeal['name'] ?? 'Блюдо', style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(child: _buildInfoCard('Калории', '${currentMeal['calories']}', isEditable: false)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildInfoCard('Порция', '1', isEditable: false)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildMacroCard('Белки', 'P', '${currentMeal['protein']}г', const Color(0xFFD49A89))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildMacroCard('Жиры', 'F', '${currentMeal['fat']}г', const Color(0xFFE5C158))),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildMacroCard('Углеводы', 'C', '${currentMeal['carbs']}г', const Color(0xFF89CFF0))),
                          const SizedBox(width: 16),
                          // === КАРТОЧКА ПОЛЬЗЫ: СТРОГО Rose Gold ===
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white, 
                                borderRadius: BorderRadius.circular(20), 
                                border: Border.all(color: _accentColor.withValues(alpha: 0.3), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04), 
                                    blurRadius: 24, 
                                    offset: const Offset(0, 8)
                                  )
                                ]
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Польза', style: TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.favorite, color: _accentColor, size: 16), 
                                      const SizedBox(width: 6), 
                                      Text('$avgScore/10', style: const TextStyle(color: _accentColor, fontSize: 18, fontWeight: FontWeight.w900))
                                    ]
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Ингредиенты", style: TextStyle(color: _textColor, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      ...ingredients.map((ing) => _buildIngredientRow(ing, currentMeal['id'])).toList(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, {bool isEditable = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w900)),
              if (isEditable) const Icon(Icons.edit, color: _textColor, size: 16),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroCard(String title, String letter, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _subTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 20, height: 20, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(dynamic itemDynamic, String mealId) {
    if (itemDynamic is! Map<String, dynamic>) return const SizedBox.shrink();
    final Map<String, dynamic> item = itemDynamic;

    return GestureDetector(
      onTap: () => _showEditWeightDialog(item, mealId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name'] ?? 'Ингредиент', style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text("${item['weight_g'] ?? 0}г на порцию", style: const TextStyle(color: _subTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildMiniBadge('P', item['protein'] ?? 0, const Color(0xFFD49A89)),
                      const SizedBox(width: 12),
                      _buildMiniBadge('F', item['fat'] ?? 0, const Color(0xFFE5C158)),
                      const SizedBox(width: 12),
                      _buildMiniBadge('C', item['carbs'] ?? 0, const Color(0xFF89CFF0)),
                    ],
                  ),
                ],
              ),
            ),
            Text("${item['calories'] ?? 0} ккал", style: const TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String letter, dynamic value, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
        const SizedBox(width: 6),
        Text('${value ?? 0}г', style: const TextStyle(color: _textColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}