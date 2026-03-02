import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Добавлен intl для работы с датами
import '../services/database_service.dart';
import '../workout_session_screen.dart';

import '../widgets/base_background.dart'; 

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          title: const Text("История", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0)),
          backgroundColor: Colors.transparent, 
          elevation: 0, 
          automaticallyImplyLeading: false,
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: DatabaseService().getUserHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history, size: 60, color: Colors.grey.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    // Обновленный текст пустого состояния
                    const Text("Ваша история пуста. Время первой тренировки!", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              );
            }

            // 1. ЛОГИКА ГРУППИРОВКИ ПО МЕСЯЦАМ
            final docs = snapshot.data!.docs;
            final Map<String, List<QueryDocumentSnapshot>> groupedHistory = {};

            for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final timestamp = data['date'] as Timestamp?;
              
              String monthYearKey = "Неизвестно";
              if (timestamp != null) {
                final date = timestamp.toDate();
                // Форматируем в "Февраль 2026" (используем русскую локаль, если она настроена, или стандартную)
                try {
                  String rawFormat = DateFormat('LLLL yyyy', 'ru').format(date);
                  monthYearKey = rawFormat[0].toUpperCase() + rawFormat.substring(1);
                } catch (e) {
                  // Fallback, если локаль 'ru' не инициализирована в intl
                  monthYearKey = DateFormat('MMMM yyyy').format(date); 
                }
              }

              if (!groupedHistory.containsKey(monthYearKey)) {
                groupedHistory[monthYearKey] = [];
              }
              groupedHistory[monthYearKey]!.add(doc);
            }

            // 2. ВЕРСТКА UI (АККОРДЕОНЫ)
            final sortedKeys = groupedHistory.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: sortedKeys.length,
              itemBuilder: (context, index) {
                final monthKey = sortedKeys[index];
                final monthWorkouts = groupedHistory[monthKey]!;
                
                // Считаем сводку за месяц
                double totalMonthTonnage = 0;
                for (var doc in monthWorkouts) {
                  final data = doc.data() as Map<String, dynamic>;
                  totalMonthTonnage += (data['tonnage'] ?? 0).toDouble();
                }
                final String monthTonsStr = (totalMonthTonnage / 1000).toStringAsFixed(1);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E).withOpacity(0.6), 
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      // По умолчанию раскрываем только первый (самый свежий) месяц
                      initiallyExpanded: index == 0,
                      iconColor: const Color(0xFFCCFF00),
                      collapsedIconColor: Colors.grey,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Text(
                        monthKey, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
                      ),
                      subtitle: Text(
                        "${monthWorkouts.length} тренировок • $monthTonsStr т", 
                        style: const TextStyle(color: Colors.grey, fontSize: 13)
                      ),
                      children: monthWorkouts.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['workoutName'] ?? "Тренировка";
                        final tonnage = (data['tonnage'] ?? 0).toDouble();
                        final tonnageStr = (tonnage / 1000).toStringAsFixed(1);
                        
                        final timestamp = data['date'] as Timestamp?;
                        String dayStr = "--";
                        String weekdayStr = "";
                        
                        if (timestamp != null) {
                          final date = timestamp.toDate();
                          dayStr = DateFormat('d').format(date); // Например: "24"
                          try {
                            weekdayStr = DateFormat('E', 'ru').format(date).toLowerCase(); // Например: "вт"
                          } catch (e) {
                            weekdayStr = DateFormat('E').format(date).toLowerCase(); 
                          }
                        }

                        // 3. КАРТОЧКА ТРЕНИРОВКИ (ВНУТРИ АККОРДЕОНА)
                        return Dismissible(
                          key: Key(doc.id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  backgroundColor: const Color(0xFF1C1C1E),
                                  title: const Text("Удалить тренировку?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  content: const Text("Это действие нельзя отменить.", style: TextStyle(color: Colors.grey)),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      child: const Text("ОТМЕНА", style: TextStyle(color: Colors.white)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      child: const Text("УДАЛИТЬ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.delete_forever, color: Colors.white, size: 28),
                          ),
                          onDismissed: (_) {
                            DatabaseService().deleteHistoryItem(doc.id);
                          },
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WorkoutSessionScreen(
                                    workoutTitle: name,
                                    existingDocId: doc.id,   
                                    existingData: data,      
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))
                              ),
                              child: Row(
                                children: [
                                  // СЛЕВА: Дата и День недели
                                  SizedBox(
                                    width: 45,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(dayStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                        Text(weekdayStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Container(width: 1, height: 30, color: Colors.white.withOpacity(0.1), margin: const EdgeInsets.symmetric(horizontal: 12)),
                                  
                                  // ПО ЦЕНТРУ: Название
                                  Expanded(
                                    child: Text(
                                      name, 
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  
                                  // СПРАВА: Тоннаж и стрелочка
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("$tonnageStr т", style: const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold, fontSize: 15)),
                                      const SizedBox(height: 2),
                                      const Text("объем", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}