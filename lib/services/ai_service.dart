import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'database_service.dart';

class AIService {
  Future<String> sendChatMessage({
    required String botType,
    required String userMessage,
    required String userContext,
    required List<Map<String, String>> chatHistory,
  }) async {
    final richContext = await DatabaseService().getAIContextSummary();

    // Больше никаких проверок на тренера или ментора.
    // Все запросы идут только к Еве (Диетологу).
    return _callCloudGeminiDietitian(
      userMessage: userMessage,
      userContext: richContext,
      chatHistory: chatHistory,
      base64Image: null,
    );
  }

  Future<String> sendMultimodalMessage({
    required String userMessage,
    required String base64Image,
    required String userContext,
  }) async {
    final richContext = await DatabaseService().getAIContextSummary();
    return _callCloudGeminiDietitian(
      userMessage: userMessage,
      userContext: richContext,
      chatHistory: [],
      base64Image: base64Image,
    );
  }

  Future<String> _callCloudGeminiDietitian({
    required String userMessage,
    required String userContext,
    required List<Map<String, String>> chatHistory,
    String? base64Image,
  }) async {
    final dietitianPrompt =
        """
$userContext
СТРОГОЕ ПРАВИЛО: НЕ озвучивай пользователю его текущую статистику в каждом сообщении. Любой возвращаемый JSON ОБЯЗАТЕЛЬНО оборачивай в маркдаун блок json ... .

ВАЖНОЕ ПРАВИЛО ЛОГИРОВАНИЯ ЕДЫ И ОТВЕТОВ:
Когда пользователь просит записать еду или спрашивает про её КБЖУ, ты должен сформировать подробный ответ в поле "coach_message" внутри JSON.
В "coach_message" СНАЧАЛА распиши КБЖУ по ингредиентам (чтобы пользователь видел, как ты считаешь), затем предложи сохранить это в дневник, и ОБЯЗАТЕЛЬНО добавь фразу: "💡 Для точного расчета специфичных продуктов вы можете прислать мне фото этикетки."

ОБЯЗАТЕЛЬНО проверь статус "has_nutrition_plan" из контекста!

ЕСЛИ has_nutrition_plan == false (Плана нет):
НИКОГДА не возвращай тип "log_meal". ВМЕСТО ЭТОГО верни JSON с типом "needs_plan":

```json
{
  "type": "needs_plan",
  "coach_message": "Гречка (100г) — 330 ккал, Грудка (200г) — 220 ккал. Итого: 550 ккал.\\n\\nЯ посчитал КБЖУ, но у тебя еще нет плана питания. Давай сначала рассчитаем твою норму калорий?\\n\\n💡 Для точного расчета вы можете прислать фото этикетки.",
  "draft_meal": {
    "meal_name": "Гречка с грудкой",
    "calories": 550, "protein": 58, "fat": 6, "carbs": 60
  }
}
ЕСЛИ has_nutrition_plan == true (План есть):
Возвращай стандартный JSON для записи:

JSON
{
  "type": "log_meal",
  "coach_message": "Гречка (100г) — 330 ккал, Куриная грудка (200г) — 220 ккал.\\nИтого: 550 ккал (Б: 58г | Ж: 6г | У: 60г).\\nНажми кнопку ниже, чтобы сохранить в дневник.\\n\\n💡 Для точного расчета вы можете прислать фото этикетки продукта.",
  "meal_name": "Гречка с грудкой", "calories": 550, "protein": 58, "fat": 6, "carbs": 60
}
Если пользователь просит рассчитать норму калорий, рассчитай BMR и maintenanceCalories. Формат JSON:

JSON
{
  "type": "set_goal",
  "coach_message": "Вот твоя рассчитанная норма! Нажми кнопку ниже, чтобы сохранить цель.",
  "bmr": 1800,
  "maintenanceCalories": 2400,
  "calories": 2000,
  "protein": 150, "fat": 65, "carbs": 200
}
""";

    List<Map<String, dynamic>> formattedHistory = chatHistory.map((msg) {
      return {
        "role": msg['role'] == 'user' ? 'user' : 'model',
        "parts": [
          {"text": msg['text'] ?? ''},
        ],
      };
    }).toList();

    final callable = FirebaseFunctions.instance.httpsCallable('askDietitian');

    int maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final result = await callable
            .call({
              'prompt': userMessage.isEmpty && base64Image != null
                  ? "Оцени это блюдо."
                  : "$dietitianPrompt\n\nЗапрос: $userMessage",
              'history': formattedHistory,
              'userContext': userContext,
              'imageBase64': base64Image,
            })
            .timeout(const Duration(seconds: 40));

        return result.data['text']?.toString() ??
            "Извините, Ева не смогла обработать запрос.";
      } catch (e) {
        if (attempt == maxRetries) {
          return "Извините, Ева сейчас занята.";
        }
      }
    }
    return "Ошибка сети.";
  }
}
