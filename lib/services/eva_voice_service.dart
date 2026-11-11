// Голосовая Ева: запись голосового сообщения → текст (transcribeVoice)
// и озвучка ответов голосом Евы (speakText, только PRO). Аудио нигде не хранится,
// озвученные ответы кэшируются в памяти на время работы приложения.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class EvaVoiceException implements Exception {
  final String message;
  final bool needsPro;
  const EvaVoiceException(this.message, {this.needsPro = false});
  @override
  String toString() => message;
}

class EvaVoiceService {
  EvaVoiceService._();
  static final EvaVoiceService instance = EvaVoiceService._();

  static const Duration maxDuration = Duration(seconds: 60);

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final Map<String, Uint8List> _cache = {};

  /// id сообщения, которое сейчас звучит (или загружается).
  final ValueNotifier<String?> playingId = ValueNotifier<String?>(null);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  // --- Запись ---

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) return false;
    await stopPlayback();
    final String path = '${Directory.systemTemp.path}/eva_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: path);
    return true;
  }

  Future<void> cancelRecording() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  /// Останавливает запись и возвращает распознанный текст.
  Future<String> stopAndTranscribe() async {
    final String? path = await _recorder.stop();
    if (path == null) throw const EvaVoiceException('Запись не получилась');
    final File f = File(path);
    try {
      final Uint8List bytes = await f.readAsBytes();
      if (bytes.length < 16000) throw const EvaVoiceException('Слишком коротко — скажи чуть подробнее');
      final res = await FirebaseFunctions.instance
          .httpsCallable('transcribeVoice', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({'audioBase64': base64Encode(bytes), 'mime': 'audio/wav'});
      final String text = (res.data is Map ? (res.data as Map)['text'] : '')?.toString().trim() ?? '';
      if (text.isEmpty) throw const EvaVoiceException('Не расслышала 🙈 Попробуй ещё раз, ближе к микрофону');
      return text;
    } on FirebaseFunctionsException catch (e) {
      throw EvaVoiceException(e.message ?? 'Не получилось распознать голос');
    } finally {
      f.delete().catchError((_) => f);
    }
  }

  // --- Озвучка ---

  /// Готовит текст к чтению и режет на части: первая — 1–2 коротких предложения,
  /// чтобы голос зазвучал через пару секунд, остальные синтезируются, пока играет первая.
  static List<String> splitForSpeech(String raw) {
    String t = raw
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'\[SHOPPING_LIST\][\s\S]*?\[/SHOPPING_LIST\]'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'[*_#>`~|]'), '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    bool cut = false;
    if (t.length > 1200) {
      t = t.substring(0, 1200);
      final int end = [t.lastIndexOf('. '), t.lastIndexOf('! '), t.lastIndexOf('? '), t.lastIndexOf('\n')].reduce((a, b) => a > b ? a : b);
      if (end > 400) t = t.substring(0, end + 1);
      cut = true;
    }
    final List<String> sentences = RegExp(r'[^.!?\n]+[.!?]*\s*|\n+').allMatches(t).map((m) => m.group(0)!).where((x) => x.trim().isNotEmpty).toList();
    final List<String> parts = [];
    String cur = '';
    for (final sen in sentences) {
      final int limit = parts.isEmpty ? 160 : 420;
      if (cur.isNotEmpty && (cur.length + sen.length) > limit) {
        parts.add(cur.trim());
        cur = '';
      }
      cur += sen;
    }
    if (cur.trim().isNotEmpty) parts.add(cur.trim());
    if (cut) parts.add('Остальное — в тексте сообщения.');
    return parts.where((p) => p.length > 1).take(6).toList();
  }

  Future<Uint8List> _synth(String messageId, int part, String text) async {
    final String key = '$messageId#$part';
    final Uint8List? cached = _cache[key];
    if (cached != null) return cached;
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('speakText', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call({'text': text, 'part': part});
      final String b64 = (res.data is Map ? (res.data as Map)['audioBase64'] : '')?.toString() ?? '';
      if (b64.isEmpty) throw const EvaVoiceException('Не получилось озвучить');
      final Uint8List bytes = base64Decode(b64);
      _cache[key] = bytes;
      return bytes;
    } on FirebaseFunctionsException catch (e) {
      if (e.message == 'PRO_REQUIRED') throw const EvaVoiceException('Голос Евы доступен в PRO', needsPro: true);
      throw EvaVoiceException(e.message ?? 'Не получилось озвучить');
    }
  }

  Future<void> _playAndWait(Uint8List bytes) async {
    final done = Completer<void>();
    _current = done;
    final sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.play(BytesSource(bytes, mimeType: 'audio/wav'));
      await done.future;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> toggleSpeak(String messageId, String text) async {
    if (playingId.value == messageId) {
      await stopPlayback();
      return;
    }
    await stopPlayback();
    final List<String> parts = splitForSpeech(text);
    if (parts.isEmpty) return;
    playingId.value = messageId;
    loading.value = true;
    // Первая часть — сразу, остальные запрашиваем после неё (параллельно между собой),
    // чтобы первая не стояла в очереди за длинными.
    final Future<Uint8List> first = _synth(messageId, 0, parts[0]);
    final List<Future<Uint8List>> rest = [];
    try {
      final Uint8List firstBytes = await first;
      for (int i = 1; i < parts.length; i++) {
        final f = _synth(messageId, i, parts[i]);
        f.ignore(); // ошибку обработаем, когда дойдём до этой части
        rest.add(f);
      }
      loading.value = false;
      if (playingId.value != messageId) return;
      await _playAndWait(firstBytes);
      for (final f in rest) {
        if (playingId.value != messageId) return;
        if (!(_cache.containsKey('$messageId#${rest.indexOf(f) + 1}'))) loading.value = true;
        final Uint8List b = await f;
        loading.value = false;
        if (playingId.value != messageId) return;
        await _playAndWait(b);
      }
    } finally {
      loading.value = false;
      if (playingId.value == messageId) playingId.value = null;
    }
  }

  Completer<void>? _current;

  Future<void> stopPlayback() async {
    final c = _current;
    if (c != null && !c.isCompleted) c.complete();
    loading.value = false;
    playingId.value = null;
    try {
      await _player.stop();
    } catch (_) {}
  }
}
