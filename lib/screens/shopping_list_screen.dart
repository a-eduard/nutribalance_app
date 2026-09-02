// Файл: lib/screens/shopping_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import 'product_catalog_screen.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Мои покупки', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        actions: [
          TextButton(
            onPressed: () async {
              await DatabaseService().clearCheckedShoppingItems();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Купленные продукты удалены ✨', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), 
                  backgroundColor: theme.colorScheme.primary
                )
              );
            },
            child: Text('Очистить', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('shopping_list').doc('current').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
                }

                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                final List<dynamic> categories = data['categories'] ?? [];

                final activeCategories = categories.where((cat) => (cat['items'] as List).isNotEmpty).toList();

                if (activeCategories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_basket_outlined, size: 80, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'Твой список пуст', 
                          style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w800)
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ева с радостью поможет\nсоставить меню на неделю', 
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15, fontWeight: FontWeight.w500)
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 40),
                  itemCount: activeCategories.length,
                  itemBuilder: (context, index) {
                    final category = activeCategories[index];
                    final catName = category['name'] ?? 'Продукты';
                    final items = category['items'] as List<dynamic>? ?? [];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(catName.toUpperCase(), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          ...items.map((item) {
                            final itemName = item['name'] ?? '';
                            final itemAmount = item['amount'] ?? '';
                            final bool isChecked = item['isChecked'] ?? false;

                            return OptimisticShoppingItem(
                              catName: catName,
                              itemName: itemName,
                              amount: itemAmount,
                              initialChecked: isChecked,
                            );
                          }),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 40), 
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 32, offset: const Offset(0, -8))],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductCatalogScreen()));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  shadowColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: Icon(Icons.add, color: theme.colorScheme.onPrimary),
                label: Text(
                  "ДОБАВИТЬ ПРОДУКТЫ", 
                  style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.0)
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// === ВИДЖЕТ МГНОВЕННОГО ОТКЛИКА (Optimistic UI) ===
class OptimisticShoppingItem extends StatefulWidget {
  final String catName;
  final String itemName;
  final String amount;
  final bool initialChecked;

  const OptimisticShoppingItem({
    super.key,
    required this.catName,
    required this.itemName,
    required this.amount,
    required this.initialChecked,
  });

  @override
  State<OptimisticShoppingItem> createState() => _OptimisticShoppingItemState();
}

class _OptimisticShoppingItemState extends State<OptimisticShoppingItem> {
  late bool _isChecked;

  @override
  void initState() {
    super.initState();
    _isChecked = widget.initialChecked;
  }

  @override
  void didUpdateWidget(covariant OptimisticShoppingItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChecked != widget.initialChecked) {
      _isChecked = widget.initialChecked;
    }
  }

  void _toggleItem() async {
    final previousState = _isChecked;
    
    // 1. Мгновенно меняем UI
    setState(() {
      _isChecked = !_isChecked;
    });
    
    // 2. Отправляем запрос с перехватом ошибки
    try {
      await DatabaseService().toggleShoppingListItem(widget.catName, widget.itemName, _isChecked);
    } catch (e) {
      // 3. Откатываем UI, если сервер не ответил
      if (!mounted) return;
      setState(() => _isChecked = previousState);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка синхронизации. Проверьте интернет.', style: TextStyle(color: Colors.white)), 
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: _toggleItem, 
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: _isChecked ? theme.colorScheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isChecked ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2), 
                  width: 2
                ),
              ),
              child: _isChecked ? Icon(Icons.check, size: 16, color: theme.colorScheme.onPrimary) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.itemName, 
                    style: TextStyle(
                      color: _isChecked ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface, 
                      fontSize: 16, 
                      fontWeight: FontWeight.w700,
                      decoration: _isChecked ? TextDecoration.lineThrough : null,
                      decorationColor: theme.colorScheme.onSurfaceVariant,
                    )
                  ),
                  if (widget.amount.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        widget.amount, 
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)
                      ),
                    )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}