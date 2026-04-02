import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/database_service.dart';
import 'product_catalog_screen.dart';

class ShoppingListScreen extends StatelessWidget {
  const ShoppingListScreen({super.key});

  static const Color _accentColor = Color(0xFFB76E79); 
  static const Color _bgColor = Color(0xFFF9F9F9);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('Мои покупки', style: TextStyle(color: _textColor, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: _textColor),
        actions: [
          TextButton(
            onPressed: () {
              DatabaseService().clearCheckedShoppingItems();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Купленные продукты удалены ✨', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.teal));
            },
            child: const Text('Очистить', style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 16)),
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
                  return const Center(child: CircularProgressIndicator(color: _accentColor));
                }

                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                final List<dynamic> categories = data['categories'] ?? [];

                final activeCategories = categories.where((cat) => (cat['items'] as List).isNotEmpty).toList();

                if (activeCategories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_basket_outlined, size: 80, color: _subTextColor.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        const Text(
                          'Твой список пуст', 
                          style: TextStyle(color: _textColor, fontSize: 20, fontWeight: FontWeight.w800)
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ева с радостью поможет\nсоставить меню на неделю', 
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _subTextColor, fontSize: 15, fontWeight: FontWeight.w500)
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
                          Text(catName.toUpperCase(), style: const TextStyle(color: _accentColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          ...items.map((item) {
                            final itemName = item['name'] ?? '';
                            final itemAmount = item['amount'] ?? '';
                            final bool isChecked = item['isChecked'] ?? false;

                            // Используем новый виджет с мгновенным откликом
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
              color: Colors.white,
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
                  backgroundColor: _accentColor,
                  shadowColor: _accentColor.withValues(alpha: 0.3),
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  "ДОБАВИТЬ ПРОДУКТЫ", 
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.0)
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
  static const Color _accentColor = Color(0xFFB76E79); 
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    _isChecked = widget.initialChecked;
  }

  // Обновляем стейт, если пришли новые данные с сервера, 
  // но приоритет отдаем локальному клику
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
      if (mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleItem, // Вызываем мгновенную функцию
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24, height: 24,
              decoration: BoxDecoration(
                color: _isChecked ? _accentColor : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: _isChecked ? _accentColor : const Color(0xFFE5E5EA), width: 2),
              ),
              child: _isChecked ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.itemName, 
                    style: TextStyle(
                      color: _isChecked ? _subTextColor : _textColor, 
                      fontSize: 16, 
                      fontWeight: FontWeight.w700,
                      decoration: _isChecked ? TextDecoration.lineThrough : null,
                    )
                  ),
                  if (widget.amount.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(widget.amount, style: TextStyle(color: _subTextColor.withValues(alpha: 0.8), fontSize: 13, fontWeight: FontWeight.w500)),
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