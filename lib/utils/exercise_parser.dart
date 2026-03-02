class ParsedExercise {
  final String name;
  final String notes;

  ParsedExercise({required this.name, required this.notes});
}

class ExerciseParser {
  static ParsedExercise parse(dynamic rawEx, [Map<String, dynamic>? targets]) {
    String exName = "Упражнение";
    String comment = "";
    final safeTargets = targets ?? {};

    if (rawEx is Map) {
      exName = rawEx['name']?.toString() ?? "Упражнение";
      comment = rawEx['notes']?.toString() ?? rawEx['coach_note']?.toString() ?? "";
    } else {
      exName = rawEx.toString();
      if (safeTargets.containsKey(exName)) {
        final parts = safeTargets[exName].toString().split('|');
        comment = parts.length > 1 ? parts[1].trim() : parts[0].trim();
      }
    }

    // Убираем мусорные нули
    if (comment == "0x0" || comment == "0|0" || comment == "0" || comment == "0х0") {
      comment = "";
    }

    // Чистим имя от JSON-артефактов
    String cleanExName = exName.replaceAll(RegExp(r'[{}""\[\],]|(name\s*:)|(notes\s*:)'), '').trim();

    return ParsedExercise(name: cleanExName, notes: comment);
  }
}