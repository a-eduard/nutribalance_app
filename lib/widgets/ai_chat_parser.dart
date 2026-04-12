import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/database_service.dart';

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
  late Map<String, dynamic> _editableData;
  
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

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
        if (oldCals == 0) return;
        double ratio = newValue / oldCals;
        for (var item in items) {
          item['calories'] = (((item['calories'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['protein'] = (((item['protein'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['fat'] = (((item['fat'] as num?)?.toDouble() ?? 0) * ratio).round();
          item['carbs'] = (((item['carbs'] as num?)?.toDouble() ?? 0) * ratio).round();
          if (item['fiber'] != null) {
            item['fiber'] = (((item['fiber'] as num).toDouble()) * ratio).round();
          }
        }
      } else {
        int diff = 0;
        int calDiff = 0;
        if (macroType == 'protein') { diff = newValue - oldP; calDiff = diff * 4; } 
        else if (macroType == 'fat') { diff = newValue - oldF; calDiff = diff * 9; } 
        else if (macroType == 'carbs') { diff = newValue - oldC; calDiff = diff * 4; }

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

  void _showEditDialog(String label, int currentValue, String macroType, int oldC, int oldP, int oldF, int oldCarb) {
    if (_isSaved) return; 
    final TextEditingController ctrl = TextEditingController(text: currentValue.toString());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Изменить $label', style: const TextStyle(color: _textColor, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900),
          decoration: InputDecoration(
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.themeColor, width: 2)),
            suffixText: macroType == 'calories' ? 'ккал' : 'г',
          ),
          cursorColor: widget.themeColor,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: widget.themeColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val >= 0) {
                _editMacro(macroType, val, oldC, oldP, oldF, oldCarb);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  Widget _buildMacroEditBtn(String label, int value, String type, int tc, int tp, int tf, int tcarb, Color color) {
    return GestureDetector(
      onTap: () => _showEditDialog(label, value, type, tc, tp, tf, tcarb),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(color: _textColor, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (!_isSaved) const Icon(Icons.edit_outlined, size: 16, color: _subTextColor),
              ],
            ),
            const SizedBox(height: 4),
            Text("${value}г", style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w900)),
          ]
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final String actionType = _editableData['action_type'] ?? _editableData['type'] ?? '';
    if (actionType == 'advice') return const SizedBox.shrink();

    if (actionType == 'needs_plan') {
      final draft = _editableData['draft_meal'] ?? {};
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text("⚠️ Нет плана питания", style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16))),
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 16.0),
              child: Center(child: Text("Чтобы сохранить ${draft['meal_name'] ?? 'блюдо'}, нужно рассчитать дневную норму.", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.center)),
            ),
            if (!_isSaved)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _isSaved ? null : () {
                        setState(() => _isSaved = true);
                        widget.onSaveSuccess(widget.msgId);
                        Future.microtask(() async {
                          try {
                            await DatabaseService().saveMealDraft(draft);
                            await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                          } catch(e) {}
                        });
                      },
                      child: const Text("ПОЗЖЕ", style: TextStyle(color: _subTextColor, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: widget.themeColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                      onPressed: _isSaved ? null : () {
                        widget.onSendMessage("Помоги составить план питания и рассчитать норму КБЖУ");
                        setState(() => _isSaved = true);
                        widget.onSaveSuccess(widget.msgId);
                        Future.microtask(() async {
                          try {
                            await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                          } catch(e) {}
                        });
                      },
                      child: const Text("СОСТАВИТЬ ПЛАН", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              )
            else
              const Center(child: Text("ОБРАБОТАНО", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold)))
          ],
        ),
      );
    }

    String title = "Данные обработаны"; String description = ""; String buttonText = "СОХРАНИТЬ";
    Color cardAccentColor = widget.themeColor; 
    bool isLogFood = (actionType == 'log_food' || actionType == 'log_meal');
    int totalCals = 0, totalP = 0, totalF = 0, totalC = 0; String mealName = 'Прием пищи';

    if (actionType == 'shopping_list') {
      title = "🛒 Список покупок"; description = "Ева составила список продуктов. Хотите сохранить его на Главный экран?"; buttonText = "СОХРАНИТЬ СПИСОК"; cardAccentColor = Colors.teal;
    } else if (actionType == 'update_goal' || actionType == 'set_goal') {
      title = "🎯 Ваша новая цель КБЖУ"; description = "${_editableData['calories'] ?? 0} ккал\nБ: ${_editableData['protein'] ?? 0}г | Ж: ${_editableData['fat'] ?? 0}г | У: ${_editableData['carbs'] ?? 0}г"; buttonText = "ОБНОВИТЬ ЦЕЛЬ";
    } else if (isLogFood) {
      title = "🍽 Добавление в дневник"; buttonText = "ЗАПИСАТЬ В ДНЕВНИК";
      List<dynamic> items = _editableData['items'] ?? [];
      if (items.isEmpty && (_editableData['meal_name'] != null || _editableData['name'] != null)) items = [_editableData];
      mealName = _editableData['meal_name'] ?? _editableData['name'] ?? (items.isNotEmpty ? items.first['name'] : null) ?? 'Прием пищи';
      for (var item in items) { totalCals += (item['calories'] as num?)?.toInt() ?? 0; totalP += (item['protein'] as num?)?.toInt() ?? 0; totalF += (item['fat'] as num?)?.toInt() ?? 0; totalC += (item['carbs'] as num?)?.toInt() ?? 0; }
    } else if (actionType == 'save_to_rag' || actionType == 'save_food') {
      title = "📦 Новая этикетка"; buttonText = "ЗАПИСАТЬ В БАЗУ ДАННЫХ"; cardAccentColor = Colors.deepPurpleAccent; 
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))], border: Border.all(color: _isSaved ? const Color(0xFFE5E5EA) : cardAccentColor.withValues(alpha: 0.3), width: 1.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(title, style: const TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16))),
          if (description.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12.0), child: Center(child: Text(description, style: TextStyle(color: cardAccentColor, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center))),
          if (isLogFood) ...[
            const SizedBox(height: 16),
            Center(child: Text(mealName, style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showEditDialog('Калории', totalCals, 'calories', totalCals, totalP, totalF, totalC),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("$totalCals ккал", style: TextStyle(color: widget.themeColor, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1.0)), if (!_isSaved) ...[const SizedBox(width: 8), const Icon(Icons.edit_outlined, size: 16, color: _subTextColor)]]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMacroEditBtn("Белки", totalP, "protein", totalCals, totalP, totalF, totalC, const Color(0xFFD49A89))), const SizedBox(width: 8),
                Expanded(child: _buildMacroEditBtn("Жиры", totalF, "fat", totalCals, totalP, totalF, totalC, const Color(0xFFE5C158))), const SizedBox(width: 8),
                Expanded(child: _buildMacroEditBtn("Углеводы", totalC, "carbs", totalCals, totalP, totalF, totalC, const Color(0xFF89CFF0))),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _isSaved ? Colors.transparent : cardAccentColor.withValues(alpha: 0.1),
                side: BorderSide(color: _isSaved ? const Color(0xFFE5E5EA) : cardAccentColor.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSaved ? null : () {
                // МГНОВЕННОЕ СОХРАНЕНИЕ В ИНТЕРФЕЙСЕ
                setState(() => _isSaved = true);
                widget.onSaveSuccess(widget.msgId);
                
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Успешно сохранено! ✨', style: TextStyle(fontWeight: FontWeight.bold)), 
                  backgroundColor: Colors.teal,
                  duration: Duration(seconds: 2),
                ));

                // ОТПРАВКА ДАННЫХ В ФОНЕ (ИЗОЛИРОВАННО ОТ ИНТЕРФЕЙСА)
                Future.microtask(() async {
                  try {
                    if (widget.imageUrl != null) {
                      _editableData['imageUrl'] = widget.imageUrl;
                    }

                    if (actionType == 'update_goal' || actionType == 'set_goal') {
                      await DatabaseService().saveNutritionGoal(_editableData);
                    } else if (isLogFood) {
                      await DatabaseService().logMeal(_editableData);
                    } else if (actionType == 'shopping_list') {
                      await DatabaseService().saveShoppingList(_editableData);
                    }
                    
                    await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                  } catch (e) {
                    debugPrint('Фоновая ошибка БД: $e');
                  }
                });
              },
              child: Text(
                _isSaved ? "✓ СОХРАНЕНО" : buttonText, 
                style: TextStyle(color: _isSaved ? _subTextColor : cardAccentColor, fontWeight: FontWeight.bold)
              ),
            ),
          ),
        ],
      ),
    );
  }
}