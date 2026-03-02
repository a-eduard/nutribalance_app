import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import '../widgets/base_background.dart';
import '../workout_session_screen.dart';
import '../create_workout_screen.dart';
import 'assigned_workout_preview_screen.dart';
import '../services/database_service.dart';
import '../utils/exercise_parser.dart';

class MyProgramsScreen extends StatefulWidget {
  const MyProgramsScreen({super.key});

  @override
  State<MyProgramsScreen> createState() => _MyProgramsScreenState();
}

// ЗАДАЧА 7: Добавляем SingleTickerProviderStateMixin для контроллера вкладок
class _MyProgramsScreenState extends State<MyProgramsScreen> with SingleTickerProviderStateMixin {
  static const Color _accentColor = Color(0xFF9CD600);
  
  late TabController _tabController;
  bool _hasNewProgram = false; // Локальное хранение статуса новинки

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Слушаем переключение вкладок
    _tabController.addListener(_handleTabSelection);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Сбрасываем бейдж ТОЛЬКО когда пользователь перешел на вкладку "Тренер" (индекс 2)
  void _handleTabSelection() {
    if (_tabController.index == 2 && _hasNewProgram) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('users').doc(uid).update({'hasNewProgram': false});
      }
    }
  }

  Widget _buildBadge(String source) {
    Color bgColor; Color textColor; String text; IconData icon;

    if (source == 'coach') {
      bgColor = Colors.deepOrange.withValues(alpha: 0.1);
      textColor = Colors.deepOrange;
      text = 'От тренера';
      icon = Icons.sports;
    } else if (source == 'ai') {
      bgColor = const Color(0xFF9CD600).withValues(alpha: 0.1);
      textColor = const Color(0xFF9CD600);
      text = 'От ИИ';
      icon = Icons.auto_awesome;
    } else {
      bgColor = Colors.grey.withValues(alpha: 0.1);
      textColor = Colors.grey;
      text = 'Своя';
      icon = Icons.edit;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: textColor.withValues(alpha: 0.5))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 12),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildProgramsList(List<Map<String, dynamic>> programs, String emptyMessage, String uid) {
    if (programs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(emptyMessage, style: const TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: programs.length,
      itemBuilder: (context, index) {
        final data = programs[index];
        final docId = data['docId'];
        final collectionName = data['collectionName'];
        final source = data['source'];
        
        final name = data['name'] ?? 'untitled'.tr();
        
        final List<dynamic> rawExercises = data['exercises'] as List<dynamic>? ?? [];
        final Map<String, dynamic> targets = Map<String, dynamic>.from(data['targets'] ?? {});

        return Dismissible(
          key: Key(docId),
          direction: DismissDirection.endToStart, 
          background: Container(alignment: Alignment.centerRight, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.only(right: 24), decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.delete_outline, color: Colors.white, size: 28)),
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1C1C1E),
                title: Text('delete_program_title'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: Text('delete_program_desc'.tr(), style: const TextStyle(color: Colors.grey)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr(), style: const TextStyle(color: Colors.white))),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('delete'.tr(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                ],
              ),
            );
          },
          onDismissed: (direction) async {
            await FirebaseFirestore.instance.collection('users').doc(uid).collection(collectionName).doc(docId).delete();
          },
          child: GestureDetector(
            onTap: () {
              if (source == 'coach') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AssignedWorkoutPreviewScreen(workoutId: docId, workoutData: data)));
              } else {
                List<String> simpleNames = rawExercises.map((e) {
                  final parsed = ExerciseParser.parse(e, targets);
                  return parsed.name;
                }).toList();
                
                Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutSessionScreen(
                  workoutTitle: name, 
                  initialExercises: simpleNames, 
                  workoutId: docId,
                  existingData: data, 
                )));
              }
            },
            onLongPress: () {
              if (source != 'coach') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => CreateWorkoutScreen(existingDocId: docId, existingData: data)));
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                      _buildBadge(source), 
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text("${rawExercises.length} ${'exercises_count'.tr()}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                  iconColor: _accentColor,
                  collapsedIconColor: _accentColor,
                  
                  children: rawExercises.map<Widget>((rawEx) {
                    final parsed = ExerciseParser.parse(rawEx, targets);

                    return ListTile(
                      dense: true, 
                      title: Text(parsed.name.tr(), style: const TextStyle(color: Colors.white)), 
                      subtitle: parsed.notes.isNotEmpty ? Text(parsed.notes, style: const TextStyle(color: _accentColor, fontSize: 12)) : null, 
                      visualDensity: VisualDensity.compact
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Scaffold(backgroundColor: Colors.black, body: Center(child: Text("auth_error".tr(), style: const TextStyle(color: Colors.white))));

    // ЗАДАЧА 7: Оборачиваем весь экран в StreamBuilder, чтобы реагировать на приход новой программы
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        
        if (userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data() as Map<String, dynamic>;
          _hasNewProgram = userData['hasNewProgram'] == true;
        }

        return BaseBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: const Color(0xFF1C1C1E),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text('Программы тренировок', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add, color: _accentColor),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateWorkoutScreen())),
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: _accentColor,
                labelColor: _accentColor,
                unselectedLabelColor: Colors.grey,
                tabs: [
                  const Tab(text: "Свои"),
                  const Tab(text: "От ИИ"),
                  Tab(
                    // ЗАДАЧА 7: Бейдж на вкладке Тренера
                    child: Badge(
                      isLabelVisible: _hasNewProgram,
                      backgroundColor: Colors.redAccent,
                      smallSize: 10,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 8.0),
                        child: Text("Тренер"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('assigned_workouts').snapshots(),
                    builder: (context, assignedSnapshot) {
                      return StreamBuilder<QuerySnapshot>(
                        stream: DatabaseService().getUserWorkouts(),
                        builder: (context, workoutsSnapshot) {
                          if (workoutsSnapshot.connectionState == ConnectionState.waiting && assignedSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: _accentColor));
                          }
                          
                          List<Map<String, dynamic>> customPrograms = [];
                          List<Map<String, dynamic>> aiPrograms = [];
                          List<Map<String, dynamic>> coachPrograms = [];

                          if (assignedSnapshot.hasData) {
                            for (var doc in assignedSnapshot.data!.docs) {
                              var data = doc.data() as Map<String, dynamic>;
                              data['docId'] = doc.id;
                              data['source'] = 'coach'; 
                              data['collectionName'] = 'assigned_workouts';
                              coachPrograms.add(data);
                            }
                          }

                          if (workoutsSnapshot.hasData) {
                            for (var doc in workoutsSnapshot.data!.docs) {
                              var data = doc.data() as Map<String, dynamic>;
                              data['docId'] = doc.id;
                              data['collectionName'] = 'workouts';
                              
                              String source = data['source'] ?? 'custom';
                              data['source'] = source;

                              if (source == 'ai') {
                                aiPrograms.add(data);
                              } else {
                                customPrograms.add(data); 
                              }
                            }
                          }

                          void sortPrograms(List<Map<String, dynamic>> list) {
                            list.sort((a, b) {
                              Timestamp tA = a['createdAt'] ?? a['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
                              Timestamp tB = b['createdAt'] ?? b['date'] ?? Timestamp.fromMillisecondsSinceEpoch(0);
                              return tB.compareTo(tA);
                            });
                          }
                          
                          sortPrograms(customPrograms);
                          sortPrograms(aiPrograms);
                          sortPrograms(coachPrograms);

                          return TabBarView(
                            controller: _tabController,
                            children: [
                              _buildProgramsList(customPrograms, "Здесь пока нет ваших программ", uid),
                              _buildProgramsList(aiPrograms, "Вы еще не сохраняли программы от ИИ", uid),
                              _buildProgramsList(coachPrograms, "Тренер пока не назначил вам программы", uid),
                            ],
                          );
                        },
                      );
                    }
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}