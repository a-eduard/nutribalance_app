// «Моя полка»: косметика, которая у пользовательницы уже есть дома.
// Средства попадают сюда из разбора состава (кнопка «На мою полку»).
// Хранение: users/{uid}/cosmetics_shelf/{id} — полный разбор средства.
// Ева-косметолог видит полку (crossChatMemory на сервере) и может разобрать её целиком.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/analytics_service.dart';
import '../theme/eva_colors.dart';
import '../widgets/eva_ui.dart';
import 'ai_chat_screen.dart';
import 'label_scanner_screen.dart';

class CosmeticShelf {
  CosmeticShelf._();

  static CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).collection('cosmetics_shelf');
  }

  /// Id записи на полке: id скана, если он есть, иначе — из названия.
  static String idFor(Map<String, dynamic> data) {
    final String scanId = (data['id'] ?? '').toString();
    if (scanId.isNotEmpty) return scanId;
    final String name = (data['productName'] ?? 'item').toString().toLowerCase().replaceAll(RegExp(r'[^a-zа-я0-9]+'), '_');
    return name.length > 60 ? name.substring(0, 60) : name;
  }

  static Stream<bool> isOnShelf(Map<String, dynamic> data) {
    final col = _col;
    if (col == null) return Stream.value(false);
    return col.doc(idFor(data)).snapshots().map((d) => d.exists);
  }

  static Future<void> add(Map<String, dynamic> data) async {
    final col = _col;
    if (col == null) return;
    final Map<String, dynamic> doc = {
      for (final k in ['productName', 'productType', 'score', 'verdict', 'good', 'watch', 'skinTypes', 'pregnancy', 'pregnancyNote', 'howToUse', 'phaseTip', 'basedOnName'])
        if (data[k] != null) k: data[k],
      'kind': 'cosmetic',
      'addedAt': FieldValue.serverTimestamp(),
    };
    await col.doc(idFor(data)).set(doc);
  }

  static Future<void> remove(String id) async => _col?.doc(id).delete();

  static Stream<QuerySnapshot<Map<String, dynamic>>>? stream() => _col?.snapshots();
}

/// Кнопка на экране разбора средства: «На мою полку» / «На полке».
class ShelfButton extends StatelessWidget {
  final Map<String, dynamic> data;
  const ShelfButton({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: CosmeticShelf.isOnShelf(data),
      builder: (context, snap) {
        final bool on = snap.data == true;
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: Icon(on ? PhosphorIconsFill.checkCircle : PhosphorIconsLight.plusCircle),
          label: Text(on ? 'На моей полке' : 'Это моё — на полку'),
          onPressed: () async {
            if (on) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CosmeticShelfScreen()));
              return;
            }
            await CosmeticShelf.add(data);
            Analytics.event('shelf_add');
            if (context.mounted) {
              EvaSnack.show(context, 'Добавила на полку. Ева учтёт его в советах ✨', type: EvaSnackType.success);
            }
          },
        );
      },
    );
  }
}

class CosmeticShelfScreen extends StatelessWidget {
  const CosmeticShelfScreen({super.key});

  static String _plural(int n) {
    final int m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return '$n средство';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n средства';
    return '$n средств';
  }

  void _askEva(BuildContext context, List<Map<String, dynamic>> items) {
    Analytics.event('shelf_review', {'count': items.length});
    final String list = items.map((x) => '«${x['productName']}»${(x['productType'] ?? '').toString().isNotEmpty ? ' (${x['productType']})' : ''}').join(', ');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatScreen(
          botType: 'cosmetologist',
          initialDisplayMessage: 'Разбери мою полку косметики',
          initialTechnicalPrompt: 'Разбери мою полку косметики: $list. '
              'Составь уход утром и вечером только из того, что у меня есть (по шагам, что за чем). '
              'Скажи честно: какие средства дублируют друг друга и что можно пока убрать; что нельзя сочетать в один день; '
              'что не подходит моему типу кожи; чего реально не хватает. Коротко, списками.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stream = CosmeticShelf.stream();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Моя полка'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.maybePop(context)),
        actions: [
          IconButton(
            tooltip: 'Добавить средство',
            icon: const Icon(PhosphorIconsLight.plus),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelScannerScreen(initialKind: 'cosmetic'))),
          ),
        ],
      ),
      body: EvaBackground(
        child: stream == null
            ? const SizedBox.shrink()
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: stream,
                builder: (context, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs.toList()
                    ..sort((a, b) {
                      final ta = a.data()['addedAt'], tb = b.data()['addedAt'];
                      if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
                      return 0;
                    });
                  final items = [for (final d in docs) {'id': d.id, ...d.data()}];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(EvaSpace.page, 8, EvaSpace.page, 40),
                    children: [
                      EvaCard(
                        gradient: context.eva.hero,
                        border: false,
                        padding: const EdgeInsets.all(22),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          EvaOverline('Ева-косметолог', color: Colors.white.withValues(alpha: 0.85)),
                          const SizedBox(height: 8),
                          Text(items.isEmpty ? 'Собери свою полку' : 'У тебя ${_plural(items.length)}',
                              style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(
                            'Добавляй средства, которые уже есть дома. Ева соберёт уход из того, что есть, подскажет, что дублируется, что не подходит коже и чего не хватает.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      if (items.isNotEmpty) ...[
                        EvaPrimaryButton(
                          label: 'Разобрать полку с Евой',
                          icon: PhosphorIconsLight.sparkle,
                          onPressed: () => _askEva(context, items),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (items.isEmpty)
                        EvaEmptyState(
                          icon: PhosphorIconsLight.drop,
                          title: 'Полка пока пустая',
                          subtitle: 'Сфотографируй состав крема, сыворотки или шампуня и нажми «Это моё — на полку».',
                          actionLabel: 'Отсканировать средство',
                          onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabelScannerScreen(initialKind: 'cosmetic'))),
                        )
                      else
                        for (final x in items) _ShelfTile(item: x),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _ShelfTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ShelfTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String score = (item['score'] ?? 'ok').toString();
    final (String scoreText, Color scoreColor) = switch (score) {
      'good' => ('Хороший состав', EvaColors.success),
      'limit' => ('Есть нюансы', EvaColors.warning),
      _ => ('Нормальный состав', EvaColors.lavender),
    };
    final String type = (item['productType'] ?? '').toString();
    final String id = item['id'].toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(color: EvaColors.error.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(22)),
          child: Icon(PhosphorIconsLight.trash, color: EvaColors.error),
        ),
        confirmDismiss: (_) async => _confirmDelete(context),
        onDismissed: (_) {
          CosmeticShelf.remove(id);
          Analytics.event('shelf_remove');
        },
        child: EvaCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LabelResultScreen(data: {...item, 'kind': 'cosmetic'}))),
          child: Row(children: [
            EvaIconBubble(icon: PhosphorIconsLight.drop, color: scoreColor, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((item['productName'] ?? 'Средство').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text([if (type.isNotEmpty) type, scoreText].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(PhosphorIconsLight.dotsThreeVertical, color: theme.colorScheme.onSurfaceVariant),
              onSelected: (v) async {
                if (v == 'del' && await _confirmDelete(context)) {
                  CosmeticShelf.remove(id);
                  Analytics.event('shelf_remove');
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Убрать с полки'))],
            ),
          ]),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Убрать с полки?'),
        content: Text('«${item['productName'] ?? 'Средство'}» больше не будет учитываться в советах Евы.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Убрать')),
        ],
      ),
    );
    return ok == true;
  }
}
