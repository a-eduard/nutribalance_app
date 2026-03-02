import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

    if (botType == 'trainer') {
      return _callCloudGeminiTrainer(
        userMessage: userMessage, 
        userContext: richContext, 
        chatHistory: chatHistory
      );
    } else if (botType == 'coach_mentor') {
      return _callCloudCoachMentor(userMessage: userMessage, chatHistory: chatHistory); 
    } else {
      return _callCloudGeminiDietitian(userMessage: userMessage, userContext: richContext, chatHistory: chatHistory, imageUrl: null);
    }
  }

  Future<String> sendMultimodalMessage({
    required String userMessage,
    required String imageUrl,
    required String userContext,
  }) async {
    final richContext = await DatabaseService().getAIContextSummary();
    return _callCloudGeminiDietitian(
      userMessage: userMessage, 
      userContext: richContext, 
      chatHistory: [], 
      imageUrl: imageUrl
    );
  }

  Future<String> _callCloudGeminiTrainer({
    required String userMessage,
    required String userContext,
    required List<Map<String, String>> chatHistory,
  }) async {
    final systemPrompt = """
Ты — профессиональный ИИ-Тренер приложения Tonna. 
$userContext

ПРАВИЛА ОБЩЕНИЯ (СТРОГО СОБЛЮДАТЬ):
1. ОПРОС ПЕРЕД ПРОГРАММОЙ: Никогда не выдавай готовую программу тренировок в первом сообщении. Сначала задай 1-2 уточняющих вопроса (опыт, наличие травм, где будет тренироваться).
2. НЕ ПОВТОРЯЙ СТАТИСТИКУ: Контекстные данные (тоннаж, калории) используй только для своего анализа. НЕ озвучивай их пользователю в каждом ответе, если он сам об этом не спросил.
3. Веди живой диалог текстом.
4. Когда ты собрал всю информацию и составил финальную программу, ОБЯЗАТЕЛЬНО напиши в конце текста фразу: 'Сохранить эту тренировку в профиль?'.
5. Если пользователь соглашается, сгенерируй финальную программу строго в формате JSON, обернув её в блок ```json ... ```.
6. АНТИ-СПАМ ПРИВЕТСТВИЯМИ (КРИТИЧЕСКИ ВАЖНО): НИКОГДА не здоровайся с пользователем (не говори Привет, Здравствуйте, Доброе утро и т.д.), если это не самое первое сообщение в истории чата. Отвечай сразу по делу.

ФОРМАТ ОЖИДАЕМОГО JSON (использовать только для финального сохранения):
```json
{
  "type": "workout",
  "coach_message": "Отличная тренировка! Сохраняю программу...",
  "program_title": "Название",
  "days": [{
    "day_name": "День 1",
    "exercises": [
      {"name": "Жим", "sets": "3", "reps": "12", "rest": "60с", "coach_note": "Совет"}
    ]
  }]
}
""";

List<Map<String, dynamic>> formattedHistory = chatHistory.map((msg) {
return {
"role": msg['role'] == 'user' ? 'user' : 'model',
"parts": [{"text": msg['text'] ?? ''}]
};
}).toList();

final callable = FirebaseFunctions.instance.httpsCallable('generateTrainerWorkout');

int maxRetries = 2;
for (int attempt = 0; attempt <= maxRetries; attempt++) {
try {
final result = await callable.call({
'prompt': "$systemPrompt\n\nЗапрос пользователя: $userMessage",
'history': formattedHistory,
}).timeout(const Duration(seconds: 40));
return result.data['result']?.toString() ?? "Извините, произошла ошибка генерации ответа.";
} on TimeoutException catch (_) {
if (attempt == maxRetries) {
return "Время ожидания истекло. Проверьте подключение к интернету.";
}
debugPrint("Таймаут ИИ Тренера, попытка ${attempt + 1} из $maxRetries...");
} catch (e) {
if (attempt == maxRetries) {
debugPrint("Cloud Trainer Error: $e");
return 'Упс, на сервере заминка. Давай попробуем еще раз через пару минут! 💪';
}
}
}
return "Ошибка сети.";
}

Future<String> _callCloudGeminiDietitian({
required String userMessage,
required String userContext,
required List<Map<String, String>> chatHistory,
String? imageUrl,
}) async {
// БЛОК 3: Обновленный промпт с защитой логирования
final dietitianPrompt = """
$userContext
СТРОГОЕ ПРАВИЛО: НЕ озвучивай пользователю его текущую статистику (тоннаж, средние калории) в каждом сообщении. Знай её для себя.

ВАЖНОЕ ПРАВИЛО ЛОГИРОВАНИЯ ЕДЫ:
Если пользователь просит записать еду, ОБЯЗАТЕЛЬНО проверь статус "has_nutrition_plan" из контекста!
ЕСЛИ has_nutrition_plan == false:
НИКОГДА не возвращай тип "log_meal". ВМЕСТО ЭТОГО верни JSON с типом "needs_plan":

JSON
{
  "type": "needs_plan",
  "coach_message": "Я посчитал КБЖУ для твоего блюда, но у тебя еще нет плана питания. Давай сначала рассчитаем твою норму калорий, чтобы я мог вести трекинг?",
  "draft_meal": {
    "meal_name": "Название блюда",
    "calories": 250, "protein": 15, "fat": 10, "carbs": 25
  }
}
ЕСЛИ has_nutrition_plan == true, возвращай стандартный JSON для записи:

JSON
{
  "type": "log_meal",
  "coach_message": "Отлично, записал!",
  "meal_name": "Название", "calories": 250, "protein": 15, "fat": 10, "carbs": 25
}
Если пользователь просит рассчитать норму калорий, рассчитай BMR и maintenanceCalories. Формат JSON для сохранения КБЖУ:

JSON
{
  "type": "set_goal",
  "coach_message": "Твоя цель рассчитана! Сохраняю...",
  "bmr": 1800,
  "maintenanceCalories": 2400,
  "calories": 2000,
  "protein": 150, "fat": 65, "carbs": 200
}
""";

List<Map<String, dynamic>> formattedHistory = chatHistory.map((msg) {
return {
"role": msg['role'] == 'user' ? 'user' : 'model',
"parts": [{"text": msg['text'] ?? ''}]
};
}).toList();

String? base64Image;
if (imageUrl != null && imageUrl.isNotEmpty) {
try {
final response = await http.get(Uri.parse(imageUrl));
if (response.statusCode == 200) {
base64Image = base64Encode(response.bodyBytes);
}
} catch (e) {
debugPrint("Ошибка загрузки изображения: $e");
}
}

final callable = FirebaseFunctions.instance.httpsCallable('askDietitian');

int maxRetries = 2;
for (int attempt = 0; attempt <= maxRetries; attempt++) {
try {
final result = await callable.call({
'prompt': userMessage.isEmpty && base64Image != null
? "Оцени это блюдо."
: "$dietitianPrompt\n\nЗапрос: $userMessage",
'history': formattedHistory,
'userContext': userContext,
'imageBase64': base64Image,
}).timeout(const Duration(seconds: 40));
return result.data['text']?.toString() ?? "Извините, Нутрициолог не смог обработать запрос.";
} on TimeoutException catch (_) {
if (attempt == maxRetries) {
return "Время ожидания истекло. Проверьте интернет.";
}
} catch (e) {
if (attempt == maxRetries) {
debugPrint("Cloud Dietitian Error: $e");
return "Извините, Нутрициолог сейчас занят или возникла ошибка сети.";
}
}
}
return "Ошибка сети.";
}

Future<String> _callCloudCoachMentor({
required String userMessage,
required List<Map<String, String>> chatHistory,
}) async {
List<Map<String, dynamic>> formattedHistory = chatHistory.map((msg) {
return {"role": msg['role'] == 'user' ? 'user' : 'model', "parts": [{"text": msg['text'] ?? ''}]};
}).toList();

final callable = FirebaseFunctions.instance.httpsCallable('askCoachMentor');
try {
final result = await callable.call({
'prompt': userMessage,
'history': formattedHistory,
}).timeout(const Duration(seconds: 40));
return result.data['text']?.toString() ?? "Ошибка генерации ответа.";
} catch (e) {
debugPrint("Cloud Mentor Error: $e");
return "Извините, Ментор сейчас занят или возникла ошибка сети.";
}
}
}