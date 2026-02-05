import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // ==========================================
  // 🔴 ВСТАВЬ СЮДА СВОИ КЛЮЧИ YANDEX CLOUD
  // ==========================================
  static const String _folderId = "b1gr7ld3rc4skasb0uvm";
  static const String _apiKey = "AQVNy2e7IsDaM-B19oPnKEZnHJAIPJGQvpQKN0JX";
  // ==========================================

  final Uri _url = Uri.parse(
    'https://llm.api.cloud.yandex.net/foundationModels/v1/completion',
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Api-Key $_apiKey',
    'x-folder-id': _folderId,
  };

  /// МЕТОД 1: Генерация программы (JSON)
  Future<Map<String, dynamic>> generateWorkoutPlan({
    required String goal,
    required String level,
    required String gender,
    required double weight,
    required double height,
    required double bodyFat,
    required String experience,
    required int daysPerWeek,
  }) async {
    if (_folderId.contains("ВСТАВЬ") || _apiKey.contains("ВСТАВЬ")) {
      await Future.delayed(const Duration(seconds: 1));
      throw Exception("Ключи API не настроены в ai_service.dart");
    }

    final promptSystem =
        "Ты — элитный фитнес-тренер. Твоя задача — генерировать JSON. Не пиши вводный текст.";
    final promptUser =
        """
    Составь программу (${gender == 'male' ? 'Мужчина' : 'Женщина'}, ${weight}кг, ${height}см, Жир ${bodyFat}%, Стаж $experience).
    Цель: $goal. Уровень: $level. Дней: $daysPerWeek.
    ВЕРНИ JSON:
    {
      "nutrition": {"calories": "...", "protein": "...", "fats": "...", "carbs": "...", "advice": "..."},
      "schedule": [{"dayName": "...", "exercises": [{"name": "...", "sets": "...", "reps": "...", "comment": "..."}]}]
    }
    """;

    final body = jsonEncode({
      "modelUri": "gpt://$_folderId/yandexgpt/latest",
      "completionOptions": {
        "stream": false,
        "temperature": 0.3,
        "maxTokens": 4000,
      },
      "messages": [
        {"role": "system", "text": promptSystem},
        {"role": "user", "text": promptUser},
      ],
    });

    final response = await http.post(_url, headers: _headers, body: body);

    if (response.statusCode != 200)
      throw Exception("Error: ${response.statusCode}");

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    String text = data['result']['alternatives'][0]['message']['text'];

    String cleanJson = text
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final startIndex = cleanJson.indexOf('{');
    final endIndex = cleanJson.lastIndexOf('}');
    if (startIndex != -1 && endIndex != -1)
      cleanJson = cleanJson.substring(startIndex, endIndex + 1);

    return jsonDecode(cleanJson);
  }

  /// МЕТОД 2: Чат с тренером (Текст)
  // ... внутри класса AIService

  // Обновленный метод чата с контекстом
  // ... внутри класса AIService

  // Обновленный метод чата с контекстом
  Future<String> sendChatMessage(String userMessage, String contextInfo) async {
    if (_folderId.contains("ВСТАВЬ"))
      return "Ошибка: Вставь API ключи в ai_service.dart";

    final body = jsonEncode({
      "modelUri": "gpt://$_folderId/yandexgpt/latest",
      "completionOptions": {
        "stream": false,
        "temperature": 0.5,
        "maxTokens": 1000,
      },
      "messages": [
        {
          "role": "system",
          // ЖЕСТКИЙ СИСТЕМНЫЙ ПРОМПТ
          "text":
              """
          Ты — профессиональный диетолог и фитнес-тренер. 
          Твоя задача — давать КОНКРЕТНЫЕ цифры и рекомендации.
          
          Контекст пользователя: $contextInfo
          
          ИНСТРУКЦИИ:
          1. Если пользователь спрашивает про калории, похудение или набор — ТЫ ОБЯЗАН посчитать их по формуле Миффлина-Сан Жеора, используя данные из контекста (вес, рост, возраст). Сделай расчет сам и напиши цифру.
          2. НЕ пиши 'обратитесь к врачу'. НЕ пиши 'зависит от индивидуальных факторов'.
          3. Отвечай кратко, без воды.
          4. Обращайся на 'ты'.
          """,
        },
        {"role": "user", "text": userMessage},
      ],
    });

    try {
      final response = await http.post(_url, headers: _headers, body: body);
      if (response.statusCode != 200)
        return "Ошибка сети: ${response.statusCode}";

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['result']['alternatives'][0]['message']['text'];
    } catch (e) {
      return "Ошибка: $e";
    }
  }
}
