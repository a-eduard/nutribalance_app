import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../paywall_screen.dart';
import '../../screens/ai_chat_screen.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import '../../theme/eva_colors.dart';
import '../eva_ui.dart';

/// Быстрый сканер еды по фото.
class FastFoodScannerSheet extends StatefulWidget {
  const FastFoodScannerSheet({super.key});

  static void show(BuildContext context) {
    EvaSheet.show<void>(context, builder: (_) => const FastFoodScannerSheet());
  }

  @override
  State<FastFoodScannerSheet> createState() => _FastFoodScannerSheetState();
}

enum _ScanState { selecting, analyzing, result }

class _FastFoodScannerSheetState extends State<FastFoodScannerSheet> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;
  _ScanState _state = _ScanState.selecting;
  Map<String, dynamic>? _resultData;
  String? _errorMessage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      // 1024px/60% — хороший баланс точности распознавания и размера (~100–200 КБ).
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 60, maxWidth: 1024, maxHeight: 1024);
      if (pickedFile == null) return;
      final bytes = await pickedFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _errorMessage = null;
        _state = _ScanState.analyzing;
      });
      await _analyzeImage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.selecting;
        _errorMessage = 'Нет доступа к камере или галерее';
      });
    }
  }

  Future<void> _analyzeImage() async {
    final bytes = _imageBytes;
    if (bytes == null) return;
    try {
      final response = await AIService().sendMultimodalMessage(
        userMessage: "Проанализируй это блюдо. Верни СТРОГО JSON формат (action_type: log_food), разбив на ингредиенты.",
        base64Image: base64Encode(bytes),
        userContext: "",
      );
      final parsedJson = _extractJson(response);
      if (!mounted) return;
      if (parsedJson != null && parsedJson['items'] is List && (parsedJson['items'] as List).isNotEmpty) {
        setState(() {
          _resultData = parsedJson;
          _state = _ScanState.result;
        });
      } else {
        setState(() {
          _state = _ScanState.selecting;
          _errorMessage = 'Ева не смогла распознать еду. Попробуй сфотографировать ближе и при хорошем свете.';
        });
      }
    } on EvaQuotaException {
      if (!mounted) return;
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => const PaywallScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ScanState.selecting;
        _errorMessage = e is EvaUnavailableException ? e.message : 'Ошибка связи с сервером. Проверь интернет.';
      });
    }
  }

  Map<String, dynamic>? _extractJson(String text) {
    try {
      final String tick = String.fromCharCode(96);
      final String tripleTick = tick + tick + tick;
      final RegExp jsonRegExp = RegExp(tripleTick + r'(?:json)?\s*(\{.*?\})\s*' + tripleTick, dotAll: true);
      final match = jsonRegExp.firstMatch(text);
      if (match != null) {
        final d = jsonDecode(match.group(1)!);
        if (d is Map<String, dynamic>) return d;
      }
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start != -1 && end > start) {
        final d = jsonDecode(text.substring(start, end + 1));
        if (d is Map<String, dynamic>) return d;
      }
    } catch (e) {
      debugPrint("JSON Parse error: $e");
    }
    return null;
  }

  void _saveToDiary() {
    final data = _resultData;
    if (data == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    Navigator.pop(context);
    DatabaseService().logMeal(data, imageBytes: _imageBytes).catchError((e) => debugPrint('scanner save: $e'));
    EvaSnack.showOn(messenger, theme, 'Блюдо добавлено в дневник ✨', type: EvaSnackType.success);
  }

  void _editMacro(String macroType, int newValue, int oldCals, int oldP, int oldF, int oldC) {
    final List<dynamic> items = _resultData?['items'] is List ? _resultData!['items'] : const [];
    if (items.isEmpty) return;
    setState(() {
      if (macroType == 'calories') {
        if (oldCals == 0) return;
        final double ratio = newValue / oldCals;
        for (final item in items) {
          if (item is! Map) continue;
          item['calories'] = (evaDouble(item['calories']) * ratio).round();
          item['protein'] = (evaDouble(item['protein']) * ratio).round();
          item['fat'] = (evaDouble(item['fat']) * ratio).round();
          item['carbs'] = (evaDouble(item['carbs']) * ratio).round();
          item['fiber'] = (evaDouble(item['fiber']) * ratio).round();
        }
      } else {
        int diff = 0, calDiff = 0;
        final first = items.first;
        if (first is! Map) return;
        if (macroType == 'protein') {
          diff = newValue - oldP;
          calDiff = diff * 4;
        } else if (macroType == 'fat') {
          diff = newValue - oldF;
          calDiff = diff * 9;
        } else if (macroType == 'carbs') {
          diff = newValue - oldC;
          calDiff = diff * 4;
        } else if (macroType == 'fiber') {
          int totalFiber = 0;
          for (final i in items) {
            if (i is Map) totalFiber += evaInt(i['fiber']);
          }
          diff = newValue - totalFiber;
        }
        final int newMacro = evaInt(first[macroType]) + diff;
        final int newCals = evaInt(first['calories']) + calDiff;
        first[macroType] = newMacro < 0 ? 0 : newMacro;
        first['calories'] = newCals < 0 ? 0 : newCals;
      }
    });
  }

  void _showEditDialog(String label, int currentValue, String macroType, int oldC, int oldP, int oldF, int oldCarb) {
    final TextEditingController ctrl = TextEditingController(text: currentValue.toString());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Изменить: ${label.toLowerCase()}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: Theme.of(ctx).textTheme.headlineMedium,
          decoration: InputDecoration(suffixText: macroType == 'calories' ? 'ккал' : 'г'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val >= 0) {
                _editMacro(macroType, val, oldC, oldP, oldF, oldCarb);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: switch (_state) {
          _ScanState.selecting => _buildSelectionState(Theme.of(context)),
          _ScanState.analyzing => _buildAnalyzingState(Theme.of(context)),
          _ScanState.result => _buildResultState(Theme.of(context)),
        },
      ),
    );
  }

  Widget _buildSelectionState(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvaSheetHeader(title: 'Что на тарелке?', subtitle: 'Сфотографируй блюдо — Ева посчитает калории и БЖУ'),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: EvaStatusBanner(visible: true, text: _errorMessage!, icon: Icons.info_outline_rounded),
          ),
        EvaOptionTile(title: 'Сфотографировать', subtitle: 'Лучше сверху и при дневном свете', icon: Icons.photo_camera_outlined, selected: false, onTap: () => _pickImage(ImageSource.camera)),
        EvaOptionTile(title: 'Выбрать из галереи', icon: Icons.photo_library_outlined, selected: false, onTap: () => _pickImage(ImageSource.gallery)),
        EvaOptionTile(
          title: 'Описать словами',
          subtitle: 'Например: «гречка 150 г и котлета»',
          icon: Icons.edit_note_rounded,
          selected: false,
          onTap: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.push(MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
          },
        ),
      ],
    );
  }

  Widget _buildAnalyzingState(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const EvaSheetHandle(),
        if (_imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.memory(_imageBytes!, height: 220, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 20),
        const EvaTypingDots(),
        const SizedBox(height: 12),
        Text('Ева анализирует блюдо…', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Обычно это занимает 5–15 секунд', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _macroTile(String label, int value, String type, int tc, int tp, int tf, int tcarb, Color color, ThemeData theme) {
    return EvaPressable(
      onTap: () => _showEditDialog(label, value, type, tc, tp, tf, tcarb),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: context.isDark ? 0.18 : 0.1), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
              Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 4),
            Text('$value г', style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildResultState(ThemeData theme) {
    final List<dynamic> items = _resultData?['items'] is List ? _resultData!['items'] : const [];
    int totalCals = 0, totalP = 0, totalF = 0, totalC = 0, totalFiber = 0;
    for (final item in items) {
      if (item is! Map) continue;
      totalCals += evaInt(item['calories']);
      totalP += evaInt(item['protein']);
      totalF += evaInt(item['fat']);
      totalC += evaInt(item['carbs']);
      totalFiber += evaInt(item['fiber']);
    }
    final String mealName = (_resultData?['meal_name'] ?? (items.isNotEmpty && items.first is Map ? items.first['meal_name'] : null) ?? 'Блюдо').toString();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EvaSheetHandle(),
        Row(
          children: [
            if (_imageBytes != null)
              ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.memory(_imageBytes!, width: 84, height: 84, fit: BoxFit.cover)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mealName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  EvaPressable(
                    onTap: () => _showEditDialog('Калории', totalCals, 'calories', totalCals, totalP, totalF, totalC),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$totalCals', style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.primary, height: 1)),
                        const SizedBox(width: 6),
                        Text('ккал', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: _macroTile('Белки', totalP, 'protein', totalCals, totalP, totalF, totalC, EvaColors.protein, theme)),
          const SizedBox(width: 10),
          Expanded(child: _macroTile('Жиры', totalF, 'fat', totalCals, totalP, totalF, totalC, EvaColors.fat, theme)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _macroTile('Углеводы', totalC, 'carbs', totalCals, totalP, totalF, totalC, EvaColors.carbs, theme)),
          const SizedBox(width: 10),
          Expanded(child: _macroTile('Клетчатка', totalFiber, 'fiber', totalCals, totalP, totalF, totalC, EvaColors.fiber, theme)),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.eva.fieldFill, borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: items.whereType<Map>().map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text((item['meal_name'] ?? item['name'] ?? 'Продукт').toString(), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    Text('${evaInt(item['weight_g'])} г · ${evaInt(item['calories'])} ккал', style: theme.textTheme.bodySmall),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        EvaPrimaryButton(label: 'Добавить в дневник', icon: Icons.check_rounded, onPressed: _saveToDiary),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _resultData = null;
              _imageBytes = null;
              _state = _ScanState.selecting;
            }),
            child: const Text('Переснять фото'),
          ),
        ),
      ],
    );
  }
}
