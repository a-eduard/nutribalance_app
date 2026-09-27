// Общие элементы чатов (P2P и чат с Евой).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/eva_colors.dart';
import 'eva_ui.dart';

class ChatTime {
  ChatTime._();

  static bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    if (sameDay(d, now)) return 'Сегодня';
    if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Вчера';
    if (d.year == now.year) return DateFormat('d MMMM', 'ru').format(d);
    return DateFormat('d MMMM yyyy', 'ru').format(d);
  }

  static String listLabel(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (sameDay(d, now)) return DateFormat('HH:mm').format(d);
    if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Вчера';
    if (now.difference(d).inDays < 7) return EvaFormat.capitalize(DateFormat('EE', 'ru').format(d));
    return DateFormat('dd.MM.yy').format(d);
  }
}

class ChatDaySeparator extends StatelessWidget {
  final DateTime day;
  const ChatDaySeparator({super.key, required this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: context.eva.hairline),
          ),
          child: Text(ChatTime.dayLabel(day), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ),
    );
  }
}

/// Пузырь сообщения в стиле Soft Luxury.
class ChatBubble extends StatelessWidget {
  final bool isMe;
  final Widget child;
  final String time;
  final Widget? status;
  final bool compactTop;
  final EdgeInsetsGeometry padding;
  final double maxWidthFactor;

  const ChatBubble({
    super.key,
    required this.isMe,
    required this.child,
    required this.time,
    this.status,
    this.compactTop = false,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 8),
    this.maxWidthFactor = 0.78,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final Color metaColor = isMe ? Colors.white.withValues(alpha: 0.78) : theme.colorScheme.onSurfaceVariant;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: compactTop ? 2 : 8, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * maxWidthFactor),
        padding: padding,
        decoration: BoxDecoration(
          gradient: isMe
              ? LinearGradient(
                  colors: [theme.colorScheme.primary, Color.lerp(theme.colorScheme.primary, palette.gold, 0.35)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMe ? null : theme.colorScheme.surface,
          border: isMe ? null : Border.all(color: palette.hairline),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isMe ? 22 : 6),
            bottomRight: Radius.circular(isMe ? 6 : 22),
          ),
          boxShadow: isMe
              ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))]
              : palette.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle.merge(
              style: TextStyle(color: isMe ? Colors.white : theme.colorScheme.onSurface),
              child: child,
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time, style: theme.textTheme.labelSmall?.copyWith(color: metaColor, fontWeight: FontWeight.w500, fontSize: 10.5)),
                if (status != null) ...[const SizedBox(width: 4), status!],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Поле ввода сообщения.
class ChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final bool busy;
  final String hint;
  final Widget? top;
  final bool allowEmptySend;

  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onAttach,
    this.busy = false,
    this.hint = 'Сообщение…',
    this.top,
    this.allowEmptySend = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final bool has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final bool canSend = (_hasText || widget.allowEmptySend) && !widget.busy;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.top != null) widget.top!,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.onAttach != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: IconButton(
                        onPressed: widget.busy ? null : widget.onAttach,
                        icon: Icon(Icons.add_circle_outline_rounded, color: theme.colorScheme.primary, size: 28),
                        tooltip: 'Прикрепить',
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: widget.hint,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: palette.hairline)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.2)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EvaPressable(
                    onTap: canSend ? widget.onSend : null,
                    pressedScale: 0.9,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: canSend ? palette.hero : null,
                        color: canSend ? null : palette.fieldFill,
                        shape: BoxShape.circle,
                        boxShadow: canSend
                            ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))]
                            : null,
                      ),
                      child: widget.busy
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary),
                            )
                          : Icon(Icons.arrow_upward_rounded, color: canSend ? Colors.white : theme.colorScheme.onSurfaceVariant, size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Лёгкий рендер markdown для ответов Евы: **жирный**, заголовки, списки.
class EvaMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color? accent;

  const EvaMarkdownText(this.text, {super.key, this.style, this.accent});

  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
  static final RegExp _numbered = RegExp(r'^(\d{1,2})[\.\)]\s+(.*)$');

  List<InlineSpan> _inline(String s, TextStyle base) {
    final List<InlineSpan> spans = [];
    int last = 0;
    for (final m in _bold.allMatches(s)) {
      if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1) ?? m.group(2), style: base.copyWith(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final TextStyle base = (style ?? theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(height: 1.45);
    final Color bulletColor = accent ?? theme.colorScheme.primary;
    final List<Widget> children = [];

    for (final rawLine in text.replaceAll('\r', '').split('\n')) {
      final String line = rawLine.trimRight();
      final String trimmed = line.trimLeft();
      if (trimmed.isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }
      if (trimmed.startsWith('#')) {
        final String h = trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text.rich(TextSpan(children: _inline(h, base)), style: base.copyWith(fontWeight: FontWeight.w700, fontSize: (base.fontSize ?? 15) + 1)),
        ));
        continue;
      }
      final bool bullet = trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('• ') || trimmed.startsWith('– ');
      final Match? numMatch = _numbered.firstMatch(trimmed);
      if (bullet || numMatch != null) {
        final String content = bullet ? trimmed.substring(2) : numMatch!.group(2)!;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: bullet
                    ? Padding(
                        padding: EdgeInsets.only(top: (base.fontSize ?? 15) * 0.55),
                        child: Container(width: 5, height: 5, decoration: BoxDecoration(color: bulletColor, shape: BoxShape.circle)),
                      )
                    : Text('${numMatch!.group(1)}.', style: base.copyWith(color: bulletColor, fontWeight: FontWeight.w700)),
              ),
              Expanded(child: Text.rich(TextSpan(children: _inline(content, base)), style: base)),
            ],
          ),
        ));
        continue;
      }
      children.add(Text.rich(TextSpan(children: _inline(line, base)), style: base));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
  }
}
