import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_service.dart';

/// Лимит бесплатных запросов исчерпан — нужно показать пейвол.
class EvaQuotaException implements Exception {
  const EvaQuotaException();
  @override
  String toString() => 'QUOTA_EXCEEDED';
}

/// Ева временно недоступна (сеть, перегрузка модели и т.п.).
class EvaUnavailableException implements Exception {
  final String message;
  const EvaUnavailableException([this.message = 'Ева временно недоступна']);
  @override
  String toString() => message;
}

class EvaReply {
  final String text;
  final bool savedByServer;
  const EvaReply(this.text, {this.savedByServer = false});
}

class AIService {
  static const String _prefsKey = 'eva_server_version';
  static int _serverVersion = -1; // -1 = ещё не знаем

  /// Сервер новой версии умеет: лимиты на сервере, чтение фото из Storage,
  /// сохранение ответа в чат. До первого ответа работаем в режиме совместимости.
  static Future<int> serverVersion() async {
    if (_serverVersion >= 0) return _serverVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverVersion = prefs.getInt(_prefsKey) ?? 0;
    } catch (_) {
      _serverVersion = 0;
    }
    return _serverVersion;
  }

  static Future<void> _rememberServerVersion(dynamic data) async {
    final int v = (data is Map && data['serverVersion'] is num) ? (data['serverVersion'] as num).toInt() : 0;
    if (v > _serverVersion) {
      _serverVersion = v;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsKey, v);
      } catch (_) {}
    }
  }

  /// Универсальный вызов Евы.
  Future<EvaReply> ask({
    required String prompt,
    String botType = 'dietitian',
    List<Map<String, String>> history = const [],
    String? userContext,
    List<String> imagesBase64 = const [],
    List<String> imagePaths = const [],
    String? pdfBase64,
    String? pdfPath,
    String quota = 'message',
    bool saveReply = true,
    String? mode,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final int version = await serverVersion();
    final bool serverV2 = version >= 2;

    // Совместимость со старой версией сервера: лимит списываем на клиенте.
    if (!serverV2) {
      final bool hasQuota = quota == 'scan'
          ? await DatabaseService().checkAndDecrementFreeScan().catchError((_) => true)
          : await DatabaseService().checkAndDecrementFreeMessage().catchError((_) => true);
      if (!hasQuota) throw const EvaQuotaException();
    }

    final String context = userContext ?? await DatabaseService().getAIContextSummary();

    final Map<String, dynamic> payload = {
      'prompt': prompt,
      'history': history,
      'userContext': context,
      'botType': botType,
      'saveReply': saveReply,
      // Лимит списывает сервер, только если мы точно знаем, что он новой версии
      // (иначе — на клиенте выше), чтобы не списать попытку дважды.
      if (serverV2) 'quota': quota,
      'clientVersion': 2,
      if (mode != null) 'mode': mode,
      if (serverV2 && imagePaths.isNotEmpty) 'imagePaths': imagePaths else 'imagesBase64': imagesBase64,
      if (serverV2 && pdfPath != null) 'pdfPath': pdfPath else if (pdfBase64 != null) 'pdfBase64': pdfBase64,
    };

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('askDietitian', options: HttpsCallableOptions(timeout: timeout))
          .call(payload);
      final dynamic data = result.data;
      unawaited(_rememberServerVersion(data));
      final String text = (data is Map ? data['text'] : null)?.toString() ?? '';
      final bool saved = data is Map && data['saved'] == true;
      if (text.trim().isEmpty) throw const EvaUnavailableException();
      return EvaReply(text, savedByServer: saved);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('askDietitian: ${e.code} ${e.message}');
      if (e.code == 'resource-exhausted') throw const EvaQuotaException();
      throw EvaUnavailableException(e.code == 'unauthenticated' ? 'Войдите в аккаунт заново' : 'Ева временно недоступна. Попробуй ещё раз.');
    } on TimeoutException {
      throw const EvaUnavailableException('Ответ занимает слишком много времени. Проверь соединение.');
    }
  }

  // --- Старый API (используется в нескольких местах) ---

  Future<String> sendChatMessage({
    required String botType,
    required String userMessage,
    required String userContext,
    required List<Map<String, String>> chatHistory,
  }) async {
    try {
      final reply = await ask(prompt: userMessage, botType: botType, history: chatHistory, saveReply: false);
      return reply.text;
    } catch (e) {
      debugPrint("AI Error: $e");
      return "Извините, сервер сейчас перегружен. Попробуй ещё раз.";
    }
  }

  /// Распознавание еды по фото (быстрый сканер). Бросает [EvaQuotaException],
  /// если бесплатные сканы закончились.
  Future<String> sendMultimodalMessage({
    required String userMessage,
    required String base64Image,
    required String userContext,
  }) async {
    final reply = await ask(
      prompt: userMessage.isEmpty
          ? "Оцени это блюдо. Верни СТРОГО чистый JSON (action_type: log_food). Разбей на базовые ингредиенты, не дублируй названия."
          : "$userMessage Убедись, что ты разбила блюдо на разные ингредиенты и вернула чистый JSON.",
      imagesBase64: [base64Image],
      quota: 'scan',
      saveReply: false,
      timeout: const Duration(seconds: 60),
    );
    return reply.text;
  }
}
