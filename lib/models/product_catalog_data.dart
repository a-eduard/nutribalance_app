class CatalogItem {
  final String name;
  final String category;
  const CatalogItem({required this.name, required this.category});
}

class ProductCatalogData {
  static const List<String> categories = [
    'Все', 'Овощи и зелень', 'Фрукты и ягоды', 'Мясо и птица', 
    'Морепродукты', 'Молочные продукты', 'Бакалея', 'Хлеб и выпечка', 'Разное'
  ];

  static const List<CatalogItem> allProducts = [
    // Овощи и зелень
    CatalogItem(name: 'Огурцы', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Помидоры', category: 'Овощи и зелень'),
    CatalogItem(name: 'Картофель', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Морковь', category: 'Овощи и зелень'),
    CatalogItem(name: 'Лук', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Чеснок', category: 'Овощи и зелень'),
    CatalogItem(name: 'Шпинат', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Брокколи', category: 'Овощи и зелень'),
    CatalogItem(name: 'Кабачки', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Болгарский перец', category: 'Овощи и зелень'),
    CatalogItem(name: 'Авокадо', category: 'Овощи и зелень'), 
    CatalogItem(name: 'Руккола', category: 'Овощи и зелень'),
    
    // Фрукты и ягоды
    CatalogItem(name: 'Яблоки', category: 'Фрукты и ягоды'), 
    CatalogItem(name: 'Бананы', category: 'Фрукты и ягоды'),
    CatalogItem(name: 'Лимон', category: 'Фрукты и ягоды'), 
    CatalogItem(name: 'Апельсины', category: 'Фрукты и ягоды'),
    CatalogItem(name: 'Груши', category: 'Фрукты и ягоды'), 
    CatalogItem(name: 'Голубика', category: 'Фрукты и ягоды'),
    CatalogItem(name: 'Клубника', category: 'Фрукты и ягоды'), 
    CatalogItem(name: 'Киви', category: 'Фрукты и ягоды'),
    
    // Мясо и птица
    CatalogItem(name: 'Филе куриное', category: 'Мясо и птица'), 
    CatalogItem(name: 'Филе индейки', category: 'Мясо и птица'),
    CatalogItem(name: 'Говядина (мякоть)', category: 'Мясо и птица'), 
    CatalogItem(name: 'Фарш куриный', category: 'Мясо и птица'),
    CatalogItem(name: 'Яйца (десяток)', category: 'Мясо и птица'),
    
    // Морепродукты
    CatalogItem(name: 'Красная рыба', category: 'Морепродукты'), 
    CatalogItem(name: 'Креветки', category: 'Морепродукты'),
    CatalogItem(name: 'Тунец консервированный', category: 'Морепродукты'), 
    CatalogItem(name: 'Белая рыба', category: 'Морепродукты'),
    
    // Молочные продукты
    CatalogItem(name: 'Молоко (2.5%)', category: 'Молочные продукты'), 
    CatalogItem(name: 'Творог (5%)', category: 'Молочные продукты'),
    CatalogItem(name: 'Сыр твердый', category: 'Молочные продукты'), 
    CatalogItem(name: 'Сметана', category: 'Молочные продукты'),
    CatalogItem(name: 'Кефир', category: 'Молочные продукты'), 
    CatalogItem(name: 'Сливочное масло', category: 'Молочные продукты'),
    CatalogItem(name: 'Йогурт классический', category: 'Молочные продукты'), 
    CatalogItem(name: 'Моцарелла', category: 'Молочные продукты'),
    
    // Бакалея
    CatalogItem(name: 'Макароны', category: 'Бакалея'), 
    CatalogItem(name: 'Гречка', category: 'Бакалея'),
    CatalogItem(name: 'Рис басмати', category: 'Бакалея'), 
    CatalogItem(name: 'Овсянка', category: 'Бакалея'),
    CatalogItem(name: 'Масло оливковое', category: 'Бакалея'), 
    CatalogItem(name: 'Чай', category: 'Бакалея'),
    CatalogItem(name: 'Кофе', category: 'Бакалея'), 
    CatalogItem(name: 'Сахар', category: 'Бакалея'),
    CatalogItem(name: 'Соль', category: 'Бакалея'), 
    CatalogItem(name: 'Мука', category: 'Бакалея'),
    CatalogItem(name: 'Орехи', category: 'Бакалея'),
    
    // Хлеб и выпечка
    CatalogItem(name: 'Хлеб цельнозерновой', category: 'Хлеб и выпечка'), 
    CatalogItem(name: 'Хлебцы', category: 'Хлеб и выпечка'),
    CatalogItem(name: 'Лаваш', category: 'Хлеб и выпечка'),
  ];

  static Map<String, String> get productCategoryMap {
    return { for (var item in allProducts) item.name : item.category };
  }
}