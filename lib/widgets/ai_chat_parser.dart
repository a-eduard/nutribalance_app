import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../theme/eva_colors.dart';
import 'eva_ui.dart';

class AIChatSaveCardWidget extends StatefulWidget {
  final Map<String, dynamic> jsonData;
  final String msgId;
  final String botType;
  final Color themeColor;
  final bool isInitiallySaved;
  final String? imageUrl;
  final Function(String) onSaveSuccess;
  final Function(String) onSendMessage;

  const AIChatSaveCardWidget({
    super.key,
    required this.jsonData,
    required this.msgId,
    required this.botType,
    required this.themeColor,
    required this.isInitiallySaved,
    this.imageUrl,
    required this.onSaveSuccess,
    required this.onSendMessage,
  });

  @override
  State<AIChatSaveCardWidget> createState() => _AIChatSaveCardWidgetState();
}

class _AIChatSaveCardWidgetState extends State<AIChatSaveCardWidget> {
  late bool _isSaved;
  bool _isSavingNow = false; 
  late Map<String, dynamic> _editableData;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isInitiallySaved;
    _editableData = jsonDecode(jsonEncode(widget.jsonData));
    if (widget.imageUrl != null) {
      _editableData['imageUrl'] = widget.imageUrl;
    }
  }

  void _editMacro(String macroType, int newValue, int oldCals, int oldP, int oldF, int oldC) {
    List<dynamic> items = _editableData['items'] ?? [];
    if (items.isEmpty && (_editableData['meal_name'] != null || _editableData['name'] != null)) {
      items = [_editableData]; 
    }
    if (items.isEmpty) return;

    setState(() {
      if (macroType == 'calories') {
        if (oldCals <= 0) return; 
        
        double ratio = newValue / oldCals;
        for (var item in items) {
          item['calories'] = (((item['calories'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['protein'] = (((item['protein'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['fat'] = (((item['fat'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['carbs'] = (((item['carbs'] as num?)?.toDouble() ?? 0) * ratio).round();
          
          if (item['fiber'] != null) {
            item['fiber'] = (((item['fiber'] as num).toDouble()) * ratio).round();
          } else {
            item['fiber'] = 0;
          }
        }
      } else {
        int diff = 0;
        int calDiff = 0;
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
          int currentFiberValue = (items.first['fiber'] as num?)?.toInt() ?? 0;
          diff = newValue - currentFiberValue; 
          calDiff = 0; 
        }

        var first = items.first;
        int currentMacro = (first[macroType] as num?)?.toInt() ?? 0;
        int currentCals = (first['calories'] as num?)?.toInt() ?? 0;

        int newMacroValue = currentMacro + diff;
        int newCalsValue = currentCals + calDiff;

        first[macroType] = newMacroValue < 0 ? 0 : newMacroValue;
        first['calories'] = newCalsValue < 0 ? 0 : newCalsValue;
      }
    });
  }

  void _showEditDialog(String label, int currentValue, String macroType, int oldC, int oldP, int oldF, int oldCarb, ThemeData theme) {
    if (_isSaved) return; 
    final TextEditingController ctrl = TextEditingController(text: currentValue.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Изменить: ${label.toLowerCase()}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: theme.textTheme.headlineMedium,
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

  Widget _buildMacroEditBtn(String label, int value, String type, int tc, int tp, int tf, int tcarb, Color color, ThemeData theme) {
    return EvaPressable(
      onTap: _isSaved ? null : () => _showEditDialog(label, value, type, tc, tp, tf, tcarb, theme),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (!_isSaved) Icon(Icons.edit_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 4),
            Text("$value г", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Future<void> _save(String actionType, bool isLogFood) async {
    setState(() => _isSavingNow = true);
    try {
      if (widget.imageUrl != null) {
        _editableData['imageUrl'] = widget.imageUrl;
      }
      // Записи в Firestore не блокируют интерфейс: при слабой сети/VPN они
      // сохраняются локально и досинхронизируются автоматически.
      if (actionType == 'update_goal' || actionType == 'set_goal') {
        await DatabaseService().saveNutritionGoal(_editableData);
      } else if (isLogFood) {
        await DatabaseService().logMeal(_editableData);
      } else if (actionType == 'shopping_list') {
        await DatabaseService().saveShoppingList(_editableData);
      }
      await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);

      if (!mounted) return;
      setState(() {
        _isSaved = true;
        _isSavingNow = false;
      });
      widget.onSaveSuccess(widget.msgId);
      EvaSnack.show(context, isLogFood ? 'Записала в дневник ✨' : 'Сохранено ✨', type: EvaSnackType.success);
    } catch (e) {
      debugPrint('Ошибка БД: $e');
      if (!mounted) return;
      setState(() => _isSavingNow = false);
      EvaSnack.show(context, 'Не получилось сохранить. Попробуйте ещё раз.', type: EvaSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.eva;
    final String actionType = (_editableData['action_type'] ?? _editableData['type'] ?? '').toString();

    if (actionType == 'advice' || actionType.isEmpty) return const SizedBox.shrink();

    if (actionType == 'needs_plan') {
      final draft = _editableData['draft_meal'] is Map ? Map<String, dynamic>.from(_editableData['draft_meal']) : <String, dynamic>{};
      return Padding(
        padding: const EdgeInsets.only(top: 10, right: 24),
        child: EvaCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                EvaIconBubble(icon: Icons.flag_outlined, color: palette.warning, size: 38, iconSize: 19),
                const SizedBox(width: 12),
                Expanded(child: Text('Нужен план питания', style: theme.textTheme.titleMedium)),
              ]),
              const SizedBox(height: 10),
              Text("Чтобы записать «${draft['meal_name'] ?? 'блюдо'}», давай сначала рассчитаем твою дневную норму.", style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              if (_isSaved)
                EvaPill(text: 'Обработано', icon: Icons.check_rounded, color: palette.success)
              else
                Row(
                  children: [
                    Expanded(
                      child: EvaSecondaryButton(
                        label: 'Позже',
                        height: 46,
                        onPressed: _isSavingNow
                            ? null
                            : () async {
                                setState(() => _isSavingNow = true);
                                await DatabaseService().saveMealDraft(draft);
                                await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                                if (!mounted) return;
                                setState(() {
                                  _isSaved = true;
                                  _isSavingNow = false;
                                });
                                widget.onSaveSuccess(widget.msgId);
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: EvaPrimaryButton(
                        label: 'Составить план',
                        height: 46,
                        loading: _isSavingNow,
                        onPressed: () async {
                          setState(() => _isSavingNow = true);
                          await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                          widget.onSendMessage("Помоги составить план питания и рассчитать норму КБЖУ");
                          if (!mounted) return;
                          setState(() {
                            _isSaved = true;
                            _isSavingNow = false;
                          });
                          widget.onSaveSuccess(widget.msgId);
                        },
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );
    }

    String title = "Данные обработаны";
    String description = "";
    String buttonText = "Сохранить";
    IconData icon = Icons.auto_awesome_rounded;
    Color accent = widget.themeColor;
    final bool isLogFood = (actionType == 'log_food' || actionType == 'log_meal');
    int totalCals = 0, totalP = 0, totalF = 0, totalC = 0, totalFiber = 0;
    String mealName = 'Приём пищи';

    if (actionType == 'shopping_list') {
      title = "Список покупок";
      description = "Ева составила список продуктов. Сохранить его?";
      buttonText = "Сохранить список";
      icon = Icons.shopping_bag_outlined;
      accent = palette.gold;
    } else if (actionType == 'update_goal' || actionType == 'set_goal') {
      title = "Новая цель КБЖУ";
      description = "${evaInt(_editableData['calories'])} ккал · Б ${evaInt(_editableData['protein'])} · Ж ${evaInt(_editableData['fat'])} · У ${evaInt(_editableData['carbs'])} г";
      buttonText = "Обновить цель";
      icon = Icons.track_changes_rounded;
    } else if (isLogFood) {
      title = "Добавить в дневник";
      buttonText = "Записать в дневник";
      icon = Icons.restaurant_rounded;
      List<dynamic> items = _editableData['items'] is List ? _editableData['items'] : [];
      if (items.isEmpty && (_editableData['meal_name'] != null || _editableData['name'] != null)) items = [_editableData];
      mealName = (_editableData['meal_name'] ?? _editableData['name'] ?? (items.isNotEmpty && items.first is Map ? items.first['meal_name'] ?? items.first['name'] : null) ?? 'Приём пищи').toString();
      for (final item in items) {
        if (item is! Map) continue;
        totalCals += evaInt(item['calories']);
        totalP += evaInt(item['protein']);
        totalF += evaInt(item['fat']);
        totalC += evaInt(item['carbs']);
        totalFiber += evaInt(item['fiber']);
      }
    } else if (actionType == 'save_to_rag' || actionType == 'save_food') {
      title = "Новая этикетка";
      buttonText = "Сохранить продукт";
      icon = Icons.qr_code_2_rounded;
      accent = palette.lavender;
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 24),
      child: EvaCard(
        padding: const EdgeInsets.all(18),
        borderColor: _isSaved ? palette.hairline : accent.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EvaIconBubble(icon: icon, color: accent, size: 38, iconSize: 19),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                if (_isSaved) EvaPill(text: 'Сохранено', icon: Icons.check_rounded, color: palette.success),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (isLogFood) ...[
              const SizedBox(height: 14),
              Text(mealName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              EvaPressable(
                onTap: _isSaved ? null : () => _showEditDialog('Калории', totalCals, 'calories', totalCals, totalP, totalF, totalC, theme),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text("$totalCals", style: theme.textTheme.displaySmall?.copyWith(color: accent)),
                    const SizedBox(width: 6),
                    Padding(padding: const EdgeInsets.only(bottom: 6), child: Text("ккал", style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
                    if (!_isSaved) ...[
                      const SizedBox(width: 6),
                      Padding(padding: const EdgeInsets.only(bottom: 8), child: Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _buildMacroEditBtn("Белки", totalP, "protein", totalCals, totalP, totalF, totalC, EvaColors.protein, theme)),
                const SizedBox(width: 8),
                Expanded(child: _buildMacroEditBtn("Жиры", totalF, "fat", totalCals, totalP, totalF, totalC, EvaColors.fat, theme)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _buildMacroEditBtn("Углеводы", totalC, "carbs", totalCals, totalP, totalF, totalC, EvaColors.carbs, theme)),
                const SizedBox(width: 8),
                Expanded(child: _buildMacroEditBtn("Клетчатка", totalFiber, "fiber", totalCals, totalP, totalF, totalC, EvaColors.fiber, theme)),
              ]),
            ],
            if (!_isSaved) ...[
              const SizedBox(height: 16),
              EvaPrimaryButton(
                label: buttonText,
                height: 50,
                loading: _isSavingNow,
                onPressed: () => _save(actionType, isLogFood),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
