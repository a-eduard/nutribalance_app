import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_service.dart';

/// Отчёт для врача: кто пациентка, параметры цикла и прогноз, сводка за 3 месяца
/// (как часто встречались симптомы, настроение, препараты, динамика веса и БТТ)
/// и подневная таблица. Все данные — то, что пользовательница сама внесла в приложение.
class PdfReportService {
  static const int _days = 90;
  static final PdfColor _accent = PdfColor.fromInt(0xFF9E4F65);
  static final PdfColor _accentLight = PdfColor.fromInt(0xFFF6ECEF);

  static Future<void> generateAndShareHarmonyReport({
    required bool hideIntimateDetails,
  }) async {
    final dbService = DatabaseService();
    final user = dbService.currentUser;
    if (user == null) {
      throw Exception("Пользователь не авторизован");
    }

    // 1. Сбор данных
    final stats = await dbService.getHarmonyStatistics();
    final logs = await _getRecentCycleLogs(_days);
    final userSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final Map<String, dynamic> profile = userSnap.data() ?? {};
    final weights = await _getWeights(user.uid, _days);

    // Встроенные шрифты с кириллицей (работают офлайн).
    final fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf'));

    final pdf = pw.Document();
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: _days));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 28),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('«Моя Ева» · стр. ${ctx.pageNumber} из ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (pw.Context context) {
          return [
            _buildHeader(fontBold, now, from),
            pw.SizedBox(height: 14),
            _buildPatient(fontBold, profile, weights),
            pw.SizedBox(height: 12),
            _buildCycle(fontBold, profile, stats, now),
            pw.SizedBox(height: 12),
            _buildFrequency(fontBold, logs, weights, hideIntimateDetails, stats),
            pw.SizedBox(height: 16),
            pw.Text("Дневник по дням", style: pw.TextStyle(font: fontBold, fontSize: 14)),
            pw.SizedBox(height: 6),
            _buildLogsTable(fontBold, logs, hideIntimateDetails, stats),
            pw.SizedBox(height: 14),
            pw.Text(
              'Данные внесены пользовательницей вручную в приложении «Моя Ева». День цикла и прогнозы рассчитаны '
              'по последней дате начала месячных и средней длине цикла — это ориентир, а не диагноз.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'myeva_report_${DateFormat('yyyy_MM_dd').format(now)}.pdf',
    );
  }

  // ---------------------------------------------------------------------------
  // Данные
  // ---------------------------------------------------------------------------

  static String _key(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static Future<List<Map<String, dynamic>>> _getRecentCycleLogs(int days) async {
    final dbService = DatabaseService();
    final cutoffStr = _key(DateTime.now().subtract(Duration(days: days)));
    final uid = dbService.currentUser!.uid;
    final logsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cycle_logs')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoffStr)
        .get();
    final docs = logsSnap.docs.map((d) => {'date': d.id, ...d.data()}).where(_hasAnyData).toList();
    docs.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return docs;
  }

  static bool _hasAnyData(Map<String, dynamic> log) =>
      log['temperature'] != null ||
      log['weight'] != null ||
      (log['symptoms'] is Map && (log['symptoms'] as Map).isNotEmpty) ||
      (log['moods'] is List && (log['moods'] as List).isNotEmpty) ||
      (log['mood'] != null && log['mood'].toString().isNotEmpty) ||
      (log['meds'] is List && (log['meds'] as List).isNotEmpty) ||
      (log['sex_data'] is List && (log['sex_data'] as List).isNotEmpty);

  /// Вес за период: [дата, кг] по возрастанию даты.
  static Future<List<MapEntry<DateTime, double>>> _getWeights(String uid, int days) async {
    try {
      final cutoffStr = _key(DateTime.now().subtract(Duration(days: days)));
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('weight_logs')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoffStr)
          .get();
      final out = <MapEntry<DateTime, double>>[];
      for (final d in snap.docs) {
        final date = DateTime.tryParse(d.id);
        final w = d.data()['weight'];
        final double? kg = w is num ? w.toDouble() : double.tryParse('$w');
        if (date != null && kg != null && kg > 0) out.add(MapEntry(date, kg));
      }
      out.sort((a, b) => a.key.compareTo(b.key));
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String _kg(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static List<String> _moodsOf(Map<String, dynamic> log) {
    if (log['moods'] is List) return List<String>.from((log['moods'] as List).map((e) => '$e'));
    if (log['mood'] != null && log['mood'].toString().isNotEmpty) return [log['mood'].toString()];
    return const [];
  }

  static List<String> _symptomsOf(Map<String, dynamic> log) => log['symptoms'] is Map ? (log['symptoms'] as Map).keys.map((e) => '$e').toList() : const [];

  static List<String> _medsOf(Map<String, dynamic> log) => log['meds'] is List ? List<String>.from((log['meds'] as List).map((e) => '$e')) : const [];

  static List<MapEntry<String, int>> _top(Iterable<List<String>> lists, [int n = 8]) {
    final Map<String, int> c = {};
    for (final l in lists) {
      for (final x in l.toSet()) {
        c[x] = (c[x] ?? 0) + 1;
      }
    }
    final list = c.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  // ---------------------------------------------------------------------------
  // Блоки
  // ---------------------------------------------------------------------------

  static pw.Widget _buildHeader(pw.Font fontBold, DateTime now, DateTime from) {
    final f = DateFormat('dd.MM.yyyy');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text("Отчёт о цикле и самочувствии", style: pw.TextStyle(font: fontBold, fontSize: 22, color: _accent)),
        pw.SizedBox(height: 4),
        pw.Text("Период: ${f.format(from)} — ${f.format(now)} · сформирован ${DateFormat('dd.MM.yyyy HH:mm').format(now)}",
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.grey300),
      ],
    );
  }

  static pw.Widget _card(pw.Font fontBold, String title, List<pw.Widget> children) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: _accentLight, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 13, color: _accent)),
        pw.SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  static pw.Widget _item(pw.Font fontBold, String title, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(right: 18, bottom: 6),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 11.5)),
      ]),
    );
  }

  static pw.Widget _buildPatient(pw.Font fontBold, Map<String, dynamic> p, List<MapEntry<DateTime, double>> weights) {
    final String name = (p['name'] ?? '').toString().trim();
    final age = p['age'];
    final height = p['height'];
    final num? w = weights.isNotEmpty ? weights.last.value : (p['weight'] is num ? p['weight'] as num : null);
    String bmi = '—';
    if (w != null && height is num && height > 0) {
      final double m = height / 100;
      bmi = (w / (m * m)).toStringAsFixed(1);
    }
    final String mode = switch ((p['appMode'] ?? 'standard').toString()) {
      'pregnancy' => 'Беременность',
      'menopause' => 'Менопауза',
      'simple' => 'Только месячные',
      _ => 'Обычный цикл',
    };
    return _card(fontBold, 'Пациентка', [
      pw.Wrap(children: [
        _item(fontBold, 'Имя', name.isEmpty ? '—' : name),
        _item(fontBold, 'Возраст', age == null ? '—' : '$age лет'),
        _item(fontBold, 'Рост', height == null ? '—' : '${height is num ? _kg(height.toDouble()) : height} см'),
        _item(fontBold, 'Вес', w == null ? '—' : '${_kg(w.toDouble())} кг'),
        _item(fontBold, 'ИМТ', bmi),
        _item(fontBold, 'Режим', mode),
      ]),
    ]);
  }

  static pw.Widget _buildCycle(pw.Font fontBold, Map<String, dynamic> p, Map<String, dynamic> stats, DateTime now) {
    final f = DateFormat('dd.MM.yyyy');
    final String mode = (p['appMode'] ?? 'standard').toString();
    if (mode == 'pregnancy') {
      final Timestamp? start = p['pregnancyStartDate'] as Timestamp?;
      if (start != null) {
        final int days = now.difference(start.toDate()).inDays;
        final due = start.toDate().add(const Duration(days: 280));
        return _card(fontBold, 'Беременность', [
          pw.Wrap(children: [
            _item(fontBold, 'Срок', '${days ~/ 7} нед. ${days % 7} дн.'),
            _item(fontBold, 'Первый день последних месячных', f.format(start.toDate())),
            _item(fontBold, 'Предполагаемая дата родов', f.format(due)),
          ]),
        ]);
      }
    }
    final Timestamp? lastTs = stats['lastPeriodStartDate'] as Timestamp?;
    final int cycle = (stats['cycleLength'] as num?)?.toInt() ?? 28;
    final int period = (stats['periodDuration'] as num?)?.toInt() ?? 5;
    final List<pw.Widget> items = [
      _item(fontBold, 'Начало последних месячных', lastTs == null ? 'нет данных' : f.format(lastTs.toDate())),
      _item(fontBold, 'Средняя длина цикла', '$cycle дн.'),
      _item(fontBold, 'Длительность месячных', '$period дн.'),
    ];
    if (lastTs != null && mode != 'menopause') {
      final DateTime last = DateTime(lastTs.toDate().year, lastTs.toDate().month, lastTs.toDate().day);
      final int dayNow = now.difference(last).inDays % cycle + 1;
      DateTime next = last.add(Duration(days: cycle));
      while (next.isBefore(DateTime(now.year, now.month, now.day))) {
        next = next.add(Duration(days: cycle));
      }
      items.add(_item(fontBold, 'День цикла сегодня', '$dayNow'));
      items.add(_item(fontBold, 'Ожидаемые месячные', f.format(next)));
      if (mode != 'simple') {
        final ov = next.subtract(const Duration(days: 14));
        items.add(_item(fontBold, 'Ожидаемая овуляция', '≈ ${f.format(ov)}'));
      }
    }
    return _card(fontBold, 'Цикл', [pw.Wrap(children: items)]);
  }

  static pw.Widget _buildFrequency(pw.Font fontBold, List<Map<String, dynamic>> logs, List<MapEntry<DateTime, double>> weights,
      bool hideIntimate, Map<String, dynamic> stats) {
    final symptoms = _top(logs.map(_symptomsOf));
    final moods = _top(logs.map(_moodsOf), 6);
    final meds = _top(logs.map(_medsOf), 8);
    final temps = logs.map((l) => l['temperature']).whereType<num>().map((e) => e.toDouble()).toList();

    String line(List<MapEntry<String, int>> list) => list.isEmpty ? 'не отмечено' : list.map((e) => '${e.key} — ${e.value} дн.').join(', ');

    final List<pw.Widget> rows = [
      _row(fontBold, 'Дней с отметками', '${logs.length} из $_days'),
      _row(fontBold, 'Симптомы', line(symptoms)),
      _row(fontBold, 'Настроение', line(moods)),
      _row(fontBold, 'Препараты', line(meds)),
    ];
    if (temps.isNotEmpty) {
      temps.sort();
      rows.add(_row(fontBold, 'Базальная температура', '${temps.length} измер., от ${temps.first.toStringAsFixed(1)} до ${temps.last.toStringAsFixed(1)} °C'));
    }
    if (weights.length >= 2) {
      final first = weights.first;
      final last = weights.last;
      final double diff = last.value - first.value;
      final vals = weights.map((e) => e.value).toList()..sort();
      final f = DateFormat('dd.MM');
      rows.add(_row(fontBold, 'Вес',
          '${_kg(first.value)} кг (${f.format(first.key)}) → ${_kg(last.value)} кг (${f.format(last.key)}), изменение ${diff >= 0 ? '+' : '−'}${_kg(double.parse(diff.abs().toStringAsFixed(1)))} кг; мин. ${_kg(vals.first)}, макс. ${_kg(vals.last)}'));
    } else if (weights.length == 1) {
      rows.add(_row(fontBold, 'Вес', '${_kg(weights.first.value)} кг (одно измерение)'));
    }
    if (!hideIntimate) {
      rows.add(_row(fontBold, 'Половые акты за год', '${stats['sexYear'] ?? 0}'));
    }
    return _card(fontBold, 'Сводка за 3 месяца', rows);
  }

  static pw.Widget _row(pw.Font fontBold, String title, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 120, child: pw.Text(title, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
        pw.Expanded(child: pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 9.5))),
      ]),
    );
  }

  static pw.Widget _buildLogsTable(pw.Font fontBold, List<Map<String, dynamic>> logs, bool hideIntimateDetails, Map<String, dynamic> stats) {
    if (logs.isEmpty) {
      return pw.Text("За последние 3 месяца отметок нет.", style: const pw.TextStyle(fontSize: 10));
    }

    final headers = ['Дата', 'День цикла', 'БТТ', 'Вес', 'Симптомы', 'Настроение', 'Препараты'];
    if (!hideIntimateDetails) headers.add('Близость');

    final Timestamp? lastStartTs = stats['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (stats['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (stats['periodDuration'] as num?)?.toInt() ?? 5;
    DateTime? lastStartDate;
    if (lastStartTs != null) {
      final dt = lastStartTs.toDate();
      lastStartDate = DateTime(dt.year, dt.month, dt.day);
    }

    final data = logs.map((log) {
      final dateStr = log['date'] as String;
      final DateTime? d = DateTime.tryParse(dateStr);
      final String displayDate = d == null ? dateStr : DateFormat('dd.MM.yyyy').format(d);
      String cycleDay = '—';
      if (lastStartDate != null && d != null) {
        final int day = (d.difference(lastStartDate).inDays % cycleLength) + 1;
        cycleDay = day <= periodDuration ? '$day (мес.)' : '$day';
      }
      final row = [
        displayDate,
        cycleDay,
        log['temperature'] != null ? "${log['temperature']} °C" : "—",
        log['weight'] is num ? "${_kg((log['weight'] as num).toDouble())} кг" : "—",
        _symptomsOf(log).isEmpty
            ? "—"
            : _symptomsOf(log).map((k) {
                final v = (log['symptoms'] as Map)[k];
                return v is num && v > 0 ? '$k (${v.toInt()}/10)' : k;
              }).join(', '),
        _moodsOf(log).isEmpty ? "—" : _moodsOf(log).join(', '),
        _medsOf(log).isEmpty ? "—" : _medsOf(log).join(', '),
      ];
      if (!hideIntimateDetails) {
        final sex = log['sex_data'] is List ? List<String>.from((log['sex_data'] as List).map((e) => '$e')).join(', ') : '';
        row.add(sex.isEmpty ? "—" : sex);
      }
      return row;
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: _accent),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellPadding: const pw.EdgeInsets.all(5),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(54),
        1: const pw.FixedColumnWidth(40),
        2: const pw.FixedColumnWidth(38),
        3: const pw.FixedColumnWidth(44),
        4: const pw.FlexColumnWidth(),
        5: const pw.FlexColumnWidth(),
        6: const pw.FlexColumnWidth(),
        if (!hideIntimateDetails) 7: const pw.FlexColumnWidth(0.8),
      },
    );
  }
}
