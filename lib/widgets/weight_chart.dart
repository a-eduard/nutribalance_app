// График веса: общий для «Мой прогресс» и «Обзор → Вес».
// Ровная шкала (целые кг), даты в формате ДД.ММ без повторов, без «перелёта» кривой.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class WeightLineChart extends StatelessWidget {
  /// Точки по возрастанию даты: ключ — 'yyyy-MM-dd', значение — кг.
  final List<MapEntry<String, double>> points;
  final double height;

  const WeightLineChart({super.key, required this.points, this.height = 220});

  static String kg(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = [for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)];
    final dates = [for (final p in points) p.key.length >= 10 ? '${p.key.substring(8, 10)}.${p.key.substring(5, 7)}' : p.key];
    final double minW = points.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final double maxW = points.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final double minY = (minW - 1).floorToDouble();
    final double maxY = (maxW + 1).ceilToDouble();
    final double yStep = ((maxY - minY) / 4).ceilToDouble().clamp(1, 100).toDouble();
    final int step = (dates.length / 5).ceil().clamp(1, 1000);
    final Color muted = theme.colorScheme.onSurfaceVariant;

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: 12, top: 8),
        child: LineChart(
          LineChartData(
            minY: minY,
            maxY: maxY,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yStep,
              getDrawingHorizontalLine: (_) => FlLine(color: muted.withValues(alpha: 0.12), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: yStep,
                  getTitlesWidget: (value, meta) => ((value - minY) % yStep).abs() > 0.01
                      ? const SizedBox()
                      : Text(kg(value), style: TextStyle(fontSize: 10, color: muted)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    final int idx = value.toInt();
                    if (value != idx.toDouble() || idx % step != 0 || idx >= dates.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 8), child: Text(dates[idx], style: TextStyle(fontSize: 10, color: muted)));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (items) => items
                    .map((it) => LineTooltipItem('${kg(it.y)} кг\n${dates[it.x.toInt()]}', const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)))
                    .toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: theme.colorScheme.primary,
                barWidth: 3,
                dotData: FlDotData(show: points.length <= 30),
                belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: 0.10)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
