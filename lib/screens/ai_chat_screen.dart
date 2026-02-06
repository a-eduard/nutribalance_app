import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/ai_service.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  String _fullUserContext = "";

  @override
  void initState() {
    super.initState();
    _loadFullUserContext();
    
    // НОВОЕ ПРИВЕТСТВИЕ ДИЕТОЛОГА
    _messages.add({
      'role': 'ai',
      'text': 'Привет! Я твой персональный диетолог. Я изучил твой профиль и готов составить план питания. Хочешь, я рассчитаю твои КБЖУ или составлю меню на завтра?'
    });
  }

  // СБОР ПОЛНОГО ДОСЬЕ
  Future<void> _loadFullUserContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final d = doc.data()!;
        
        // Формируем подробный контекст
        // Если каких-то полей нет, ставим прочерк или дефолт
        _fullUserContext = """
          Имя: ${d['name'] ?? 'Не указано'},
          Пол: ${d['gender'] == 'male' ? 'Мужчина' : 'Женщина'},
          Возраст: ${d['age'] ?? 25} лет,
          Вес: ${d['weight'] ?? 70} кг,
          Рост: ${d['height'] ?? 175} см,
          Процент жира: ${d['bodyFat'] ?? 20}%,
          Стаж тренировок: ${d['experience'] ?? 'Новичок'},
          Цель: ${d['goal'] ?? 'Улучшение формы (по умолчанию)'}
        """;
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
      _controller.clear();
    });

    try {
      final response = await AIService().sendChatMessage(text, _fullUserContext);
      if (mounted) {
        setState(() {
          _messages.add({'role': 'ai', 'text': response});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({'role': 'ai', 'text': 'Ошибка связи. Попробуй позже.'});
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text("Личный Диетолог"),
        backgroundColor: const Color(0xFF1C1C1E),
        leading: const BackButton(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    // Ограничение ширины сообщения (80% экрана)
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFFCCFF00) : const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
                        bottomRight: isUser ? Radius.zero : const Radius.circular(16),
                      ),
                    ),
                    // Используем обычный Text, он сам переносит строки (multiline)
                    child: Text(
                      msg['text']!,
                      style: TextStyle(
                        color: isUser ? Colors.black : Colors.white,
                        fontSize: 15,
                        height: 1.4, // Межстрочный интервал для читаемости меню
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Индикатор загрузки
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text("Диетолог составляет ответ...", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            
          // Поле ввода
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1C1C1E),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    // Разрешаем многострочный ввод для пользователя тоже
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Напиши мне рацион на завтра...",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0F0F0F),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    // Отправка по кнопке на клавиатуре (только если 1 строка, иначе Enter делает перенос)
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xFFCCFF00),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}