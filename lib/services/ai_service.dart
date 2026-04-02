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

    int maxRetries = 2;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final result = await callable.call({
          // Промпт теперь полностью управляется в index.js! 
          // Мы отправляем только сам запрос пользователя.
          'prompt': userMessage.isEmpty && base64Image != null ? "Оцени это блюдо." : userMessage,
          'history': formattedHistory,
          'userContext': userContext,
          'imageBase64': base64Image,
        }).timeout(const Duration(seconds: 40));

        return result.data['text']?.toString() ?? "Извините, Ева не смогла обработать запрос.";
      } catch (e) {
        if (attempt == maxRetries) {
          debugPrint("AI Error: $e");
          return "Извините, Ева сейчас занята.";
        }
      }
    }
    return "Ошибка сети.";
  }
}