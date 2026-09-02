import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../services/database_service.dart';

class MealDetailScreen extends StatefulWidget {
  final Map<String, dynamic> mealData; 
  final String dateDocId;

  const MealDetailScreen({super.key, required this.mealData, required this.dateDocId});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {

  void _showEditWeightDialog(Map<String, dynamic> ingredient, String mealId, ThemeData theme) {
    final TextEditingController weightController = TextEditingController(text: ingredient['weight_g'].toString());

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Вес ингредиента', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ingredient['name'], style: TextStyle(color: theme.colorScheme.primary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(
              controller: weightController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                labelText: 'Граммы',
                labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary, width: 2)),
                suffixText: 'г',
                suffixStyle: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20),
              ),
              cursorColor: theme.colorScheme.primary,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Отмена', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              final doubleWeight = double.tryParse(weightController.text.replaceAll(',', '.').trim());
              if (doubleWeight != null && doubleWeight > 0) {
                DatabaseService().updateIngredientWeight(mealId, ingredient, doubleWeight.round()); 
                Navigator.pop(ctx);
              }
            },
            child: Text('Сохранить', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.colorScheme.primary.withValues(alpha: 0.1), theme.colorScheme.surface], begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      child: Center(child: Icon(Icons.restaurant, size: 80, color: theme.colorScheme.primary.withValues(alpha: 0.3))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    if (uid == null) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(widget.dateDocId).snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          
          Map<String, dynamic> currentMeal = widget.mealData;
          List<dynamic> items = []; 

          if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            items = data['items'] ?? []; 
            final mealIndex = items.indexWhere((m) => m['id'] == currentMeal['id']);
            if (mealIndex != -1) {
              currentMeal = items[mealIndex] as Map<String, dynamic>;
            }
          }

          List<dynamic> ingredients = [];
          if (currentMeal['ingredients_json'] != null) {
            ingredients = jsonDecode(currentMeal['ingredients_json']);
          } else {
            ingredients = currentMeal['ingredients'] ?? [];
          }
          
          int totalScore = 0;
          int validIngredientsCount = 0;
          
          for (var ing in ingredients) {
            if (ing is Map<String, dynamic>) {
              totalScore += (ing['health_score'] as num?)?.toInt() ?? 5; 
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
                backgroundColor: theme.colorScheme.surface,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                    child: IconButton(icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface), onPressed: () => Navigator.pop(context)),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: theme.colorScheme.surface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              title: Text('Удалить блюдо?', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
                              content: Text('Это действие нельзя отменить.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            DatabaseService().deleteMealItem(currentMeal, items, widget.dateDocId);
                            // ИСПРАВЛЕНИЕ: Используем context.mounted
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Блюдо удалено ✨', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), 
                                backgroundColor: theme.colorScheme.primary
                              )
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (currentMeal['imageUrl'] != null && currentMeal['imageUrl'].toString().startsWith('http'))
                        CachedNetworkImage(
                          imageUrl: currentMeal['imageUrl'],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1)),
                          errorWidget: (context, url, error) => _buildPlaceholder(theme),
                        )
                      else
                        _buildPlaceholder(theme),
                        
                      Positioned(
                        bottom: -2, left: 0, right: 0,
                        child: Container(height: 40, decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(32)))),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)))),
                      const SizedBox(height: 24),
                      Text(currentMeal['name'] ?? 'Блюдо', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 32),

                      Row(
                        children: [
                          Expanded(child: _buildInfoCard('Калории', '${currentMeal['calories']}', theme, isEditable: false, bgColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.05))),
                          const SizedBox(width: 16),
                          Expanded(child: _buildInfoCard('Порция', '1', theme, isEditable: false)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildMacroCard('Белки', 'P', '${currentMeal['protein']}г', theme.colorScheme.secondary, theme)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildMacroCard('Жиры', 'F', '${currentMeal['fat']}г', const Color(0xFFE5C158), theme)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildMacroCard('Углеводы', 'C', '${currentMeal['carbs']}г', const Color(0xFF89CFF0), theme)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildMacroCard('Клетчатка', 'K', '${currentMeal['fiber'] ?? 0}г', Colors.green[300] ?? Colors.green, theme)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20), 
                          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Индекс пользы блюда', style: TextStyle(color: theme.colorScheme.primary, fontSize: 15, fontWeight: FontWeight.w800)),
                            Row(
                              children: [
                                Icon(Icons.favorite, color: theme.colorScheme.primary, size: 20), 
                                const SizedBox(width: 6), 
                                Text('$avgScore/10', style: TextStyle(color: theme.colorScheme.primary, fontSize: 20, fontWeight: FontWeight.w900))
                              ]
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: theme.colorScheme.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Ингредиенты", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      ...ingredients.map((ing) => _buildIngredientRow(ing, currentMeal['id'], theme)),
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

  Widget _buildInfoCard(String title, String value, ThemeData theme, {bool isEditable = false, Color? bgColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor ?? theme.colorScheme.surface, 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
              if (isEditable) Icon(Icons.edit, color: theme.colorScheme.onSurface, size: 16),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroCard(String title, String letter, String value, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05), 
        borderRadius: BorderRadius.circular(20), 
        border: Border.all(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(width: 20, height: 20, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(width: 8),
              Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(dynamic itemDynamic, String mealId, ThemeData theme) {
    if (itemDynamic is! Map<String, dynamic>) return const SizedBox.shrink();
    final Map<String, dynamic> item = itemDynamic;

    return GestureDetector(
      onTap: () => _showEditWeightDialog(item, mealId, theme),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name'] ?? 'Ингредиент', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text("${item['weight_g'] ?? 0}г на порцию", style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _buildMiniBadge('P', item['protein'] ?? 0, theme.colorScheme.secondary, theme),
                      _buildMiniBadge('F', item['fat'] ?? 0, const Color(0xFFE5C158), theme),
                      _buildMiniBadge('C', item['carbs'] ?? 0, const Color(0xFF89CFF0), theme),
                      _buildMiniBadge('K', item['fiber'] ?? 0, Colors.green[300] ?? Colors.green, theme),
                    ],
                  ),
                ],
              ),
            ),
            Text("${item['calories'] ?? 0} ккал", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String letter, dynamic value, Color color, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), alignment: Alignment.center, child: Text(letter, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))),
        const SizedBox(width: 6),
        Text('${value ?? 0}г', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}