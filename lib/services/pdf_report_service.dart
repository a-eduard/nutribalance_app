import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'database_service.dart';

class PdfReportService {
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
    final logs = await _getRecentCycleLogs(90); 
    
    // Получаем шрифты с поддержкой кириллицы
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final pdf = pw.Document();
    final now = DateTime.now();

    // 2. Формирование документа
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildHeader(fontBold, fontRegular, now),
            pw.SizedBox(height: 20),
            _buildSummary(fontBold, fontRegular, stats, hideIntimateDetails),
            pw.SizedBox(height: 20),
            pw.Text("Детализация за последние 3 месяца", style: pw.TextStyle(font: fontBold, fontSize: 16)), // СТАЛО
            pw.SizedBox(height: 10),
            // Передаем stats в таблицу для расчета ДЦ
            _buildLogsTable(fontBold, fontRegular, logs, hideIntimateDetails, stats),
          ];
        },
      ),
    );

    // 3. Вызов нативного диалога "Поделиться"
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'myeva_report_${DateFormat('yyyy_MM_dd').format(now)}.pdf',
    );
  }

  static Future<List<Map<String, dynamic>>> _getRecentCycleLogs(int days) async {
    final dbService = DatabaseService();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final String cutoffStr = "${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}";

    final uid = dbService.currentUser!.uid;
    
    final logsSnap = await FirebaseFirestore.instance.collection('users').doc(uid)
        .collection('cycle_logs')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: cutoffStr)
        .get();

    final docs = logsSnap.docs.map((d) => {'date': d.id, ...d.data()}).toList();
    docs.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));

    return docs;
  }

  static pw.Widget _buildHeader(pw.Font fontBold, pw.Font fontRegular, DateTime date) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text("Медицинский отчет (Женское здоровье)", style: pw.TextStyle(font: fontBold, fontSize: 24, color: PdfColors.pink800)),
        pw.SizedBox(height: 4),
        pw.Text("Сгенерировано: ${DateFormat('dd.MM.yyyy HH:mm').format(date)}", style: pw.TextStyle(font: fontRegular, fontSize: 12, color: PdfColors.grey700)),
        pw.Divider(color: PdfColors.grey300),
      ],
    );
  }

  static pw.Widget _buildSummary(pw.Font fontBold, pw.Font fontRegular, Map<String, dynamic> stats, bool hideIntimateDetails) {
    final lastStart = stats['lastPeriodStartDate'];
    final lastPeriodStr = lastStart != null ? DateFormat('dd.MM.yyyy').format(lastStart.toDate()) : 'Нет данных';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("Общая статистика", style: pw.TextStyle(font: fontBold, fontSize: 16)),
          pw.SizedBox(height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _summaryItem(fontBold, fontRegular, "Последние месячные", lastPeriodStr),
              _summaryItem(fontBold, fontRegular, "Длина цикла", "${stats['cycleLength'] ?? '-'} дн."),
              _summaryItem(fontBold, fontRegular, "Длительность", "${stats['periodDuration'] ?? '-'} дн."),
            ]
          ),
          if (!hideIntimateDetails) ...[
            pw.SizedBox(height: 12),
            pw.Text("Интимность (за год)", style: pw.TextStyle(font: fontBold, fontSize: 14)),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                _summaryItem(fontBold, fontRegular, "Половые акты", "${stats['sexYear'] ?? 0}"),
                pw.SizedBox(width: 40),
                _summaryItem(fontBold, fontRegular, "Оргазмы", "${stats['orgasmsYear'] ?? 0}"),
              ]
            ),
          ]
        ]
      )
    );
  }

  static pw.Widget _summaryItem(pw.Font fontBold, pw.Font fontRegular, String title, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(font: fontBold, fontSize: 14)),
      ]
    );
  }

  static pw.Widget _buildLogsTable(pw.Font fontBold, pw.Font fontRegular, List<Map<String, dynamic>> logs, bool hideIntimateDetails, Map<String, dynamic> stats) {
    if (logs.isEmpty) {
      return pw.Text("За последние 30 дней данных нет.", style: pw.TextStyle(font: fontRegular));
    }

    final headers = ['Дата', 'БТТ / Вес', 'Симптомы', 'Настроение', 'Препараты'];
    
    if (!hideIntimateDetails) {
      headers.add('Интимность');
    }

    // Подготовка данных для расчета ДЦ
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
      String displayDate = dateStr.substring(5).replaceAll('-', '.'); // MM.DD
      
      // Расчет Дня Цикла
      if (lastStartDate != null) {
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          final logDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          
          // Математика: разница в днях по модулю длины цикла
          final int diff = logDate.difference(lastStartDate).inDays;
          final int cycleDay = (diff % cycleLength) + 1;
          
          if (cycleDay <= periodDuration) {
             displayDate += "\n(М: $cycleDay ДЦ)"; // "М:" вместо эмодзи крови
          } else {
             displayDate += "\n($cycleDay ДЦ)";
          }
        }
      }

      final temp = log['temperature'] != null ? "${log['temperature']}°C" : "-";
      final weight = log['weight'] != null ? "${log['weight']}кг" : "-";
      
      String symptomsStr = "-";
      if (log['symptoms'] is Map) {
        symptomsStr = (log['symptoms'] as Map).keys.join(', ');
      }

      List<String> moods = [];
      if (log['moods'] is List) {
        moods = List<String>.from(log['moods']);
      } else if (log['mood'] != null && log['mood'].toString().isNotEmpty) {
        moods = [log['mood'].toString()];
      }
      
      final meds = log['meds'] is List ? List<String>.from(log['meds']).join(', ') : "-";
      
      final row = [
        displayDate,
        "$temp\n$weight",
        symptomsStr.isEmpty ? "-" : symptomsStr,
        moods.isEmpty ? "-" : moods.join(', '),
        meds.isEmpty ? "-" : meds,
      ];

      if (!hideIntimateDetails) {
        final sexData = log['sex_data'] is List ? List<String>.from(log['sex_data']).join(', ') : "-";
        row.add(sexData.isEmpty ? "-" : sexData);
      }
      return row;
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.pink400),
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
      cellPadding: const pw.EdgeInsets.all(6),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(48), // Чуть расширил колонку для текста "(М: 14 ДЦ)"
        1: const pw.FixedColumnWidth(50),
        2: const pw.FlexColumnWidth(),
        3: const pw.FlexColumnWidth(),
        4: const pw.FlexColumnWidth(),
        if (!hideIntimateDetails) 5: const pw.FlexColumnWidth(),
      }
    );
  }
}