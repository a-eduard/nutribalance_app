import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

import '../widgets/base_background.dart'; 
import '../screens/profile_screen.dart'; 
import '../screens/history_screen.dart';
import '../screens/coach_list_screen.dart'; 
import '../screens/p2p_chat_screen.dart';
import '../screens/assigned_workout_preview_screen.dart';
import '../screens/ai_hub_screen.dart';
import '../workout_session_screen.dart';
import '../create_workout_screen.dart';
import '../services/database_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  static const Color _accentColor = Color(0xFF9CD600);

  final List<Widget> _screens = [
    const HomeTab(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        body: _screens[_currentIndex],
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFF1C1C1E)))),
          child: BottomNavigationBar(
            backgroundColor: const Color(0xFF000000), 
            selectedItemColor: _accentColor,
            unselectedItemColor: Colors.grey,
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(icon: const Icon(Icons.fitness_center), label: 'workouts_tab'.tr()),
              BottomNavigationBarItem(icon: const Icon(Icons.history), label: 'history_tab'.tr()),
              BottomNavigationBarItem(icon: const Icon(Icons.person), label: 'profile_tab'.tr()),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  static const Color _accentColor = Color(0xFF9CD600);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Center(child: Text("error_msg".tr(), style: const TextStyle(color: Colors.white)));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TONNA GYM", style: TextStyle(color: _accentColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                      builder: (context, snapshot) {
                        final name = (snapshot.data?.data() as Map<String, dynamic>?)?['name']?.toString() ?? '';
                        return Text(
                          name.isNotEmpty ? "${'hello'.tr()}, ${name.toUpperCase()}" : 'hello_athlete'.tr(), 
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)
                        );
                      },
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: _accentColor),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiHubScreen())),
                ),
              ],
            ),
            const SizedBox(height: 16),

            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, userSnapshot) {
                final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                final coachId = userData?['currentCoachId'];

                if (coachId == null || coachId.toString().isEmpty) return const SizedBox.shrink();

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(coachId).snapshots(),
                  builder: (context, coachSnapshot) {
                    final coachData = coachSnapshot.data?.data() as Map<String, dynamic>?;
                    final coachName = coachData?['name'] ?? 'my_coach'.tr();
                    final coachPhoto = coachData?['photoUrl'] ?? '';

                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('assigned_workouts').orderBy('date', descending: true).limit(1).snapshots(),
                      builder: (context, workoutSnapshot) {
                        final workouts = workoutSnapshot.data?.docs ?? [];
                        final hasWorkout = workouts.isNotEmpty;
                        final workoutDoc = hasWorkout ? workouts.first : null;
                        final workoutData = workoutDoc?.data() as Map<String, dynamic>?;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Colors.grey[800],
                                    backgroundImage: coachPhoto.isNotEmpty ? MemoryImage(base64Decode(coachPhoto)) : null,
                                    child: coachPhoto.isEmpty ? const Icon(Icons.person, color: Colors.white54) : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(coachName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline, color: _accentColor),
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: coachId, otherUserName: coachName))), 
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white12, height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(hasWorkout ? (workoutData?['name'] ?? 'coach_program'.tr()) : 'no_programs'.tr(), style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  if (hasWorkout && workoutDoc != null)
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: _accentColor, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignedWorkoutPreviewScreen(workoutId: workoutDoc.id, workoutData: workoutData ?? {}))),
                                      child: Text('open'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),

            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoachListScreen())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: _accentColor.withOpacity(0.3), width: 1.5)),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _accentColor.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.people, color: _accentColor, size: 24)),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('marketplace'.tr().toUpperCase(), style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
                        Text('find_coach'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('my_programs'.tr(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateWorkoutScreen())),
                  child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _accentColor, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.add, color: Colors.black, size: 20)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: DatabaseService().getUserWorkouts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: _accentColor));
                  
                  final docs = snapshot.data?.docs ?? [];
                  
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fitness_center, size: 48, color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          Text('no_programs'.tr(), style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final name = data['name'] ?? 'untitled'.tr();
                      final exercises = (data['exercises'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
                      final targets = Map<String, dynamic>.from(data['targets'] ?? {});

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart, 
                        background: Container(alignment: Alignment.centerRight, margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.only(right: 24), decoration: BoxDecoration(color: Colors.red.withOpacity(0.9), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.delete_outline, color: Colors.white, size: 28)),
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
                        onDismissed: (direction) async => await DatabaseService().deleteWorkout(doc.id),
                        child: GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutSessionScreen(workoutTitle: name, initialExercises: exercises, workoutId: doc.id))),
                          onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateWorkoutScreen(existingDocId: doc.id, existingData: data))),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(color: const Color(0xFF1C1C1E).withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
                            child: Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                subtitle: Text("${exercises.length} ${'exercises_count'.tr()}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                iconColor: _accentColor,
                                collapsedIconColor: _accentColor,
                                children: exercises.map<Widget>((exName) {
                                  String comment = "";
                                  if (targets.containsKey(exName)) {
                                    final parts = targets[exName].toString().split('|');
                                    if (parts.length > 1) comment = parts[1];
                                  }
                                  return ListTile(dense: true, title: Text(exName.tr(), style: const TextStyle(color: Colors.white)), subtitle: comment.isNotEmpty ? Text(comment, style: const TextStyle(color: _accentColor, fontSize: 12)) : null, visualDensity: VisualDensity.compact);
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}