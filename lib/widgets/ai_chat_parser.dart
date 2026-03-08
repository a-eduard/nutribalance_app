import 'package:flutter/material.dart';
import '../services/database_service.dart';

class AIChatSaveCardWidget extends StatefulWidget {
  final Map<String, dynamic> jsonData;
  final String msgId;
  final String botType;
  final Color themeColor;
  final bool isInitiallySaved;
  final Function(String) onSaveSuccess;
  final Function(String) onSendMessage;

  const AIChatSaveCardWidget({
    super.key,
    required this.jsonData,
    required this.msgId,
    required this.botType,
    required this.themeColor,
    required this.isInitiallySaved,
    required this.onSaveSuccess,
    required this.onSendMessage,
  });

  @override
  State<AIChatSaveCardWidget> createState() => _AIChatSaveCardWidgetState();
}

class _AIChatSaveCardWidgetState extends State<AIChatSaveCardWidget> {
  late bool _isSaved;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isInitiallySaved;
  }

  @override
  Widget build(BuildContext context) {
    final String actionType = widget.jsonData['action_type'] ?? widget.jsonData['type'] ?? '';
    
    if (actionType == 'advice') return const SizedBox.shrink();

    if (actionType == 'needs_plan') {
      final draft = widget.jsonData['draft_meal'] ?? {};
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E).withValues(alpha: 0.9), 
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3))
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: Text("⚠️ Нет плана питания", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 16.0),
              child: Center(
                child: Text("Чтобы сохранить ${draft['meal_name'] ?? 'блюдо'}, нужно рассчитать дневную норму.", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              ),
            ),
            if (!_isSaved)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: (_isLoading || _isSaved) ? null : () async {
                        setState(() => _isLoading = true);
                        try {
                          await DatabaseService().saveMealDraft(draft);
                          await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                          setState(() => _isSaved = true);
                          widget.onSaveSuccess(widget.msgId);
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      child: _isLoading ? const CircularProgressIndicator(strokeWidth: 2) : const Text("ПОЗЖЕ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: widget.themeColor, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: (_isLoading || _isSaved) ? null : () async {
                        widget.onSendMessage("Помоги составить план питания и рассчитать норму КБЖУ");
                        await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                        setState(() => _isSaved = true);
                        widget.onSaveSuccess(widget.msgId);
                      },
                      child: const Text("СОСТАВИТЬ ПЛАН", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              )
            else
              const Center(child: Text("ОБРАБОТАНО", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))
          ],
        ),
      );
    }

    String title = "Данные обработаны";
    String description = "";
    String buttonText = "СОХРАНИТЬ";
    Color cardAccentColor = widget.themeColor; 

    if (actionType == 'shopping_list') {
      title = "🛒 Список покупок";
      description = "Ева составила список продуктов. Хотите сохранить его на Главный экран?";
      buttonText = "СОХРАНИТЬ СПИСОК";
      cardAccentColor = Colors.teal;
    } else if (actionType == 'update_goal' || actionType == 'set_goal') {
      title = "🎯 Ваша новая цель КБЖУ";
      description = "${widget.jsonData['calories'] ?? 0} ккал\nБ: ${widget.jsonData['protein'] ?? 0}г | Ж: ${widget.jsonData['fat'] ?? 0}г | У: ${widget.jsonData['carbs'] ?? 0}г";
      buttonText = "ОБНОВИТЬ ЦЕЛЬ";
    } else if (actionType == 'log_food' || actionType == 'log_meal') {
      title = "🍽 Добавление в дневник";
      buttonText = "ЗАПИСАТЬ В ДНЕВНИК";  
    } else if (actionType == 'save_to_rag' || actionType == 'save_food') {
      title = "📦 Новая этикетка";
      buttonText = "ЗАПИСАТЬ В БАЗУ ДАННЫХ";
      cardAccentColor = Colors.deepPurpleAccent; 
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.9), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: _isSaved ? Colors.grey.withValues(alpha: 0.2) : cardAccentColor.withValues(alpha: 0.5), width: 1.5)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
          if (description.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 12.0), child: Center(child: Text(description, style: TextStyle(color: cardAccentColor, fontSize: 14), textAlign: TextAlign.center))),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _isSaved ? Colors.transparent : cardAccentColor.withValues(alpha: 0.1),
                side: BorderSide(color: _isSaved ? Colors.grey.withValues(alpha: 0.3) : cardAccentColor.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_isSaved || _isLoading) ? null : () async {
                setState(() => _isLoading = true);
                try {
                  if (actionType == 'update_goal' || actionType == 'set_goal') {
                    await DatabaseService().saveNutritionGoal(widget.jsonData);
                  } else if (actionType == 'log_food' || actionType == 'log_meal') {
                    await DatabaseService().logMeal(widget.jsonData);
                  } else if (actionType == 'shopping_list') {
                    await DatabaseService().saveShoppingList(widget.jsonData);
                  }
                  
                  await DatabaseService().markBotMessageAsActionCompleted(widget.botType, widget.msgId);
                  setState(() => _isSaved = true);
                  widget.onSaveSuccess(widget.msgId);
                } catch (e) {
                  // handle error
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: cardAccentColor)) : Text(_isSaved ? "✓ СОХРАНЕНО" : buttonText, style: TextStyle(color: _isSaved ? Colors.grey : cardAccentColor, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}