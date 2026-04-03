import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

class AIService {
  Future<String> sendChatMessage({
    required String botType,
    required String userMessage,
    required String userContext,
    required List<Map<String, String>> chatHistory,
  }) async {
    final richContext = await DatabaseService().getAIContextSummary();
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
    List<Map<String, dynamic>> formattedHistory = chatHistory.map((msg) {
      return {
        "role": msg['role'] == 'user' ? 'user' : 'model',
        "parts": [{"text": msg['text'] ?? ''}],
      };
    }).toList();

    final callable = FirebaseFunctions.instance.httpsCallable('askDietitian');

    try {
      final result = await callable.call({
        // === УСИЛЕННЫЙ ПРОМПТ ДЛЯ ИИ ===
        // Заставляем Еву не дублировать названия и возвращать чистый JSON
        'prompt': userMessage.isEmpty && base64Image != null 
            ? "Оцени это блюдо. Верни СТРОГО чистый JSON. Разбей на базовые ингредиенты. НИКОГДА не дублируй названия ингредиентов." 
            : "$userMessage УБЕДИСЬ, что ты разбил блюдо на разные ингредиенты и вернул чистый JSON.",
        'history': formattedHistory,
        'userContext': userContext,
        'imagesBase64': base64Image != null ? [base64Image] : [], 
      }).timeout(const Duration(seconds: 40)); 

      return result.data['text']?.toString() ?? "Извините, Ева не смогла обработать запрос.";
    } catch (e) {
      debugPrint("AI Error: $e");
      return "Извините, сервер сейчас перегружен. Попробуй переснять фото.";
    }
  }
}