// Файл: lib/widgets/catalog/catalog_ui_components.dart

import 'package:flutter/material.dart';

class CatalogSearchBar extends StatelessWidget {
  final TextEditingController controller;
  const CatalogSearchBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
          ],
        ),
        child: TextField(
          controller: controller,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Поиск продукта...',
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
            border: InputBorder.none, 
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
        ),
      ),
    );
  }
}

class CatalogCategoryChips extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final Function(String) onSelected;

  const CatalogCategoryChips({
    super.key, 
    required this.categories, 
    required this.selectedCategory, 
    required this.onSelected
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return SizedBox(
      height: 52,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final bool isActive = selectedCategory == category;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: ChoiceChip(
              label: Text(category, style: TextStyle(
                color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              )),
              selected: isActive,
              onSelected: (selected) {
                if (selected) onSelected(category);
              },
              selectedColor: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), 
              side: const BorderSide(color: Colors.transparent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              showCheckmark: false,
              elevation: isActive ? 4 : 0,
              shadowColor: theme.colorScheme.primary.withValues(alpha: 0.4),
            ),
          );
        },
      ),
    );
  }
}

class CatalogProductTile extends StatelessWidget {
  final String name;
  final String category;
  final bool isSelected;
  final VoidCallback onTap;

  const CatalogProductTile({
    super.key, 
    required this.name, 
    required this.category, 
    required this.isSelected, 
    required this.onTap
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        onTap: onTap,
        title: Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface, fontSize: 16)),
        subtitle: Text(category, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
        trailing: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            key: ValueKey<bool>(isSelected),
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            size: 28,
          ),
        ),
      ),
    );
  }
}