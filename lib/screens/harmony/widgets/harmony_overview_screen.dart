import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../services/database_service.dart';
import '../../../../services/pdf_report_service.dart';

class HarmonyOverviewScreen extends StatefulWidget {
  const HarmonyOverviewScreen({super.key});

  @override
  State<HarmonyOverviewScreen> createState() => _HarmonyOverviewScreenState();
}

class _HarmonyOverviewScreenState extends State<HarmonyOverviewScreen> {
  int _selectedPeriodDays = 30; 
  bool _hideIntimateDetails = true; 
  bool _isGeneratingPdf = false;

  String _getCutoffDateString(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return "${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          elevation: 0,
          iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
          title: Text("Обзор", style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w900)),
          centerTitle: true,
          bottom: TabBar(
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: "Статистика"),
              Tab(text: "Вес"),
              Tab(text: "PDF Отчет"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildStatsTab(theme),
            _buildWeightTab(theme),
            _buildPdfTab(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab(ThemeData theme) {
    return FutureBuilder<Map<String, dynamic>>(
      future: DatabaseService().getHarmonyStatistics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
        final data = snapshot.data ?? {};

        final Timestamp? lastStart = data['lastPeriodStartDate'] as Timestamp?;
        String lastPeriodStr = lastStart != null ? DateFormat('dd MMMM yyyy', 'ru_RU').format(lastStart.toDate()) : 'Нет данных';

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Цикл", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              _buildStatCard("Последняя менструация", lastPeriodStr, Icons.water_drop, theme.colorScheme.primary, theme),
              _buildStatCard("Средняя длина цикла", "${data['cycleLength'] ?? 0} дн.", Icons.loop, Colors.teal, theme),
              _buildStatCard("Продолжительность месячных", "${data['periodDuration'] ?? 0} дн.", Icons.calendar_today, Colors.orange, theme),
              
              const SizedBox(height: 32),
              Text("Секс (Количество занятий)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              _buildStatCard("За неделю", "${data['sexWeek'] ?? 0}", Icons.favorite, Colors.pinkAccent, theme),
              _buildStatCard("За месяц", "${data['sexMonth'] ?? 0}", Icons.favorite, Colors.pinkAccent, theme),
              _buildStatCard("За год", "${data['sexYear'] ?? 0}", Icons.favorite, Colors.pinkAccent, theme),

              const SizedBox(height: 32),
              Text("Интимность (Оргазмы)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 16),
              _buildStatCard("За неделю", "${data['orgasmsWeek'] ?? 0}", Icons.auto_awesome, Colors.deepPurpleAccent, theme),
              _buildStatCard("За месяц", "${data['orgasmsMonth'] ?? 0}", Icons.auto_awesome, Colors.deepPurpleAccent, theme),
              _buildStatCard("За год", "${data['orgasmsYear'] ?? 0}", Icons.bar_chart, Colors.blueAccent, theme),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeightTab(ThemeData theme) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
                7: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Неделя', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface))),
                30: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface))),
                180: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Полгода', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface))),
              },
              onValueChanged: (v) { if (v != null) setState(() => _selectedPeriodDays = v); },
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 6))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Динамика веса", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 24),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('weight_logs')
                      .where('date', isGreaterThanOrEqualTo: _getCutoffDateString(_selectedPeriodDays))
                      .orderBy('date', descending: false).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.length < 2) return SizedBox(height: 200, child: Center(child: Text("Недостаточно данных", style: TextStyle(color: theme.colorScheme.onSurfaceVariant))));

                    List<FlSpot> spots = [];
                    List<String> dates = [];
                    for (int i = 0; i < docs.length; i++) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      spots.add(FlSpot(i.toDouble(), (data['weight'] as num).toDouble()));
                      dates.add((data['date'] as String).substring(5).replaceAll('-', '.'));
                    }

                    int step = (dates.length / 5).ceil();
                    if (step == 0) step = 1;

                    return SizedBox(
                      height: 220,
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: FlTitlesData(
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) {
                                int idx = val.toInt();
                                if (idx % step == 0 && idx < dates.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(dates[idx], style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)));
                                return const SizedBox();
                              }),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots, isCurved: true, color: theme.colorScheme.primary, barWidth: 4,
                              dotData: FlDotData(show: docs.length <= 30),
                              belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: 0.1)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color iconColor, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, color: iconColor, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, fontWeight: FontWeight.w600))),
          Text(value, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildPdfTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))]),
            child: Column(
              children: [
                Icon(Icons.picture_as_pdf_rounded, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text("Экспорт для врача", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 12),
                Text("Сгенерируйте подробный отчет о циклах, симптомах и весе в формате PDF.", textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, height: 1.4)),
                const SizedBox(height: 24),
                
                Container(
                  decoration: BoxDecoration(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    activeTrackColor: theme.colorScheme.primary,
                    title: Text("Скрыть интимные детали", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    subtitle: Text("Уберет данные о сексе и либидо из отчета", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    value: _hideIntimateDetails,
                    onChanged: (val) => setState(() => _hideIntimateDetails = val),
                  ),
                ),
                
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                    onPressed: _isGeneratingPdf 
                      ? null 
                      : () async {
                          setState(() => _isGeneratingPdf = true);
                          try {
                            await PdfReportService.generateAndShareHarmonyReport(
                              hideIntimateDetails: _hideIntimateDetails,
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка генерации: $e'), backgroundColor: Colors.red));
                            }
                          } finally {
                            if (mounted) setState(() => _isGeneratingPdf = false);
                          }
                      },
                    child: _isGeneratingPdf 
                      ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: theme.colorScheme.onPrimary, strokeWidth: 2))
                      : Text("СГЕНЕРИРОВАТЬ PDF", style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}