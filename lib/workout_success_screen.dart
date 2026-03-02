import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart'; // ЛОКАЛИЗАЦИЯ

class WorkoutSuccessScreen extends StatelessWidget {
  final int durationMinutes;
  final int tonnage;
  final int exercisesCount;

  const WorkoutSuccessScreen({
    super.key,
    required this.durationMinutes,
    required this.tonnage,
    required this.exercisesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: const Color(0xFFCCFF00).withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFCCFF00).withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 10,
                    )
                  ],
                ),
                child: const Icon(Icons.emoji_events, size: 80, color: Color(0xFFCCFF00)),
              ),
              
              const SizedBox(height: 32),
              
              Text(
                "workout_completed".tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  color: Colors.white,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "stronger_than_yesterday".tr(),
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
              ),

              const SizedBox(height: 48),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem("$durationMinutes", "min_short".tr(), "time_upper".tr()),
                  _buildStatItem("$tonnage", "kg".tr(), "tonnage_upper".tr()),
                  _buildStatItem("$exercisesCount", "", "exercises_upper".tr()),
                ],
              ),

              const Spacer(),

              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("result_copied".tr())),
                  );
                },
                icon: const Icon(Icons.share, color: Colors.white),
                label: Text("share".tr(), style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              
              const SizedBox(height: 16),

              Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFCCFF00), Color(0xFFAACC00)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFCCFF00).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    "home".tr(),
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String unit, String label) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white, 
                fontSize: 32, 
                fontWeight: FontWeight.w900, 
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(color: Color(0xFFCCFF00), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        Text(
          label,
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
      ],
    );
  }
}