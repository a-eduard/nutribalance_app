import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // ==========================================
  // 🔴 ВСТАВЬ СЮДА СВОИ КЛЮЧИ YANDEX CLOUD
  // ==========================================
  static const String _folderId = "b1gr7ld3rc4skasb0uvm"; 
  static const String _apiKey = "AQVNy2e7IsDaM-B19oPnKEZnHJAIPJGQvpQKN0JX"; 
  // ==========================================

  final Uri _url = Uri.parse('https://llm.api.cloud.yandex.net/foundationModels/v1/completion');
  
  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Api-Key $_apiKey',
    'x-folder-id': _folderId,
  };

  /// МЕТОД 1: Генерация программы (Оставляем без изменений)
  Future<Map<String, dynamic>> generateWorkoutPlan({
    required String goal, 
    required String level, 
    required String gender,
    required double weight,
    required double height,
    required double bodyFat,
    required String experience,
    required int daysPerWeek,
    required String equipment,
  }) async {
    
    if (_folderId.contains("ВСТАВЬ") || _apiKey.contains("ВСТАВЬ")) {
      await Future.delayed(const Duration(seconds: 1));
      throw Exception("Ключи API не настроены в ai_service.dart");
    }

    final promptSystem = "Ты — элитный тренер по силовой подготовке. Твоя задача — генерировать JSON.";
    
    final promptUser = """
    Составь программу: ${gender == 'male' ? 'Мужчина' : 'Женщина'}, Вес: ${weight}кг, Рост: ${height}см, Жир: ${bodyFat}%, Стаж: $experience.
    Цель: $goal. Уровень: $level. Дней: $daysPerWeek. Место: $equipment.

    ВЕРНИ JSON СТРОГО ПО ФОРМАТУ:
    {
      "nutrition": {
        "calories": "число", 
        "protein": "число гр", 
        "fats": "число гр", 
        "carbs": "число гр", 
        "advice": "Совет по питанию и активности"
      },
      "schedule": [
        {
          "dayName": "День 1...", 
          "exercises": [
            {"name": "Упр", "sets": "3", "reps": "10", "comment": "Совет"}
          ]
        }
      ]
    }
    """;

    final body = jsonEncode({
      "modelUri": "gpt://$_folderId/yandexgpt/latest",
      "completionOptions": {"stream": false, "temperature": 0.4, "maxTokens": 4000},
      "messages": [
        {"role": "system", "text": promptSystem},
        {"role": "user", "text": promptUser}
      ]
    });

    try {
      final response = await http.post(_url, headers: _headers, body: body);
      
      if (response.statusCode != 200) {
        throw Exception("Ошибка Yandex API: ${response.statusCode}");
      }
      
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      String text = data['result']['alternatives'][0]['message']['text'];
      
      String cleanJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final startIndex = cleanJson.indexOf('{');
      final endIndex = cleanJson.lastIndexOf('}');
      
      if (startIndex != -1 && endIndex != -1) {
        cleanJson = cleanJson.substring(startIndex, endIndex + 1);
      } else {
        throw Exception("AI не вернул корректный JSON.");
      }

      return jsonDecode(cleanJson);

    } catch (e) {
      print("AI Error: $e");
      rethrow;
    }
  }

  /// МЕТОД 2: ЧАТ С ДИЕТОЛОГОМ (ОБНОВЛЕННЫЙ)
  Future<String> sendChatMessage(String userMessage, String userContext) async {
    if (_folderId.contains("ВСТАВЬ")) return "Ошибка: Вставь API ключи в ai_service.dart";

    // НОВЫЙ СИСТЕМНЫЙ ПРОМПТ
    final systemPrompt = """
      Ты — Элитный Спортивный Диетолог и Нутрициолог с медицинским образованием.
      Твой клиент: $userContext
      
      ТВОИ ПРИНЦИПЫ:
      1. ПЕРСОНАЛИЗАЦИЯ: Всегда учитывай вес, пол, цель и жир клиента при ответе.
      2. КОНКРЕТИКА: Не пиши "ешьте меньше". Пиши: "Вам нужно 2400 ккал: 180г белка, 80г жиров".
      3. МЕНЮ: Если просят рацион/меню — расписывай: Завтрак, Обед, Ужин, Перекус (с граммами продуктов).
      4. ПРОДУКТЫ: Советуй доступные продукты, но качественные (гречка, курица, творог, рыба, овощи).
      5. СТИЛЬ: Поддерживающий, профессиональный, но строгий к результату. Обращайся на "Вы".
      
      ТВОЯ ЦЕЛЬ: Привести клиента к его цели (Похудение/Масса) максимально здоровым путем.
    """;

    final body = jsonEncode({
      "modelUri": "gpt://$_folderId/yandexgpt/latest",
      "completionOptions": {
        "stream": false,
        "temperature": 0.4, // Низкая температура для точности фактов
        "maxTokens": 4000 
      },
      "messages": [
        {
          "role": "system", 
          "text": systemPrompt
        },
        {
          "role": "user", 
          "text": userMessage
        }
      ]
    });

    try {
      final response = await http.post(_url, headers: _headers, body: body);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String text = data['result']['alternatives'][0]['message']['text'];
        
        // Очистка от лишних символов Markdown (звездочек), если нужно сделать текст "чище"
        return text.replaceAll('*', '').trim();
      } else {
        return "Ошибка Yandex GPT: ${response.statusCode}";
      }
      
    } catch (e) {
      return "Ошибка соединения: $e";
    }
  }
}