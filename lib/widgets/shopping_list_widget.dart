import 'package:flutter/material.dart';

class ShoppingListCardWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  const ShoppingListCardWidget({super.key, required this.data});

  @override
  State<ShoppingListCardWidget> createState() => _ShoppingListCardWidgetState();
}

class _ShoppingListCardWidgetState extends State<ShoppingListCardWidget> {
  // Локальное хранилище для состояния чекбоксов
  final Map<String, bool> _checkedItems = {};

  @override
  Widget build(BuildContext context) {
    final List<dynamic> categories = widget.data['categories'] ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: const Color(0xFFB76E79).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_bag_outlined, color: Color(0xFFB76E79)),
              SizedBox(width: 8),
              Text("Умный список покупок", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D2D2D))),
            ],
          ),
          const Divider(height: 24, color: Color(0xFFF0F0F0)),
          ...categories.map((cat) {
            final String catName = cat['name'] ?? 'Категория';
            final List<dynamic> items = cat['items'] ?? [];
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(catName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey, letterSpacing: 1.0)),
                  const SizedBox(height: 8),
                  ...items.map((item) {
                    final String itemName = item['name'] ?? '';
                    final String itemAmount = item['amount'] ?? '';
                    final String uniqueKey = "${catName}_$itemName";
                    final bool isChecked = _checkedItems[uniqueKey] ?? false;

                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: const Color(0xFFB76E79),
                      checkColor: Colors.white,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(itemName, style: TextStyle(
                        color: isChecked ? Colors.grey : const Color(0xFF2D2D2D),
                        decoration: isChecked ? TextDecoration.lineThrough : null,
                        fontWeight: FontWeight.w600
                      )),
                      subtitle: itemAmount.isNotEmpty ? Text(itemAmount, style: const TextStyle(fontSize: 12, color: Colors.grey)) : null,
                      value: isChecked,
                      onChanged: (val) {
                        setState(() {
                          _checkedItems[uniqueKey] = val ?? false;
                        });
                      },
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}