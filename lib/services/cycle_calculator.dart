import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CyclePhaseInfo {
  final String title;
  final String description;
  final String phaseType; 

  CyclePhaseInfo({required this.title, required this.description, required this.phaseType});
}

class CycleCalculator {
  
  static CyclePhaseInfo getDayInfo({
    required DateTime targetDate,
    required DateTime? lastStartDate,
    DateTime? lastEndDate, 
    required int cycleLength,
    required int periodDuration,
    required String appMode, 
    required int? manualOvulationDay,
    Timestamp? pregStartTs,
  }) {
    if (appMode == 'pregnancy') {
      if (pregStartTs != null) {
        final pregStart = pregStartTs.toDate();
        final days = targetDate.difference(pregStart).inDays;
        final weeks = days ~/ 7;
        
        if (days < 0) return CyclePhaseInfo(title: 'До беременности', description: 'Этот день был до начала отсчета беременности.', phaseType: 'none');
        if (weeks > 42) return CyclePhaseInfo(title: 'Малыш уже с вами! 🎉', description: 'Период беременности завершен.', phaseType: 'pregnancy_done');
        
        final DateTime dueDate = pregStart.add(const Duration(days: 280));
        return CyclePhaseInfo(title: '$weeks неделя 🤰', description: 'ПДР: ${DateFormat('dd.MM.yyyy').format(dueDate)}\nСледите за питанием и отдыхайте.', phaseType: 'pregnancy');
      }
      return CyclePhaseInfo(title: 'Беременность', description: 'Укажите дату начала в настройках.', phaseType: 'pregnancy');
    }

    if (appMode == 'menopause') {
      return CyclePhaseInfo(title: 'Менопауза 🌸', description: 'Трекинг симптомов и самочувствия.', phaseType: 'menopause');
    }

    if (lastStartDate != null) {
      final start = DateTime(lastStartDate.year, lastStartDate.month, lastStartDate.day);
      final current = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final int diff = current.difference(start).inDays;

      if (diff < 0) return CyclePhaseInfo(title: 'Обычный день', description: 'Данных о цикле на этот день еще нет.', phaseType: 'none');

      final int cycleIndex = diff ~/ cycleLength;
      final int normalizedDay = diff % cycleLength;
      
      bool isActualMenstruation = false;

      // ЛОГИКА ОКОНЧАНИЯ ПЕРИОДА
      if (cycleIndex == 0) {
        if (lastEndDate != null) {
          final end = DateTime(lastEndDate.year, lastEndDate.month, lastEndDate.day);
          isActualMenstruation = !current.isBefore(start) && !current.isAfter(end);
        } else {
          isActualMenstruation = normalizedDay >= 0 && normalizedDay < periodDuration;
        }
      } else {
        isActualMenstruation = normalizedDay >= 0 && normalizedDay < periodDuration;
      }
      
      final int ovDay = manualOvulationDay != null ? (manualOvulationDay - 1) : (cycleLength - 14);
      final bool isOvulation = normalizedDay == ovDay || normalizedDay == (ovDay - 1);
      final bool isFertile = normalizedDay >= (ovDay - 5) && normalizedDay <= (ovDay + 1) && !isOvulation;
      final bool isPMS = normalizedDay >= (cycleLength - 7);

      if (appMode == 'simple') {
        if (isActualMenstruation) return CyclePhaseInfo(title: 'Менструация 🩸', description: 'Дни менструации. Отдыхайте.', phaseType: 'menstruation');
        return CyclePhaseInfo(title: 'Обычный день', description: 'Простой трекинг цикла.', phaseType: 'none');
      }

      if (isActualMenstruation) return CyclePhaseInfo(title: 'Менструация 🩸', description: 'В эти дни телу нужен отдых и забота.', phaseType: 'menstruation');
      if (isOvulation) return CyclePhaseInfo(title: 'Овуляция ✨', description: 'День максимальной фертильности и пика энергии!', phaseType: 'ovulation');
      if (isFertile) return CyclePhaseInfo(title: 'Окно фертильности 🌸', description: 'Дни с высокой вероятностью зачатия.', phaseType: 'fertile');
      if (isPMS) return CyclePhaseInfo(title: 'ПМС (Лютеиновая фаза) 🌙', description: 'Возможна тяга к сладкому и перепады настроения.', phaseType: 'pms');
      
      return CyclePhaseInfo(title: 'Фолликулярная фаза 🌿', description: 'Период роста эстрогена. Отличное время для фитнеса.', phaseType: 'follicular');
    }

    return CyclePhaseInfo(title: 'Нет данных', description: 'Отметьте начало цикла на календаре.', phaseType: 'none');
  }

  static String getCheatStatus({required DateTime targetDate, required Map<String, dynamic> userData}) {
    if (userData['isPregnant'] == true || userData['appMode'] == 'pregnancy') return 'none';
    final lastStartTs = userData['lastPeriodStartDate'] as Timestamp?;
    final int cycleLength = (userData['cycleLength'] as num?)?.toInt() ?? 28;
    if (targetDate.weekday == DateTime.sunday) return 'cheat_meal';

    if (lastStartTs != null) {
      final start = DateTime(lastStartTs.toDate().year, lastStartTs.toDate().month, lastStartTs.toDate().day);
      final current = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final int diff = current.difference(start).inDays;
      if (diff >= 0 && ((diff % cycleLength) + 1) == 26) return 'cheat_day';
    }
    return 'none';
  }
}