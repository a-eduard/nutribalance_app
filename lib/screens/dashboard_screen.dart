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
  static const Color _accentColor = Color(0xFFB76E79); 
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.white, 
          selectedItemColor: _accentColor, 
          unselectedItemColor: Colors.grey, 
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index), 
          type: BottomNavigationBarType.fixed, 
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Главная'),
            BottomNavigationBarItem(icon: Icon(Icons.people_alt_outlined), activeIcon: Icon(Icons.people), label: 'Комьюнити'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Профиль'),
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
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
                  const Text("NutriBalance", style: TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  Text("Привет, $name ✨", style: const TextStyle(color: _textColor, fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  const DailyAffirmationWidget(),

                  GestureDetector(
                    onTap: () => DailyMealsBottomSheet.show(context),
                    child: const NutritionSummaryCard(),
                  ),
                  
                  const SizedBox(height: 24),
                  const Text('ТВОЙ АССИСТЕНТ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian'))),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFD49A89)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: _accentColor.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        children: [
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28)),
                          const SizedBox(width: 16),
                          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Eva', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)), SizedBox(height: 4), Text('Твой личный нутрициолог', style: TextStyle(color: Colors.white, fontSize: 13))])),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const WaterTrackerWidget(),
                  const SizedBox(height: 24),
                  const CycleTrackerWidget(),
                  
                  const SizedBox(height: 24),
                  // НОВОЕ: Секция "Съедено сегодня"
                  const Text('СЪЕДЕНО СЕГОДНЯ', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0)),
                  const SizedBox(height: 12),
                  const ConsumedTodayWidget(),

                  const SizedBox(height: 40),
                ],
              ),
            );
          }
        ),
      ),
    );
  }
}

// === НОВЫЙ ВИДЖЕТ: Список съеденного за день ===

class ConsumedTodayWidget extends StatefulWidget {
  const ConsumedTodayWidget({super.key});

  @override
  State<ConsumedTodayWidget> createState() => _ConsumedTodayWidgetState();
}

class _ConsumedTodayWidgetState extends State<ConsumedTodayWidget> {
  String get _todayDocId => DateTime.now().toString().substring(0, 10); // Формат: YYYY-MM-DD

  Future<void> _deleteItem(String uid, DocumentSnapshot itemDoc) async {
    final data = itemDoc.data() as Map<String, dynamic>;
    final int cals = (data['calories'] as num?)?.toInt() ?? 0;
    final int p = (data['protein'] as num?)?.toInt() ?? 0;
    final int f = (data['fat'] as num?)?.toInt() ?? 0;
    final int c = (data['carbs'] as num?)?.toInt() ?? 0;

    // 1. Удаляем карточку
    await itemDoc.reference.delete();

    // 2. Вычитаем КБЖУ из общих дневных итогов
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(name, style: const TextStyle(color: Color(0xFF2D2D2D), fontWeight: FontWeight.bold, fontSize: 18)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 24, fontWeight: FontWeight.w900),
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
            child: const Text('Отмена', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB76E79),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
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

    // 1. Обновляем саму карточку продукта
    await itemDoc.reference.update({
      'grams': newGrams,
      'calories': newC,
      'protein': newP,
      'fat': newF,
      'carbs': newCarbs,
    });

    // 2. Обновляем разницу в дневных итогах
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
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.withValues(alpha: 0.1))),
            child: const Text("Вы еще ничего не записали сегодня. Напишите Еве, чтобы добавить прием пищи! 🍽", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
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
              margin: const EdgeInsets.only(bottom: 12),
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(color: Color(0xFFFDECE8), shape: BoxShape.circle),
                          child: const Text('🍎', style: TextStyle(fontSize: 18)), 
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D), fontSize: 15)),
                              const SizedBox(height: 4),
                              Text("${grams.toInt()} г", style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text("$cals ккал", style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF2D2D2D), fontSize: 16)),
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

// === СТАРЫЕ ВИДЖЕТЫ (БЕЗ ИЗМЕНЕНИЙ) ===

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
      margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFD49A89).withValues(alpha: 0.3))),
      child: Row(children: [const Text("✨", style: TextStyle(fontSize: 20)), const SizedBox(width: 12), Expanded(child: Text(phrase, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)))]),
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ВЫПИТО ВОДЫ', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(8, (index) {
                  bool isFilled = index < waterCount;
                  return GestureDetector(
                    onTap: () { int newCount = isFilled ? index : index + 1; DatabaseService().updateWaterGlasses(newCount); },
                    child: Icon(isFilled ? Icons.water_drop : Icons.water_drop_outlined, color: isFilled ? const Color(0xFF89CFF0) : Colors.grey.withValues(alpha: 0.3), size: 32),
                  );
                }),
              ),
              const SizedBox(height: 12),
              Center(child: Text("$waterCount из 8 стаканов ( ${(waterCount * 0.25).toStringAsFixed(1)} л )", style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)))
            ],
          ),
        );
      }
    );
  }
}

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: Color(0xFFF9F9F9), body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people_alt, size: 80, color: Colors.grey), SizedBox(height: 16), Text('Комьюнити', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))), SizedBox(height: 8), Text('Скоро здесь появится общий чат\nи поддержка единомышленниц!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14))])));
  }
}

class CycleTrackerWidget extends StatelessWidget {
  const CycleTrackerWidget({super.key});

  Future<void> _selectPeriodDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFB76E79), // Rose Gold
              onPrimary: Colors.white,
              onSurface: Color(0xFF2D2D2D),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      await DatabaseService().updatePeriodStartDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final Timestamp? lastPeriod = userData['lastPeriodStartDate'] as Timestamp?;
        final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;

        String dayText = "Цикл не отслеживается";
        String phaseText = "Нажмите, чтобы отметить начало цикла";
        double progress = 0.0;

        if (lastPeriod != null) {
          final start = DateTime(lastPeriod.toDate().year, lastPeriod.toDate().month, lastPeriod.toDate().day);
          final now = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
          final diff = now.difference(start).inDays;

          if (diff >= 0) {
            final int dayOfCycle = (diff % cycleLength) + 1;
            dayText = "$dayOfCycle-й день цикла";
            progress = (dayOfCycle / cycleLength).clamp(0.0, 1.0);

            if (dayOfCycle <= 5) phaseText = 'Менструация 🩸';
            else if (dayOfCycle <= 13) phaseText = 'Фолликулярная фаза 🌸';
            else if (dayOfCycle <= 15) phaseText = 'Овуляция ✨';
            else phaseText = 'Лютеиновая фаза (ПМС) 🌿';
          }
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ЖЕНСКОЕ ЗДОРОВЬЕ', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.0)),
                  GestureDetector(
                    onTap: () => _selectPeriodDate(context),
                    child: const Icon(Icons.calendar_month, color: Colors.grey, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFDECE8), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.spa, color: Color(0xFFB76E79), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(dayText, style: const TextStyle(color: Color(0xFF2D2D2D), fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(phaseText, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFFF0F0F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD49A89)),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _selectPeriodDate(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFB76E79)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Отметить начало цикла', style: TextStyle(color: Color(0xFFB76E79), fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      }
    );
  }
}