import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VolumeChart extends StatelessWidget {
  final List<DocumentSnapshot> historyDocs;

  const VolumeChart({super.key, required this.historyDocs});

  @override
  Widget build(BuildContext context) {
    if (historyDocs.isEmpty) return const SizedBox.shrink();

    // 1. Копируем и сортируем документы по дате (по возрастанию: от старых к новым)
    var sortedDocs = List<DocumentSnapshot>.from(historyDocs);
    sortedDocs.sort((a, b) {
      final tA = (a.data() as Map<String, dynamic>)['date'] as Timestamp?;
      final tB = (b.data() as Map<String, dynamic>)['date'] as Timestamp?;
      if (tA == null || tB == null) return 0;
      return tA.compareTo(tB);
    });

    // 2. Берем только последние 7 тренировок, чтобы график не превратился в кашу
    if (sortedDocs.length > 7) {
      sortedDocs = sortedDocs.sublist(sortedDocs.length - 7);
    }

    // 3. Парсим тоннаж
    List<FlSpot> spots = [];
    double maxVolume = 0;

    for (int i = 0; i < sortedDocs.length; i++) {
      double volume = 0;
      try {
        final data = sortedDocs[i].data() as Map<String, dynamic>;
        final exercises = data['exercises'] as List<dynamic>? ?? [];
        for (var ex in exercises) {
          final sets = ex['sets'] as List<dynamic>? ?? [];
          for (var set in sets) {
            double w = double.tryParse(set['weight'].toString()) ?? 0;
            double r = double.tryParse(set['reps'].toString()) ?? 0;
            volume += (w * r);
          }
        }
      } catch (e) {
        print("Ошибка парсинга объема: $e");
      }
      
      if (volume > maxVolume) maxVolume = volume;
      spots.add(FlSpot(i.toDouble(), volume));
    }

    // Если все тренировки были пустыми (0 кг), график не показываем
    if (maxVolume == 0 || spots.isEmpty) return const SizedBox.shrink();

    // 4. Отрисовка UI
    return Container(
      height: 220,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ТРЕНИРОВОЧНЫЙ ОБЪЕМ (КГ)",
            style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFFCCFF00),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true), // Показываем точки на стыках
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFCCFF00).withOpacity(0.1), // Легкое неоновое свечение внизу
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}