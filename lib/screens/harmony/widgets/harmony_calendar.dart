import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/cycle_calculator.dart';
import '../../../theme/eva_colors.dart';

class HarmonyCalendar extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Function(DateTime selectedDay, Map<String, dynamic> userData)
  onDaySelected;

  const HarmonyCalendar({
    super.key,
    required this.userData,
    required this.onDaySelected,
  });

  @override
  State<HarmonyCalendar> createState() => _HarmonyCalendarState();
}

class _HarmonyCalendarState extends State<HarmonyCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  Widget _buildCalendarDay(
    BuildContext context,
    DateTime day, {
    bool isToday = false,
    bool isOutside = false,
    bool isSelected = false,
  }) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark; // Проверка темной темы

    final String appMode = widget.userData['appMode'] ?? 'standard';
    final int cycleLength = (widget.userData['cycleLength'] as num?)?.toInt() ?? 28;
    final int periodDuration = (widget.userData['periodDuration'] as num?)?.toInt() ?? 5;
    final Timestamp? lastStartTs = widget.userData['lastPeriodStartDate'] as Timestamp?;
    final Timestamp? lastEndTs = widget.userData['lastPeriodEndDate'] as Timestamp?;
    final Timestamp? pregStartTs = widget.userData['pregnancyStartDate'] as Timestamp?;
    final int? manualOvulationDay = (widget.userData['manualOvulationDay'] as num?)?.toInt();

    Color bgColor = Colors.transparent;
    Color txtColor = isOutside ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4) : theme.colorScheme.onSurface;
    BoxBorder? border;

    final dayInfo = CycleCalculator.getDayInfo(
      targetDate: day,
      lastStartDate: lastStartTs?.toDate(),
      lastEndDate: lastEndTs?.toDate(),
      cycleLength: cycleLength,
      periodDuration: periodDuration,
      appMode: appMode,
      manualOvulationDay: manualOvulationDay,
      pregStartTs: pregStartTs,
    );

    // Адаптивная палитра цветов
    if (dayInfo.phaseType == 'pregnancy') {
      // Каждый этап развития малыша — свой цвет (легенда под календарём).
      final Color stageColor = EvaColors.pregnancyStage(dayInfo.pregnancyStage);
      bgColor = stageColor.withValues(alpha: isOutside ? (isDark ? 0.18 : 0.14) : (isDark ? 0.45 : 0.34));
      txtColor = isOutside ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : theme.colorScheme.onSurface;
      if (dayInfo.isDueDate) {
        border = Border.all(color: const Color(0xFFC6A27C), width: 2.5);
      }
    } else if (dayInfo.phaseType == 'pregnancy_done') {
      bgColor = isDark ? const Color(0xFF5E35B1) : Colors.deepPurpleAccent;
      txtColor = Colors.white;
    } else {
      switch (dayInfo.phaseType) {
        case 'menstruation':
          bgColor = theme.colorScheme.primary.withValues(alpha: isDark ? 0.8 : 1.0);
          txtColor = theme.colorScheme.onPrimary;
          break;
        case 'ovulation':
          bgColor = isDark ? const Color(0xFFE65100).withValues(alpha: 0.3) : const Color(0xFFFFE0B2);
          txtColor = isDark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
          border = Border.all(color: txtColor.withValues(alpha: 0.6), width: 1.5);
          break;
        case 'fertile':
          bgColor = isDark ? const Color(0xFF00695C).withValues(alpha: 0.3) : const Color(0xFFE0F2F1);
          txtColor = isDark ? const Color(0xFF80CBC4) : const Color(0xFF00695C);
          break;
        case 'pms':
          bgColor = isDark ? const Color(0xFF6A1B9A).withValues(alpha: 0.3) : const Color(0xFFF3E5F5);
          txtColor = isDark ? const Color(0xFFCE93D8) : const Color(0xFF6A1B9A);
          break;
      }
    }

    if (isSelected) {
      border = Border.all(color: theme.colorScheme.onSurface, width: 2);
    } else if (isToday && dayInfo.phaseType != 'pregnancy' && dayInfo.phaseType != 'pregnancy_done') {
      border = Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 2);
    } else if (isToday && dayInfo.phaseType == 'pregnancy') {
      border = Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.75), width: 2);
    }

    final String cheatStatus = CycleCalculator.getCheatStatus(targetDate: day, userData: widget.userData);
    Widget contentWidget;

    if (cheatStatus == 'cheat_day' && !isOutside) {
      contentWidget = const Text('🎂', style: TextStyle(fontSize: 16));
    } else if (cheatStatus == 'cheat_meal' && !isOutside) {
      contentWidget = const Text('🧁', style: TextStyle(fontSize: 16));
    } else {
      contentWidget = Text(day.day.toString(), style: TextStyle(color: txtColor, fontWeight: FontWeight.bold, fontSize: 15));
    }

    return Container(
      margin: const EdgeInsets.all(6.0),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle, border: border),
      child: contentWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return TableCalendar(
      locale: 'ru_RU',
      firstDay: DateTime.utc(2020, 10, 16),
      lastDay: DateTime.utc(2030, 3, 14),
      focusedDay: _focusedDay,
      availableGestures: AvailableGestures.horizontalSwipe,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        widget.onDaySelected(selectedDay, widget.userData);
      },
      startingDayOfWeek: StartingDayOfWeek.monday,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold),
        weekendStyle: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
      ),
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (c, d, f) => _buildCalendarDay(c, d),
        todayBuilder: (c, d, f) => _buildCalendarDay(c, d, isToday: true),
        outsideBuilder: (c, d, f) => _buildCalendarDay(c, d, isOutside: true),
        selectedBuilder: (c, d, f) => _buildCalendarDay(c, d, isSelected: true),
      ),
    );
  }
}

/// Легенда этапов беременности под календарём.
class PregnancyStagesLegend extends StatelessWidget {
  final int? currentStage;

  const PregnancyStagesLegend({super.key, this.currentStage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    Widget row({required Widget marker, required String range, required String title, bool current = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 22, height: 22, child: Center(child: marker)),
            const SizedBox(width: 12),
            SizedBox(
              width: 74,
              child: Text(range, style: theme.textTheme.bodySmall?.copyWith(fontWeight: current ? FontWeight.w700 : FontWeight.w500)),
            ),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: current ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
            if (current)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('сейчас', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      );
    }

    int? lastTrimester;
    final List<Widget> rows = [];
    for (final stage in CycleCalculator.pregnancyStages) {
      if (stage.trimester != lastTrimester) {
        lastTrimester = stage.trimester;
        rows.add(Padding(
          padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 10, bottom: 2),
          child: Text(
            '${stage.trimester} ТРИМЕСТР',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.6, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700),
          ),
        ));
      }
      final Color color = EvaColors.pregnancyStages[stage.index];
      rows.add(row(
        marker: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: color.withValues(alpha: isDark ? 0.55 : 0.45), shape: BoxShape.circle, border: Border.all(color: color, width: 1.5)),
        ),
        range: stage.range,
        title: stage.title,
        current: stage.index == currentStage,
      ));
    }
    rows.add(const SizedBox(height: 6));
    rows.add(row(
      marker: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC6A27C), width: 2.5)),
      ),
      range: 'ПДР',
      title: 'Предполагаемая дата родов',
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}
