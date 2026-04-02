import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_catalog_data.dart';
import '../widgets/catalog/catalog_ui_components.dart';
import '../services/database_service.dart';

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Все';
  
  bool _isLoading = true;
  
  // Локальное хранилище выбранных продуктов
  final Set<String> _selectedProducts = {};
  
  // Для кастомных продуктов, добавленных пользователем
  final Map<String, String> _customProductsMap = {};

  @override
  void initState() {
    super.initState();
    _loadExistingList();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Загружаем то, что уже было добавлено в список покупок ранее
  Future<void> _loadExistingList() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).collection('shopping_list').doc('current').get();
      if (doc.exists) {
        final categories = doc.data()?['categories'] as List<dynamic>? ?? [];
        for (var cat in categories) {
          for (var item in (cat['items'] ?? [])) {
            _selectedProducts.add(item['name']);
          }
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<CatalogItem> get _filteredProducts {
    // Объединяем дефолтные и кастомные продукты
    List<CatalogItem> allAvailable = [
      ...ProductCatalogData.allProducts,
      ..._customProductsMap.entries.map((e) => CatalogItem(name: e.key, category: e.value))
    ];

    return allAvailable.where((product) {
      final matchesCategory = _selectedCategory == 'Все' || product.category == _selectedCategory;
      final matchesSearch = product.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _addCustomProductDialog() async {
    final TextEditingController customController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Свой продукт", style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w800, fontSize: 20)),
        content: TextField(
          controller: customController,
          style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w600),
          decoration: const InputDecoration(
            hintText: 'Название продукта',
            hintStyle: TextStyle(color: Color(0xFFC7C7CC)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFB76E79))),
          ),
          cursorColor: const Color(0xFFB76E79),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Color(0xFF8E8E93), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB76E79),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
            ),
            onPressed: () {
              final val = customController.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  _customProductsMap[val] = 'Разное';
                  _selectedProducts.add(val);
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Добавить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  // Сохранение пачкой и закрытие
  Future<void> _saveAndClose() async {
    setState(() => _isLoading = true);
    
    // Собираем карту категорий для всех продуктов (базовые + кастомные)
    Map<String, String> fullCategoryMap = {...ProductCatalogData.productCategoryMap, ..._customProductsMap};
    
    await DatabaseService().syncCatalogShoppingList(_selectedProducts, fullCategoryMap);
    
    if (mounted) {
      Navigator.pop(context); // Закрываем экран
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F9F9),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFB76E79))),
      );
    }

    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text("Выбрать продукты", style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w800, fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2D2D2D)),
        actions: [
          IconButton(icon: const Icon(Icons.add, size: 28), onPressed: _addCustomProductDialog),
          const SizedBox(width: 8),
        ],
      ),
      // Плавающая кнопка сохранения
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveAndClose,
        backgroundColor: const Color(0xFFB76E79),
        elevation: 8,
        icon: const Icon(Icons.check, color: Colors.white),
        label: Text("Добавить в список (${_selectedProducts.length})", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      body: Column(
        children: [
          CatalogSearchBar(controller: _searchController),
          const SizedBox(height: 8),
          CatalogCategoryChips(
            categories: ProductCatalogData.categories,
            selectedCategory: _selectedCategory,
            onSelected: (cat) => setState(() => _selectedCategory = cat),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: products.isEmpty 
              ? const Center(child: Text('Продукты не найдены', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100), // Отступ под FAB
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final bool isSelected = _selectedProducts.contains(product.name);

                    return CatalogProductTile(
                      name: product.name,
                      category: product.category,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedProducts.remove(product.name);
                          } else {
                            _selectedProducts.add(product.name);
                          }
                        });
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