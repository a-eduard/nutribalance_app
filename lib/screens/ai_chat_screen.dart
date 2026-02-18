import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart'; // Локализация
import '../services/ai_service.dart';
import '../services/database_service.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false; // ИНДИКАТОР ЗАГРУЗКИ
  String _fullUserContext = "";

  @override
  void initState() {
    super.initState();
    _loadFullUserContext();
  }

  Future<void> _loadFullUserContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final d = doc.data()!;
        _fullUserContext = """
          Имя: ${d['name']}, Пол: ${d['gender']}, Возраст: ${d['age']}, 
          Вес: ${d['weight']}кг, Рост: ${d['height']}см, Жир: ${d['bodyFat']}%, 
          Цель: ${d['goal'] ?? 'Быть в форме'}
        """;
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() => _isTyping = true); // ВКЛЮЧАЕМ ЛОАДЕР

    try {
      await DatabaseService().saveChatMessage(text, 'user');
      _scrollToBottom();

      final responseMap = await AIService().chatWithDietologist(
        userMessage: text, 
        userContext: _fullUserContext
      );
      
      final String aiText = responseMap['text'] ?? "Ошибка: Пустой ответ";
      final bool isPlan = responseMap['is_plan'] == true;

      if (isPlan && responseMap['nutrition'] != null) {
        await DatabaseService().saveNutritionPlan(responseMap['nutrition']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Рацион сохранен в Профиль!"), backgroundColor: Color(0xFF9CD600))
          );
        }
      }

      await DatabaseService().saveChatMessage(aiText, 'ai');
      _scrollToBottom();

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка: $e")));
    } finally {
      if (mounted) setState(() => _isTyping = false); // ВЫКЛЮЧАЕМ ЛОАДЕР
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Text("ai_chat".tr()), // Локализация
        backgroundColor: const Color(0xFF1C1C1E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => DatabaseService().clearChatHistory(),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: DatabaseService().getChatMessages(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF9CD600)));
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30.0),
                      child: Text(
                        "Я изучил твой профиль.\nПопроси меня составить рацион.", 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isUser = data['role'] == 'user';
                    final text = data['text'] ?? '';

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF9CD600) : const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                            bottomRight: isUser ? Radius.zero : const Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          text, 
                          style: TextStyle(
                            color: isUser ? Colors.black : Colors.white, 
                            fontSize: 15,
                            height: 1.3 
                          )
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          if (_isTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: const Text("Печатает...", style: TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontStyle: FontStyle.italic)),
            ),

          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF1C1C1E),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Сообщение...",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0F0F0F),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // КНОПКА С ЛОАДЕРОМ
                CircleAvatar(
                  backgroundColor: const Color(0xFF9CD600),
                  child: _isTyping 
                    ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : IconButton(
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