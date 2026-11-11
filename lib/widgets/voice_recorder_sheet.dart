// Шторка записи голосового сообщения Еве: таймер, «Отмена», «Отправить».
// Возвращает распознанный текст или null.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/analytics_service.dart';
import '../services/eva_voice_service.dart';
import '../theme/eva_colors.dart';
import 'eva_ui.dart';

class VoiceRecorderSheet extends StatefulWidget {
  const VoiceRecorderSheet({super.key});

  static Future<String?> show(BuildContext context) => showModalBottomSheet<String>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => const VoiceRecorderSheet(),
      );

  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> with SingleTickerProviderStateMixin {
  final EvaVoiceService _voice = EvaVoiceService.instance;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final bool ok = await _voice.startRecording();
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Нужен доступ к микрофону. Разреши его в настройках телефона.');
      return;
    }
    HapticFeedback.mediumImpact();
    Analytics.event('voice_record_start');
    setState(() => _recording = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= EvaVoiceService.maxDuration.inSeconds) _send();
    });
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _voice.cancelRecording();
    Analytics.event('voice_record_cancel');
    if (mounted) Navigator.pop(context);
  }

  Future<void> _send() async {
    if (_sending) return;
    _timer?.cancel();
    setState(() => _sending = true);
    try {
      final String text = await _voice.stopAndTranscribe();
      Analytics.event('voice_message_sent', {'seconds': _seconds});
      if (mounted) Navigator.pop(context, text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _recording = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String time = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_sending ? 'Ева слушает…' : (_error != null ? 'Ой' : 'Говори, я слушаю'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 18),
            if (_error != null)
              Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium)
            else
              ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(gradient: context.eva.hero, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                      : const Icon(Icons.mic_rounded, color: Colors.white, size: 44),
                ),
              ),
            const SizedBox(height: 14),
            if (_error == null)
              Text(_sending ? 'Распознаю речь' : '$time / 1:00', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _sending ? null : (_error != null ? () => Navigator.pop(context) : _cancel),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(_error != null ? 'Закрыть' : 'Отмена'),
                ),
              ),
              if (_error == null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: EvaPrimaryButton(
                    label: 'Отправить',
                    icon: Icons.arrow_upward_rounded,
                    height: 50,
                    loading: _sending,
                    onPressed: _recording && !_sending ? _send : null,
                  ),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
