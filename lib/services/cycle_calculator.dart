import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CyclePhaseInfo {
  final String title;
  final String description;
  final String phaseType;

  /// Этап беременности (индекс в [CycleCalculator.pregnancyStages]) — только в режиме беременности.
  final int? pregnancyStage;

  /// Акушерский срок: полные недели и дни.
  final int? pregnancyWeeks;
  final int? pregnancyDays;

  /// День предполагаемой даты родов (ПДР).
  final bool isDueDate;

  CyclePhaseInfo({
    required this.title,
    required this.description,
    required this.phaseType,
    this.pregnancyStage,
    this.pregnancyWeeks,
    this.pregnancyDays,
    this.isDueDate = false,
  });
}

/// Этап развития малыша. Недели — полные акушерские недели (от первого дня
/// последних месячных), как в обменной карте: «12 нед. 3 дн.» → 12.
class PregnancyStage {
  final int index;
  final int fromWeek;
  final int toWeek;
  final String title;
  final String description;

  const PregnancyStage(this.index, this.fromWeek, this.toWeek, this.title, this.description);

  String get range => '$fromWeek–$toWeek нед.';

  int get trimester => fromWeek <= 13 ? 1 : (fromWeek <= 27 ? 2 : 3);
}

class CycleCalculator {
  static const List<PregnancyStage> pregnancyStages = [
    PregnancyStage(0, 0, 3, 'Зачатие и имплантация',
        'Срок считают от первого дня последних месячных: в эти недели происходят овуляция, зачатие и прикрепление плодного яйца. Особенно важна фолиевая кислота — по назначению врача.'),
    PregnancyStage(1, 4, 9, 'Эмбрион: закладка органов',
        'Формируются все основные органы, начинает биться сердце. Время встать на учёт, больше отдыхать и питаться бережно.'),
    PregnancyStage(2, 10, 13, 'Малыш становится плодом',
        'Завершается I триместр: органы сформированы и начинают работать. На 11–13 неделе проводят первый скрининг.'),
    PregnancyStage(3, 14, 19, 'Активный рост',
        'II триместр: малыш быстро растёт, формируются черты лица. Самочувствие часто улучшается. Второй скрининг — на 18–21 неделе.'),
    PregnancyStage(4, 20, 27, 'Шевеления и чувства',
        'Ты чувствуешь шевеления, малыш слышит звуки и реагирует на твой голос. Растёт жировая прослойка.'),
    PregnancyStage(5, 28, 36, 'Набор веса и созревание',
        'III триместр: малыш набирает вес, созревают лёгкие. Больше отдыха, следи за отёками и давлением.'),
    PregnancyStage(6, 37, 42, 'Малыш готов к рождению',
        'Беременность доношенная — роды могут начаться в любой день. Держи сумку в роддом наготове 👜'),
  ];

  static PregnancyStage pregnancyStageForWeek(int weeks) {
    for (final stage in pregnancyStages) {
      if (weeks <= stage.toWeek) return stage;
    }
    return pregnancyStages.last;
  }

  static String _plural(int n, String one, String few, String many) {
    final int mod10 = n % 10, mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
    return many;
  }

  /// «12 недель 3 дня»
  static String pregnancyTermLabel(int weeks, int days) {
    final String w = '$weeks ${_plural(weeks, 'неделя', 'недели', 'недель')}';
    if (days == 0) return w;
    return '$w $days ${_plural(days, 'день', 'дня', 'дней')}';
  }

  /// Первые дни после ожидаемой даты не считаем задержкой: цикл в норме немного сдвигается.
  static const int delayGraceDays = 2;

  /// С какого дня задержки подсказываем сделать тест или сходить к гинекологу.
  static const int delayHintDays = 7;

  /// Сколько дней прошло после ожидаемого начала месячных, если новое начало не отмечено.
  /// null — задержки нет (или она ещё в пределах [delayGraceDays]).
  static int? activeDelayDays({required DateTime? lastStartDate, required int cycleLength, DateTime? now}) {
    if (lastStartDate == null || cycleLength <= 0) return null;
    final DateTime n = now ?? DateTime.now();
    final DateTime today = DateTime(n.year, n.month, n.day);
    final DateTime start = DateTime(lastStartDate.year, lastStartDate.month, lastStartDate.day);
    final int late = today.difference(start).inDays - cycleLength;
    return late > delayGraceDays ? late : null;
  }

  static CyclePhaseInfo _delayInfo(int daysLate) {
    if (daysLate > 60) {
      return CyclePhaseInfo(
        title: 'Давно нет отметок',
        description: 'Отметь начало последних месячных — и прогноз снова станет точным.',
        phaseType: 'delay',
      );
    }
    final String days = '$daysLate ${_plural(daysLate, 'день', 'дня', 'дней')}';
    return CyclePhaseInfo(
      title: 'Задержка $days',
      description: daysLate >= delayHintDays
          ? 'Если задержка неделю и больше, сделай тест на беременность или покажись гинекологу.'
          : 'Цикл может сдвигаться из-за стресса, сна или болезни. Когда месячные начнутся — отметь.',
      phaseType: 'delay',
    );
  }

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
        final DateTime rawStart = pregStartTs.toDate();
        // Сравниваем только календарные даты: календарь передаёт дни в UTC,
        // а дата начала хранится в местном времени — иначе срок «прыгал» на день.
        final DateTime pregStart = DateTime.utc(rawStart.year, rawStart.month, rawStart.day);
        final DateTime current = DateTime.utc(targetDate.year, targetDate.month, targetDate.day);
        final int totalDays = current.difference(pregStart).inDays;
        final int weeks = totalDays ~/ 7;
        final int days = totalDays % 7;

        if (totalDays < 0) return CyclePhaseInfo(title: 'До беременности', description: 'Этот день был до начала отсчёта беременности.', phaseType: 'none');
        if (weeks > 42) return CyclePhaseInfo(title: 'Малыш уже с вами! 🎉', description: 'Период беременности завершён.', phaseType: 'pregnancy_done');

        final DateTime dueDate = pregStart.add(const Duration(days: 280));
        final PregnancyStage stage = pregnancyStageForWeek(weeks);
        return CyclePhaseInfo(
          title: '${pregnancyTermLabel(weeks, days)} 🤰',
          description: '${stage.title} · ${stage.trimester} триместр\n${stage.description}\nПДР: ${DateFormat('dd.MM.yyyy').format(dueDate)}',
          phaseType: 'pregnancy',
          pregnancyStage: stage.index,
          pregnancyWeeks: weeks,
          pregnancyDays: days,
          isDueDate: totalDays == 280,
        );
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

      // Задержка: новое начало не отмечено, а ожидаемая дата прошла больше чем на delayGraceDays.
      // Раньше календарь молча начинал следующий цикл и мог показать «Менструацию», которой нет.
      final int? lateNow = activeDelayDays(lastStartDate: lastStartDate, cycleLength: cycleLength);
      if (lateNow != null && diff >= cycleLength) {
        final DateTime n = DateTime.now();
        final DateTime today = DateTime(n.year, n.month, n.day);
        if (current.isAfter(today)) {
          return CyclePhaseInfo(title: 'Прогноз уточнится', description: 'Прогноз обновится, когда ты отметишь начало месячных.', phaseType: 'none');
        }
        final int dayLate = diff - cycleLength;
        if (dayLate > delayGraceDays) return _delayInfo(dayLate);
        return CyclePhaseInfo(title: 'Ожидались месячные', description: 'По прогнозу в этот день мог начаться новый цикл.', phaseType: 'none');
      }

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