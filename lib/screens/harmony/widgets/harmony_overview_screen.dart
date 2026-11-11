import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../theme/eva_colors.dart';
import '../../../widgets/eva_ui.dart';
import '../../../widgets/weight_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
          title: const Text("Обзор"),
          bottom: TabBar(
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: "Статистика"),
              Tab(text: "Вес"),
              Tab(text: "Для врача"),
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Цикл", style: TextStyle(fontSize: 20, fontFamily: EvaFonts.serif, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 12),
              _statRowCard(theme, [
                ('Последние месячные', lastStart != null ? DateFormat('d MMM', 'ru_RU').format(lastStart.toDate()) : '—', PhosphorIconsFill.drop),
                ('Длина цикла', '${data['cycleLength'] ?? 0} дн.', PhosphorIconsLight.arrowsClockwise),
                ('Месячные', '${data['periodDuration'] ?? 0} дн.', PhosphorIconsLight.calendarBlank),
              ]),
              const SizedBox(height: 28),
              Text("Близость", style: TextStyle(fontSize: 20, fontFamily: EvaFonts.serif, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 12),
              _intimacyTable(theme, data),
              const SizedBox(height: 10),
              Text('Видно только тебе. В отчёт для врача попадает, только если включишь это при выгрузке.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _statRowCard(ThemeData theme, List<(String, String, IconData)> items) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.eva.hairline)),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: Column(children: [
                Icon(it.$3, size: 22, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(it.$1, textAlign: TextAlign.center, maxLines: 2, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _intimacyTable(ThemeData theme, Map<String, dynamic> d) {
    TextStyle head = theme.textTheme.labelMedium!.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget cell(String t, {bool bold = false, TextAlign align = TextAlign.center}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(t, textAlign: align, style: bold ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) : theme.textTheme.bodyMedium),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.eva.hairline)),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.6), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            const SizedBox(),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Неделя', textAlign: TextAlign.center, style: head)),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Месяц', textAlign: TextAlign.center, style: head)),
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Год', textAlign: TextAlign.center, style: head)),
          ]),
          TableRow(children: [
            cell('Близость', align: TextAlign.left),
            cell('${d['sexWeek'] ?? 0}', bold: true),
            cell('${d['sexMonth'] ?? 0}', bold: true),
            cell('${d['sexYear'] ?? 0}', bold: true),
          ]),
          TableRow(children: [
            cell('Оргазмы', align: TextAlign.left),
            cell('${d['orgasmsWeek'] ?? 0}', bold: true),
            cell('${d['orgasmsMonth'] ?? 0}', bold: true),
            cell('${d['orgasmsYear'] ?? 0}', bold: true),
          ]),
        ],
      ),
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
                Text("Динамика веса", style: theme.textTheme.titleLarge),
                const SizedBox(height: 24),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('weight_logs')
                      .where('date', isGreaterThanOrEqualTo: _getCutoffDateString(_selectedPeriodDays))
                      .orderBy('date', descending: false).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.length < 2) return SizedBox(height: 200, child: Center(child: Text("Отметь вес хотя бы в два разных дня — появится график", textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))));

                    return WeightLineChart(points: [
                      for (final d in docs)
                        MapEntry((d.data() as Map<String, dynamic>)['date'].toString(), ((d.data() as Map<String, dynamic>)['weight'] as num).toDouble()),
                    ]);
                  },
                ),
              ],
            ),
          )
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
                Icon(PhosphorIconsLight.filePdf, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text("Отчёт для врача", style: TextStyle(fontSize: 22, fontFamily: EvaFonts.serif, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 12),
                Text("PDF за 3 месяца: параметры цикла и прогноз, симптомы, настроение, препараты, температура и вес. Удобно отправить врачу перед приёмом.", textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14, height: 1.4)),
                const SizedBox(height: 24),
                
                Container(
                  decoration: BoxDecoration(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                  child: SwitchListTile(
                    activeTrackColor: theme.colorScheme.primary,
                    title: Text("Скрыть интимные детали", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    subtitle: Text("Данные о близости не попадут в отчёт", style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    value: _hideIntimateDetails,
                    onChanged: (val) => setState(() => _hideIntimateDetails = val),
                  ),
                ),
                
                const SizedBox(height: 32),
                EvaPrimaryButton(
                  label: 'Скачать PDF',
                  icon: PhosphorIconsLight.downloadSimple,
                  loading: _isGeneratingPdf,
                  onPressed: _isGeneratingPdf
                      ? null
                      : () async {
                          setState(() => _isGeneratingPdf = true);
                          try {
                            await PdfReportService.generateAndShareHarmonyReport(hideIntimateDetails: _hideIntimateDetails);
                          } catch (e) {
                            debugPrint('pdf: $e');
                            if (mounted) EvaSnack.show(context, 'Не получилось собрать отчёт. Попробуй ещё раз.', type: EvaSnackType.error);
                          } finally {
                            if (mounted) setState(() => _isGeneratingPdf = false);
                          }
                        },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}