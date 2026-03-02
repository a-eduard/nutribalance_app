import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/ai_service.dart';
import '../services/database_service.dart';

class AIChatScreen extends StatefulWidget {
  final String botType;
  const AIChatScreen({super.key, required this.botType});
  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _savedMessageIds = {}; 
  bool _isTyping = false; 
  String _fullUserContext = "";
  File? _selectedImage; 

  Color get themeColor {
    if (widget.botType == 'trainer') return const Color(0xFF9CD600);
    if (widget.botType == 'coach_mentor') return const Color(0xFF8B5CF6);
    return const Color(0xFF00E5FF);
  }
  
  String get botTitle {
    if (widget.botType == 'trainer') return 'ИИ-Тренер';
    if (widget.botType == 'coach_mentor') return 'ИИ-Ментор PRO';
    return 'ИИ-Нутрициолог';
  }

  @override
  void initState() {
    super.initState();
    _initChatAndContext();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChatAndContext() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final d = doc.data()!;
        setState(() {
          _fullUserContext = "Пол: ${d['gender'] ?? 'не указано'}, Возраст: ${d['age'] ?? 'не указано'}, Вес: ${d['weight'] ?? 'не указано'}кг, Рост: ${d['height'] ?? 'не указано'}см, Цель: ${d['goal'] ?? 'не указано'}, Активность: ${d['activityLevel'] ?? 'не указано'}.";
        });
      }
      
      final historyCheck = await FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats_${widget.botType}').limit(1).get();
      if (historyCheck.docs.isEmpty) {
        String welcome = "Здравствуйте! Я ваш ИИ-Диетолог. 🍏 Пришли мне фото еды, и я посчитаю калории!";
        if (widget.botType == 'trainer') {
          welcome = "Привет! Я твой ИИ-Тренер. 💪 Какая у тебя цель?";
        } else if (widget.botType == 'coach_mentor') {
          welcome = "Приветствую, коллега! 🧠 Я ИИ-Ментор по биомеханике, медицине и тренировкам. Какой сложный случай клиента разберем сегодня?";
        }
        await DatabaseService().saveBotChatMessage(widget.botType, welcome, 'ai');
      }
    } catch (e) {
      debugPrint("Ошибка инициализации: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      if (pickedFile != null) setState(() => _selectedImage = File(pickedFile.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка выбора фото: $e")));
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.camera_alt, color: Colors.white), title: const Text('Сделать фото', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); }),
            ListTile(leading: const Icon(Icons.photo_library, color: Colors.white), title: const Text('Выбрать из галереи', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
          ],
        ),
      ),
    );
  }

  void _showLongPressMenu(String docId, String text, bool isUser) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.copy, color: Colors.white), title: const Text('Копировать текст', style: TextStyle(color: Colors.white)), onTap: () { Clipboard.setData(ClipboardData(text: text)); Navigator.pop(ctx); }),
            if (isUser) ListTile(leading: const Icon(Icons.edit, color: Colors.white), title: const Text('Редактировать', style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(ctx); _controller.text = text; }),
            ListTile(leading: const Icon(Icons.delete, color: Colors.redAccent), title: const Text('Удалить сообщение', style: TextStyle(color: Colors.redAccent)), onTap: () async { Navigator.pop(ctx); final uid = FirebaseAuth.instance.currentUser?.uid; if (uid != null) await FirebaseFirestore.instance.collection('users').doc(uid).collection('ai_chats_${widget.botType}').doc(docId).delete(); }),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImage == null) return;
    final File? imageToSend = _selectedImage;
    setState(() { _controller.clear(); _selectedImage = null; _isTyping = true; });

    try {
      String? imageUrl;
      if (imageToSend != null) imageUrl = await DatabaseService().uploadChatImage(imageToSend, 'ai_chat_${widget.botType}');
      await DatabaseService().saveBotChatMessage(widget.botType, text, 'user', imageUrl: imageUrl);
      String aiResponse = "";
      if (imageUrl != null && widget.botType == 'dietitian') aiResponse = await AIService().sendMultimodalMessage(userMessage: text, imageUrl: imageUrl, userContext: _fullUserContext);
      else {
        final history = await DatabaseService().getChatHistoryForAI(widget.botType);
        aiResponse = await AIService().sendChatMessage(botType: widget.botType, userMessage: text, userContext: _fullUserContext, chatHistory: history);
      }
      await DatabaseService().saveBotChatMessage(widget.botType, aiResponse, 'ai');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка ИИ: $e")));
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Map<String, dynamic>? _tryParseJson(String text) {
    try {
      final exp = RegExp(r"```json\s*([\s\S]*?)\s*```");
      final match = exp.firstMatch(text);
      if (match != null) {
        final jsonStr = match.group(1);
        if (jsonStr != null) return jsonDecode(jsonStr);
      } else return jsonDecode(text);
    } catch (_) {}
    return null;
  }

  String _cleanText(String text, Map<String, dynamic>? jsonData) {
    if (jsonData != null && jsonData.containsKey('coach_message')) return jsonData['coach_message'].toString();
    return text.replaceAll(RegExp(r"```json\s*([\s\S]*?)\s*```"), "").trim();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        image: DecorationImage(
          image: const AssetImage('assets/images/app_bg_silhouette.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withValues(alpha: 0.8), 
            BlendMode.darken,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent, 
        appBar: AppBar(
          title: Text(botTitle, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), 
          backgroundColor: Colors.transparent, 
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: DatabaseService().getBotChatMessages(widget.botType),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: themeColor));
                  final docs = snapshot.data?.docs ?? [];
                  return ListView.builder(
                    controller: _scrollController, reverse: true, padding: const EdgeInsets.all(16), itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isUser = data['role'] == 'user';
                      final rawText = data['text'] ?? '';
                      final imageUrl = data['imageUrl'] as String?;
                      final jsonData = isUser ? null : _tryParseJson(rawText);
                      final displayText = isUser ? rawText : _cleanText(rawText, jsonData);

                      return Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () => _showLongPressMenu(doc.id, displayText, isUser),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6), 
                                padding: const EdgeInsets.all(14), 
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                                decoration: BoxDecoration(
                                  color: isUser ? themeColor.withValues(alpha: 0.1) : const Color(0xFF1E1E1E).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isUser ? themeColor.withValues(alpha: 0.3) : themeColor.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    if (imageUrl != null) 
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0), 
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12), 
                                          child: CachedNetworkImage(imageUrl: imageUrl, width: 200, fit: BoxFit.cover, placeholder: (c, u) => const CircularProgressIndicator())
                                        )
                                      ),
                                    if (displayText.isNotEmpty) 
                                      Text(
                                        displayText, 
                                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (jsonData != null) _buildSaveCard(jsonData, doc.id),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_isTyping) Padding(padding: const EdgeInsets.all(8.0), child: Text("Бот печатает...", style: TextStyle(color: themeColor, fontSize: 12))),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12), 
      color: const Color(0xFF1C1C1E).withValues(alpha: 0.85),
      child: SafeArea(
        child: Column(
          children: [
            if (_selectedImage != null) Stack(children: [ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_selectedImage!, height: 80, width: 80, fit: BoxFit.cover)), Positioned(right: 0, child: GestureDetector(onTap: () => setState(() => _selectedImage = null), child: const CircleAvatar(radius: 10, child: Icon(Icons.close, size: 12))))]),
            Row(children: [
              IconButton(icon: const Icon(Icons.attach_file, color: Colors.grey), onPressed: _showAttachmentOptions),
              Expanded(child: TextField(controller: _controller, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Сообщение...", border: InputBorder.none))),
              CircleAvatar(
                backgroundColor: themeColor.withValues(alpha: 0.1), 
                child: IconButton(icon: Icon(Icons.send, color: themeColor), onPressed: _sendMessage)
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveCard(Map<String, dynamic> jsonData, String msgId) {
    final bool isSaved = _savedMessageIds.contains(msgId);
    final String type = jsonData['type'] ?? '';
    
    // БЛОК 3: Обработка специального типа needs_plan
    if (type == 'needs_plan') {
      final draft = jsonData['draft_meal'] ?? {};
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
                child: Text("Чтобы сохранить ${draft['meal_name'] ?? 'блюдо'} (${draft['calories'] ?? 0} ккал), нужно рассчитать дневную норму.", style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              ),
            ),
            if (!isSaved)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      onPressed: () async {
                        await DatabaseService().saveMealDraft(draft);
                        setState(() => _savedMessageIds.add(msgId));
                      },
                      child: const Text("ПОЗЖЕ", style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor, 
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      onPressed: () {
                        _controller.text = "Помоги составить план питания и рассчитай норму КБЖУ";
                        _sendMessage();
                        setState(() => _savedMessageIds.add(msgId)); 
                      },
                      child: const Text("СОСТАВИТЬ ПЛАН", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              )
            else
              const Center(child: Text("ОБРАБОТАНО", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.0)))
          ],
        ),
      );
    }

    // СТАНДАРТНАЯ ОТРИСОВКА КАРТОЧЕК
    String title = "Программа готова";
    String description = "";
    String buttonText = "СОХРАНИТЬ В БАЗУ";

    if (type == 'set_goal') {
      title = "🎯 Ваша новая цель КБЖУ";
      description = "${jsonData['calories']} ккал\nБелки: ${jsonData['protein']}г | Жиры: ${jsonData['fat']}г | Углеводы: ${jsonData['carbs']}г";
      buttonText = "ОБНОВИТЬ ЦЕЛЬ";
    } else if (type == 'log_meal') {
      title = "🍽 ${jsonData['meal_name'] ?? 'Прием пищи'}";
      description = "${jsonData['calories']} ккал\nБ: ${jsonData['protein']}г | Ж: ${jsonData['fat']}г | У: ${jsonData['carbs']}г";
      buttonText = "СОХРАНИТЬ В ДНЕВНИК"; 
    } else if (type == 'save_food') {
      title = "📝 Запомнить продукт";
      description = "${jsonData['name']}\n${jsonData['calories']} ккал | Б: ${jsonData['protein']}г | Ж: ${jsonData['fat']}г | У: ${jsonData['carbs']}г";
      buttonText = "СОХРАНИТЬ В БАЗУ"; 
    } else if (type == 'workout' || jsonData['days'] != null) {
      title = jsonData['program_title'] ?? jsonData['program_name'] ?? "Программа тренировок";
      buttonText = "СОХРАНИТЬ ПРОГРАММУ";
    } else {
      title = jsonData['title'] ?? "План питания";
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.9), 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: isSaved ? Colors.grey.withValues(alpha: 0.2) : themeColor.withValues(alpha: 0.3))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center)),
          
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
              child: Center(
                child: Text(description, style: TextStyle(color: themeColor, fontSize: 14, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
              ),
            ),

          if (jsonData['days'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (jsonData['days'] as List<dynamic>).map((day) {
                    final dayName = day['day_name'] ?? 'Тренировка';
                    final exercises = day['exercises'] as List<dynamic>? ?? [];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("📅 $dayName", style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          ...exercises.map((ex) => Text("• ${ex['name']} (${ex['sets']} × ${ex['reps']})", style: const TextStyle(color: Colors.white70, fontSize: 13))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 16),
          
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: isSaved ? Colors.transparent : themeColor.withValues(alpha: 0.05),
                side: BorderSide(color: isSaved ? Colors.grey.withValues(alpha: 0.3) : themeColor.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSaved ? null : () async {
                if (type == 'set_goal') {
                  await DatabaseService().saveNutritionGoal(jsonData);
                } else if (type == 'log_meal') {
                  await DatabaseService().logMeal(jsonData);
                } else if (type == 'save_food') {
                  await DatabaseService().saveCustomFood(jsonData);
                } else if (type == 'workout' || jsonData['days'] != null) {
                  await DatabaseService().saveAIWorkoutProgram(jsonData);
                } else {
                  await DatabaseService().saveAIDietPlan(jsonData);
                }
                setState(() => _savedMessageIds.add(msgId));
              },
              child: Text(
                isSaved ? "СОХРАНЕНО" : buttonText, 
                style: TextStyle(color: isSaved ? Colors.grey : themeColor, fontWeight: FontWeight.bold, letterSpacing: 1.0)
              ),
            ),
          ),
        ],
      ),
    );
  }
}