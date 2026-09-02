import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  int _selectedPeriodDays = 7;

  String _getCutoffDateString(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return "${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);

    if (user == null) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          "Мой прогресс",
          style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _selectedPeriodDays,
                backgroundColor: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                thumbColor: theme.colorScheme.surface,
                children: {
                  7: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('7 дней', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                  30: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                  365: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Год', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                },
                onValueChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedPeriodDays = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 32),

            Text(
              "Динамика веса",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            _buildWeightChart(user.uid, theme),
            const SizedBox(height: 40),
            
            Text(
              "Дефицит и профицит",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 16),
            _buildCaloriesChart(user.uid, theme),
            const SizedBox(height: 12),
            
            Center(
              child: Text(
                "Выше оси — дефицит, ниже — профицит",
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightChart(String uid, ThemeData theme) {
    String cutoffDate = _getCutoffDateString(_selectedPeriodDays);

    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('users').doc(uid).collection('weight_logs')
          .where('date', isGreaterThanOrEqualTo: cutoffDate)
          .orderBy('date', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.length < 2) {
          return _buildEmptyState("Добавьте больше данных о весе для отображения графика", theme);
        }

        List<FlSpot> spots = [];
        List<String> dates = [];
        
        for (int i = 0; i < docs.length; i++) {
          final data = docs[i].data() as Map<String, dynamic>;
          final weight = (data['weight'] as num).toDouble();
          final dateStr = data['date'] as String; 
          spots.add(FlSpot(i.toDouble(), weight));
          dates.add(dateStr.substring(5).replaceAll('-', '.')); 
        }

        double firstWeight = (docs.first.data() as Map<String, dynamic>)['weight'].toDouble();
        double lastWeight = (docs.last.data() as Map<String, dynamic>)['weight'].toDouble();
        double diff = lastWeight - firstWeight;

        Widget summaryWidget;
        if (diff < 0) {
          summaryWidget = Text("За $_selectedPeriodDays дней: минус ${diff.abs().toStringAsFixed(1)} кг", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16));
        } else if (diff > 0) {
          summaryWidget = Text("За $_selectedPeriodDays дней: плюс ${diff.toStringAsFixed(1)} кг", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16));
        } else {
          summaryWidget = Text("Вес стабилен", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16));
        }

        int step = (dates.length / 6).ceil();
        if (step == 0) {
          step = 1;
        }

        return Column(
          children: [
            Container(
              height: 220,
              padding: const EdgeInsets.only(right: 16, top: 16),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx % step == 0 && idx < dates.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(dates[idx], style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 4,
                      dotData: FlDotData(show: docs.length <= 30),
                      belowBarData: BarAreaData(
                        show: true,
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            summaryWidget, 
          ],
        );
      },
    );
  }

  Widget _buildCaloriesChart(String uid, ThemeData theme) {
    String cutoffDate = _getCutoffDateString(_selectedPeriodDays);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _db.collection('users').doc(uid).collection('meals')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoffDate)
            .orderBy(FieldPath.documentId, descending: false)
            .get(),
        _db.collection('users').doc(uid).collection('nutrition_goal').doc('current').get(),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
        }

        final mealDocs = (snapshot.data?[0] as QuerySnapshot).docs;
        final goalDoc = snapshot.data?[1] as DocumentSnapshot;
        final double targetCals = (goalDoc.data() as Map<String, dynamic>?)?['calories']?.toDouble() ?? 2000;

        if (mealDocs.isEmpty) {
          return _buildEmptyState("Записывайте приемы пищи, чтобы увидеть статистику", theme);
        }

        List<BarChartGroupData> groups = [];
        double totalDiff = 0; 

        for (int i = 0; i < mealDocs.length; i++) {
          final data = mealDocs[i].data() as Map<String, dynamic>;
          final cals = (data['calories'] as num?)?.toDouble() ?? 0;

          double diff = 0;
          if (cals > 0) {
            diff = targetCals - cals; 
            totalDiff += diff; 
          }

          double barW = 18;
          if (mealDocs.length > 60) {
            barW = 2;
          } else if (mealDocs.length > 30) {
            barW = 6;
          }

          groups.add(
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: diff,
                  color: diff >= 0 ? theme.colorScheme.primary : Colors.redAccent.withValues(alpha: 0.7),
                  width: barW,
                  borderRadius: BorderRadius.circular(4), 
                )
              ],
            ),
          );
        }

        Widget summaryWidget;
        if (totalDiff > 0) {
          summaryWidget = Text("Общий дефицит за период: ${totalDiff.toInt()} ккал", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16));
        } else if (totalDiff < 0) {
          summaryWidget = Text("Общий профицит за период: ${totalDiff.abs().toInt()} ккал", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16));
        } else {
          summaryWidget = Text("Баланс за период соблюден", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16));
        }

        int step = (mealDocs.length / 6).ceil();
        if (step == 0) {
          step = 1;
        }

        return Column(
          children: [
            Container(
              height: 250,
              padding: const EdgeInsets.only(top: 20),
              child: BarChart(
                BarChartData(
                  barGroups: groups,
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => theme.colorScheme.onSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        String text;
                        if (rod.toY > 0) {
                          text = '+${rod.toY.toInt()} ккал\n(Дефицит)';
                        } else if (rod.toY < 0) {
                          text = '${rod.toY.toInt()} ккал\n(Профицит)';
                        } else {
                          text = '0 ккал';
                        }
                        return BarTooltipItem(
                          text,
                          TextStyle(color: theme.colorScheme.surface, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int idx = value.toInt();
                          if (idx % step == 0 && idx < mealDocs.length) {
                            String id = mealDocs[idx].id; 
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(id.substring(5).replaceAll('-', '.'), style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 0,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            summaryWidget, 
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String message, ThemeData theme) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
          ),
        ),
      ),
    );
  }
}