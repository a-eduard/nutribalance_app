import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // ==========================================
  // 🔴 КЛЮЧИ (Оставь свои рабочие ключи)
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

  /// ==========================================================
  /// 🏋️‍♂️ РОЛЬ 1: ЭЛИТНЫЙ ТРЕНЕР (ЖЕСТКИЙ РЕЖИМ)
  /// ==========================================================
  Future<Map<String, dynamic>> generateWorkout({
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
    
    final bool isHome = equipment.toLowerCase().contains('дома') || equipment.toLowerCase().contains('home');
    final String equipText = isHome 
        ? "ОБОРУДОВАНИЕ: Только пол, гантели и турник. ЗАПРЕЩЕНО: Тренажеры, штанги." 
        : "ОБОРУДОВАНИЕ: Полный тренажерный зал.";

    final promptSystem = """
    Ты — Тренер Олимпийской сборной по бодибилдингу и пауэрлифтингу.
    Твой стиль: Жесткий, конкретный, без воды. Ты ненавидишь лишние слова.
    Твоя задача: Составить убийственно эффективную программу тренировок.
    
    ФОРМАТ ОТВЕТА: ТОЛЬКО JSON. Никакого вступления "Конечно, вот программа". Сразу JSON.
    """;
    
    final promptUser = """
    КЛИЕНТ:
    Пол: ${gender == 'male' ? 'Мужчина' : 'Женщина'}, Вес: $weight кг, Рост: $height см, Жир: $bodyFat%, Стаж: $experience.
    Цель: $goal. Уровень: $level. Дней: $daysPerWeek.
    $equipText

    ЗАДАЧА:
    Составь программу на $daysPerWeek дн.
    Для каждого упражнения укажи рабочие подходы и повторения. Дай короткий совет по технике.

    ВЕРНИ JSON (БЕЗ MARKDOWN ```json):
    {
      "schedule": [
        {
          "dayName": "День 1: Грудные (Тяжело)", 
          "exercises": [
            {"name": "Жим лежа", "sets": "4", "reps": "6-8", "comment": "Лопатки сведены, мост."}
          ]
        }
      ]
    }
    """;

    return _makeRequest(promptSystem, promptUser);
  }

  /// ==========================================================
  /// 🥦 РОЛЬ 2: ПРОФЕССИОНАЛЬНЫЙ ДИЕТОЛОГ (МЕДИЦИНСКИЙ ПОДХОД)
  /// ==========================================================
  Future<Map<String, dynamic>> chatWithDietologist({
    required String userMessage, 
    required String userContext // Полное досье клиента
  }) async {

    final promptSystem = """
    Ты — Ведущий Спортивный Диетолог (PhD in Sports Nutrition).
    У тебя на руках УЖЕ ЕСТЬ полное досье клиента (Вес, Рост, Цель, Жир).
    
    СТРОГИЕ ПРАВИЛА:
    1. ЗАПРЕЩЕНО писать: "Мне нужно больше деталей", "Обратитесь к врачу", "Все индивидуально".
    2. Ты ОБЯЗАН дать конкретное решение прямо сейчас, основываясь на данных из контекста.
    3. Если просят "рацион" или "диету" — ты ОБЯЗАН расписать меню: Завтрак, Обед, Ужин с ГРАММОВКАМИ.
    4. Твой тон: Профессиональный, уверенный, директивный. Ты врач, ты знаешь лучше.

    ФОРМАТ ОТВЕТА (JSON):
    Если вопрос про план питания/рацион/меню -> "is_plan": true.
    Если обычный вопрос -> "is_plan": false.

    СТРУКТУРА JSON (БЕЗ MARKDOWN):
    {
      "is_plan": true/false,
      "text": "Твой развернутый ответ здесь. Используй переносы строк \\n для красоты.",
      "nutrition": { 
        "calories": 2500, 
        "protein": 180, 
        "fats": 80, 
        "carbs": 250,
        "advice": "Короткий совет (10 слов)"
      }
    }
    """;

    final promptUser = """
    КОНТЕКСТ КЛИЕНТА:
    $userContext

    ВОПРОС КЛИЕНТА:
    "$userMessage"
    
    Действуй.
    """;

    return _makeRequest(promptSystem, promptUser);
  }

  Future<Map<String, dynamic>> _makeRequest(String system, String user) async {
    final body = jsonEncode({
      "modelUri": "gpt://$_folderId/yandexgpt/latest",
      "completionOptions": {
        "stream": false, 
        "temperature": 0.3, // Низкая температура = меньше фантазий, больше фактов
        "maxTokens": 8000 // Увеличил лимит для длинных диет
      },
      "messages": [
        {"role": "system", "text": system},
        {"role": "user", "text": user}
      ]
    });

    try {
      final response = await http.post(_url, headers: _headers, body: body);
      
      if (response.statusCode != 200) {
        throw Exception("Yandex API Error: ${response.statusCode}");
      }
      
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      String text = data['result']['alternatives'][0]['message']['text'];
      
      // Очистка от Markdown и лишнего мусора
      String cleanJson = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final startIndex = cleanJson.indexOf('{');
      final endIndex = cleanJson.lastIndexOf('}');
      
      if (startIndex != -1 && endIndex != -1) {
        cleanJson = cleanJson.substring(startIndex, endIndex + 1);
        return jsonDecode(cleanJson);
      } else {
        // Если ИИ все же вернул текст без JSON (бывает при сбоях)
        return {
          "is_plan": false, 
          "text": text, // Возвращаем сырой текст
          "schedule": []
        };
      }

    } catch (e) {
      print("AI Error: $e");
      return {"text": "Ошибка мозга ИИ: $e. Попробуй еще раз.", "is_plan": false};
    }
  }
}