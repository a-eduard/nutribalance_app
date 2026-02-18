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
        // Используем поле 'date', так как мы исправили это на Этапе 1
        if (session['date'] != null) {
          final sessionDate = (session['date'] as Timestamp).toDate();
          if (sessionDate.year == date.year && 
              sessionDate.month == date.month && 
              sessionDate.day == date.day) {
            count++;
          }
        }
      }
      weeklyCounts[6 - i] = count;
    }

    // Новый акцентный цвет (Lime Green)
    const primaryColor = Color(0xFF9CD600);

    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        BarChartData(
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              // ИСПРАВЛЕНИЕ: Заменили tooltipBgColor на getTooltipColor
              getTooltipColor: (group) => const Color(0xFF1C1C1E),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${rod.toY.round()} трен.',
                  const TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
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
                  color: weeklyCounts[index] > 0 ? primaryColor : const Color(0xFF2C2C2E),
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
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