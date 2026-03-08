import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'profile_screen.dart'; 
import 'ai_chat_screen.dart'; 
import '../widgets/dashboard/nutrition_card.dart';
import '../widgets/dashboard/daily_meals_bottom_sheet.dart';
import '../services/database_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  static const Color _bgColor = Color(0xFFF9F9F9); 

  final List<Widget> _screens = [
    const HomeTab(),
    const CommunityScreen(), 
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor, 
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, -8))]
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index), 
          // Убрали const перед массивом items, так как Image.asset не может быть константой
          items: [
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons/home.png', width: 26, height: 26, color: const Color(0xFF8E8E93)), 
              activeIcon: Image.asset('assets/icons/home.png', width: 26, height: 26, color: const Color(0xFFB76E79)), 
              label: 'Главная'
            ),
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons/chats.png', width: 26, height: 26, color: const Color(0xFF8E8E93)), 
              activeIcon: Image.asset('assets/icons/chats.png', width: 26, height: 26, color: const Color(0xFFB76E79)), 
              label: 'Комьюнити'
            ),
            BottomNavigationBarItem(
              icon: Image.asset('assets/icons/profile.png', width: 26, height: 26, color: const Color(0xFF8E8E93)), 
              activeIcon: Image.asset('assets/icons/profile.png', width: 26, height: 26, color: const Color(0xFFB76E79)), 
              label: 'Профиль'
            ),
          ],
        ),
      ),
    );
  }
}

// === ВКЛАДКА "ГЛАВНАЯ" ===
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _accentColor));

            final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final name = userData['name']?.toString() ?? 'Красотка';

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("NutriBalance", style: TextStyle(color: _accentColor, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Привет, $name ✨", style: const TextStyle(color: _textColor, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const DiscreetCycleWidget(), 
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  const DailyAffirmationWidget(),

                  GestureDetector(
                    onTap: () => DailyMealsBottomSheet.show(context),
                    child: const NutritionSummaryCard(),
                  ),
                  
                  const SizedBox(height: 32),
                  const Text('ТВОЙ АССИСТЕНТ', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2)),
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian'))),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.25), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28)),
                          const SizedBox(width: 16),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Eva', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)), SizedBox(height: 4), Text('Твой личный нутрициолог', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))])),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                  const WaterTrackerWidget(),
                  
                  const SizedBox(height: 32),
                  const Text('СЪЕДЕНО СЕГОДНЯ', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.2)),
                  const SizedBox(height: 16),
                  const ConsumedTodayWidget(),

                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity, height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: OutlinedButton.icon(
                      onPressed: () => _showShoppingList(context),
                      icon: const Icon(Icons.shopping_bag_outlined, color: _accentColor, size: 22),
                      label: const Text("Мой список покупок", style: TextStyle(color: _accentColor, fontWeight: FontWeight.w800, fontSize: 15)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.transparent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  void _showShoppingList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => const ShoppingListBottomSheet(),
    );
  }
}

// === ДЕЛИКАТНЫЙ ВИДЖЕТ ЦИКЛА ===
class DiscreetCycleWidget extends StatelessWidget {
  const DiscreetCycleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        
        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final Timestamp? lastPeriod = userData['lastPeriodStartDate'] as Timestamp?;
        final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

        if (lastPeriod == null) return const SizedBox.shrink();

        final start = DateTime(lastPeriod.toDate().year, lastPeriod.toDate().month, lastPeriod.toDate().day);
        final now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final diff = now.difference(start).inDays;

        if (diff < 0) return const SizedBox.shrink();

        final int dayOfCycle = (diff % cycleLength) + 1;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFDECE8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFB76E79).withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_florist, color: Color(0xFFB76E79), size: 14),
              const SizedBox(width: 6),
              Text("$dayOfCycle день", style: const TextStyle(color: Color(0xFFB76E79), fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        );
      }
    );
  }
}

// === БОТТОМ-ШИТ СПИСКА ПОКУПОК ===
class ShoppingListBottomSheet extends StatelessWidget {
  const ShoppingListBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12, bottom: 16), width: 48, height: 6, decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(3))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Align(alignment: Alignment.centerLeft, child: Text("Список покупок 🛍", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF2D2D2D)))),
            ),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('shopping_list').doc('current').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)));
                  
                  final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                  final List<dynamic> categories = data['categories'] ?? [];

                  if (categories.isEmpty) {
                    return const Center(child: Text("Твой список пока пуст.\nПопроси Еву составить меню!", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), height: 1.5, fontSize: 15)));
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(24),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      final String catName = cat['name'] ?? 'Категория';
                      final List<dynamic> items = cat['items'] ?? [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(catName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF8E8E93), letterSpacing: 1.2)),
                            const SizedBox(height: 12),
                            ...items.map((item) {
                              final String itemName = item['name'] ?? '';
                              final String itemAmount = item['amount'] ?? '';
                              final bool isChecked = item['isChecked'] ?? false;

                              return CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                activeColor: const Color(0xFFB76E79),
                                checkColor: Colors.white,
                                dense: true,
                                title: Text(itemName, style: TextStyle(color: isChecked ? const Color(0xFF8E8E93) : const Color(0xFF2D2D2D), decoration: isChecked ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600, fontSize: 15)),
                                subtitle: itemAmount.isNotEmpty ? Text(itemAmount, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93))) : null,
                                value: isChecked,
                                onChanged: (val) {
                                  DatabaseService().toggleShoppingListItem(catName, itemName, val ?? false);
                                },
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  );
                }
              ),
            ),
          ],
        );
      }
    );
  }
}

// === ВИДЖЕТ: Список съеденного за день ===
class ConsumedTodayWidget extends StatefulWidget {
  const ConsumedTodayWidget({super.key});

  @override
  State<ConsumedTodayWidget> createState() => _ConsumedTodayWidgetState();
}

class _ConsumedTodayWidgetState extends State<ConsumedTodayWidget> {
  String get _todayDocId => DateTime.now().toString().substring(0, 10); 

  Future<void> _deleteItem(String uid, DocumentSnapshot itemDoc) async {
    final data = itemDoc.data() as Map<String, dynamic>;
    final int cals = (data['calories'] as num?)?.toInt() ?? 0;
    final int p = (data['protein'] as num?)?.toInt() ?? 0;
    final int f = (data['fat'] as num?)?.toInt() ?? 0;
    final int c = (data['carbs'] as num?)?.toInt() ?? 0;

    await itemDoc.reference.delete();

    final dailyRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_todayDocId);
    await dailyRef.set({
      'calories': FieldValue.increment(-cals),
      'protein': FieldValue.increment(-p),
      'fat': FieldValue.increment(-f),
      'carbs': FieldValue.increment(-c),
    }, SetOptions(merge: true));
  }

  Future<void> _editItemWeight(BuildContext context, String uid, DocumentSnapshot itemDoc) async {
    final data = itemDoc.data() as Map<String, dynamic>;
    final double oldGrams = (data['grams'] as num?)?.toDouble() ?? 100.0;
    final String name = data['name'] ?? 'Продукт';
    
    final TextEditingController controller = TextEditingController(text: oldGrams.toInt().toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(name, style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w800, fontSize: 20)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 28, fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'Вес порции',
            suffixText: 'г',
            border: InputBorder.none,
          ),
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
              final double? newGrams = double.tryParse(controller.text.trim());
              if (newGrams != null && newGrams > 0 && newGrams != oldGrams) {
                Navigator.pop(ctx);
                _applyEdit(uid, itemDoc, oldGrams, newGrams);
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }

  Future<void> _applyEdit(String uid, DocumentSnapshot itemDoc, double oldGrams, double newGrams) async {
    final data = itemDoc.data() as Map<String, dynamic>;
    final int oldC = (data['calories'] as num?)?.toInt() ?? 0;
    final int oldP = (data['protein'] as num?)?.toInt() ?? 0;
    final int oldF = (data['fat'] as num?)?.toInt() ?? 0;
    final int oldCarbs = (data['carbs'] as num?)?.toInt() ?? 0;

    final double ratio = oldGrams > 0 ? (newGrams / oldGrams) : 1.0;

    final int newC = (oldC * ratio).round();
    final int newP = (oldP * ratio).round();
    final int newF = (oldF * ratio).round();
    final int newCarbs = (oldCarbs * ratio).round();

    await itemDoc.reference.update({
      'grams': newGrams,
      'calories': newC,
      'protein': newP,
      'fat': newF,
      'carbs': newCarbs,
    });

    final dailyRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_todayDocId);
    await dailyRef.set({
      'calories': FieldValue.increment(newC - oldC),
      'protein': FieldValue.increment(newP - oldP),
      'fat': FieldValue.increment(newF - oldF),
      'carbs': FieldValue.increment(newCarbs - oldCarbs),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('meals').doc(_todayDocId).collection('items').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFB76E79)));
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
            child: const Text("Вы еще ничего не записали сегодня. Напишите Еве, чтобы добавить прием пищи! 🍽", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
          );
        }

        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String name = data['name'] ?? 'Продукт';
            final int cals = (data['calories'] as num?)?.toInt() ?? 0;
            final double grams = (data['grams'] as num?)?.toDouble() ?? 100.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                ),
                onDismissed: (dir) => _deleteItem(uid, doc),
                child: InkWell(
                  onTap: () => _editItemWeight(context, uid, doc),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(color: Color(0xFFFDECE8), shape: BoxShape.circle),
                          child: const Text('🍎', style: TextStyle(fontSize: 18)), 
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2D2D2D), fontSize: 15)),
                              const SizedBox(height: 4),
                              Text("${grams.toInt()} г", style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("$cals ккал", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2D2D2D), fontSize: 18)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// === ОСТАЛЬНЫЕ ВИДЖЕТЫ ===
class DailyAffirmationWidget extends StatelessWidget {
  const DailyAffirmationWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final List<String> affirmations = [
      "Твой вес — это не твоя ценность. Фокус на энергии! ✨",
      "Пей воду и сияй! 💧",
      "Ты прекрасна сегодня! 🌸",
      "Движение — это любовь к своему телу. 💃",
      "Слушай свое тело, оно знает, что ему нужно. 🌿",
      "Маленькие шаги ведут к большим результатам. 🕊️",
      "Еда — это топливо и удовольствие, а не враг. 🍎",
      "Сравнивай себя только с собой вчерашней. 🌟",
      "Отдых — это тоже часть прогресса. 🧘‍♀️",
      "Твоя улыбка освещает этот мир! ☀️"
    ];
    final phrase = affirmations[DateTime.now().day % affirmations.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD49A89).withValues(alpha: 0.2))),
      child: Row(children: [const Text("✨", style: TextStyle(fontSize: 22)), const SizedBox(width: 16), Expanded(child: Text(phrase, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)))]),
    );
  }
}

class WaterTrackerWidget extends StatelessWidget {
  const WaterTrackerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: DatabaseService().getTodayMealsDoc(),
      builder: (context, snapshot) {
        int waterCount = 0;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          waterCount = (data['water_glasses'] as num?)?.toInt() ?? 0;
        }
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ВЫПИТО ВОДЫ', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.2)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(8, (index) {
                  bool isFilled = index < waterCount;
                  return GestureDetector(
                    onTap: () { int newCount = isFilled ? index : index + 1; DatabaseService().updateWaterGlasses(newCount); },
                    child: Icon(isFilled ? Icons.water_drop : Icons.water_drop_outlined, color: isFilled ? const Color(0xFF89CFF0) : const Color(0xFFE5E5EA), size: 34),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Center(child: Text("$waterCount из 8 стаканов ( ${(waterCount * 0.25).toStringAsFixed(1)} л )", style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13, fontWeight: FontWeight.w600)))
            ],
          ),
        );
      }
    );
  }
}

// === КОМЬЮНИТИ ===
class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9), 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Комьюнити', style: TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.5)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))
                ],
              ),
              child: TextField(
                style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Поиск по никнейму...',
                  hintStyle: TextStyle(color: const Color(0xFF8E8E93).withValues(alpha: 0.7)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFC7C7CC)),
                  border: InputBorder.none, 
                  contentPadding: const EdgeInsets.symmetric(vertical: 18),
                ),
              ),
            ),
          ),
          
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, 
                children: [
                  Icon(Icons.people_alt_outlined, size: 80, color: Color(0xFFE5E5EA)), 
                  SizedBox(height: 20), 
                  Text(
                    'Скоро здесь появится\nподдержка единомышленниц!', 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, height: 1.5, fontWeight: FontWeight.w500)
                  )
                ]
              )
            ),
          ),
        ],
      ),
    );
  }
}