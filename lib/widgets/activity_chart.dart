import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ActivityChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;

  const ActivityChart({super.key, required this.history});

  @override
  Widget build(BuildContext context) {
    // 1. Подготовка данных за последние 7 дней
    final now = DateTime.now();
    final List<int> weeklyCounts = List.filled(7, 0);
    final List<String> weekDays = [];

    // Генерируем дни недели (Пн, Вт...) и считаем тренировки
    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      weekDays.add(DateFormat.E('ru').format(date)); // E - день недели (Пн)

      // Считаем совпадения в истории
      int count = 0;
      for (var session in history) {
        if (session['completedAt'] != null) {
          final sessionDate = (session['completedAt'] as Timestamp).toDate();
          if (sessionDate.year == date.year && 
              sessionDate.month == date.month && 
              sessionDate.day == date.day) {
            count++;
          }
        }
      }
      weeklyCounts[6 - i] = count;
    }

    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        BarChartData(
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              // ИСПРАВЛЕНИЕ: Используем tooltipBgColor вместо getTooltipColor
              tooltipBgColor: const Color(0xFF1C1C1E),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${rod.toY.round()} трен.',
                  const TextStyle(color: Color(0xFFCCFF00), fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      weekDays[value.toInt()],
                      style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(7, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: weeklyCounts[index].toDouble(),
                  color: weeklyCounts[index] > 0 ? const Color(0xFFCCFF00) : const Color(0xFF2C2C2E),
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                  // Если backDrawRodData тоже вызовет ошибку, просто удалите этот блок backDrawRodData
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: 3, 
                    color: const Color(0xFF1C1C1E),
                  ),
                ),
              ],
            );
          }),
          gridData: const FlGridData(show: false),
        ),
      ),
    );
  }
}