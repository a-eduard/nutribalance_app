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
  
  final Set<String> _selectedProducts = {};
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

  Future<void> _addCustomProductDialog(ThemeData theme) async {
    final TextEditingController customController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Свой продукт", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 20)),
        content: TextField(
          controller: customController,
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Название продукта',
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.2))),
          ),
          cursorColor: theme.colorScheme.primary,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
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
            child: Text('Добавить', style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  Future<void> _saveAndClose() async {
    setState(() => _isLoading = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    
    Map<String, String> fullCategoryMap = {...ProductCatalogData.productCategoryMap, ..._customProductsMap};
    
    try {
      await DatabaseService().syncCatalogShoppingList(_selectedProducts, fullCategoryMap);
      if (mounted) navigator.pop(); 
    } catch (e) {
      debugPrint('Ошибка синхронизации каталога: $e');
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ошибка сохранения. Проверьте интернет.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    final products = _filteredProducts;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text("Выбрать продукты", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        actions: [
          IconButton(icon: const Icon(Icons.add, size: 28), onPressed: () => _addCustomProductDialog(theme)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveAndClose,
        backgroundColor: theme.colorScheme.primary,
        elevation: 8,
        icon: Icon(Icons.check, color: theme.colorScheme.onPrimary),
        label: Text("Добавить в список (${_selectedProducts.length})", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
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
              ? Center(child: Text('Продукты не найдены', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15)))
              : ListView.builder(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100), 
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