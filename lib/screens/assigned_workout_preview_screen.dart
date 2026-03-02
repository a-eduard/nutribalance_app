import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/exercise_parser.dart';
import '../workout_session_screen.dart'; 

class AssignedWorkoutPreviewScreen extends StatelessWidget {
  final String workoutId;
  final Map<String, dynamic> workoutData;

  const AssignedWorkoutPreviewScreen({
    super.key, 
    required this.workoutId, 
    required this.workoutData
  });

  @override
  Widget build(BuildContext context) {
    final String name = workoutData['name'] ?? 'Тренировка';
    final String coachNotes = workoutData['coachNotes'] ?? ''; 
    final List<dynamic> rawExercises = workoutData['exercises'] ?? [];
    final Map<String, dynamic> targets = Map<String, dynamic>.from(workoutData['targets'] ?? {});

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ОБЩИЕ СОВЕТЫ НА ВСЮ ТРЕНИРОВКУ
                  if (coachNotes.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF9CD600).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF9CD600).withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF9CD600)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              coachNotes,
                              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // СПИСОК УПРАЖНЕНИЙ (КАК У ИИ)
                  ...List.generate(rawExercises.length, (index) {
                    final rawEx = rawExercises[index].toString();
                    final parsed = ExerciseParser.parse(rawEx, targets);

                    String targetText = "";
                    String coachTip = "";

                    if (parsed.notes.isNotEmpty) {
                      if (parsed.notes.contains('💡')) {
                        final parts = parsed.notes.split('💡');
                        targetText = parts[0].trim(); 
                        coachTip = parts.sublist(1).join('💡').trim(); 
                      } else if (parsed.notes.contains('🎯') || parsed.notes.contains('Подходы:')) {
                        targetText = parsed.notes.trim();
                      } else {
                        coachTip = parsed.notes.trim();
                      }
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10), 
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${index + 1}. ${parsed.name.tr()}", 
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                          ),
                          
                          if (targetText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              targetText, 
                              style: TextStyle(color: Colors.grey[400], fontSize: 13, fontStyle: FontStyle.italic),
                            ),
                          ],

                          if (coachTip.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Theme(
                                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCCFF00).withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.2)),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                                    iconColor: const Color(0xFFCCFF00),
                                    collapsedIconColor: const Color(0xFFCCFF00),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.lightbulb_outline, color: Color(0xFFCCFF00), size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Комментарий тренера', 
                                          style: TextStyle(color: Color(0xFFCCFF00), fontSize: 13, fontWeight: FontWeight.bold)
                                        ),
                                      ],
                                    ),
                                    children: [
                                      Text(
                                        coachTip.replaceAll(RegExp(r'(Совет\s*:|notes\s*:)'), '').trim(), 
                                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            
            Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: const BoxDecoration(color: Color(0xFF1C1C1E), border: Border(top: BorderSide(color: Colors.white10))),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF9CD600),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context, 
                    MaterialPageRoute(
                      builder: (_) => WorkoutSessionScreen(
                        workoutTitle: name,
                        existingData: workoutData,
                        workoutId: workoutId,
                        assignedWorkoutId: workoutId,
                      )
                    )
                  );
                },
                child: const Text('НАЧАТЬ ТРЕНИРОВКУ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            )
          ],
        ),
      ),
    );
  }
}