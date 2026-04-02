import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import '../../screens/ai_chat_screen.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FastFoodScannerSheet extends StatefulWidget {
  const FastFoodScannerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Убрали белый фон для плавающего эффекта
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.1), // Легкое затемнение фона экрана
      builder: (context) => const FastFoodScannerSheet(),
    );
  }

  @override
  State<FastFoodScannerSheet> createState() => _FastFoodScannerSheetState();
}

class _FastFoodScannerSheetState extends State<FastFoodScannerSheet> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  bool _isProcessing = false;
  Map<String, dynamic>? _resultData;
  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
      if (pickedFile != null) {
        setState(() { _image = File(pickedFile.path); _errorMessage = null; });
        _analyzeImage();
      }
    } catch (e) {
      setState(() => _errorMessage = "Ошибка доступа к камере/галерее");
    }
  }

  Future<void> _analyzeImage() async {
    setState(() => _isProcessing = true);
    try {
      final bytes = await _image!.readAsBytes();
      final base64Image = base64Encode(bytes);
      final response = await AIService().sendMultimodalMessage(
        userMessage: "Проанализируй это блюдо. Верни СТРОГО JSON формат (action_type: log_food), разбив на ингредиенты.",
        base64Image: base64Image,
        userContext: "", 
      );
      final parsedJson = _extractJson(response);
      if (parsedJson != null && parsedJson['items'] != null) {
        setState(() => _resultData = parsedJson);
      } else {
        setState(() => _errorMessage = "Ева не смогла распознать еду. Попробуй сделать фото четче.");
      }
    } catch (e) {
      setState(() => _errorMessage = "Ошибка связи с сервером. Проверь интернет.");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Map<String, dynamic>? _extractJson(String text) {
    try {
      final String tick = String.fromCharCode(96);
      final String tripleTick = tick + tick + tick;
      final RegExp jsonRegExp = RegExp(tripleTick + r'(?:json)?\s*(\{.*?\})\s*' + tripleTick, dotAll: true);
      final match = jsonRegExp.firstMatch(text);
      if (match != null) return jsonDecode(match.group(1)!);
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) return jsonDecode(text.substring(start, end + 1));
    } catch (e) { debugPrint("JSON Parse error: $e"); }
    return null;
  }

  Future<void> _saveToDiary() async {
    if (_resultData == null) return;
    setState(() => _isProcessing = true);
    try {
      String? uploadedImageUrl;
      
      // === ЗАГРУЖАЕМ ФОТО НА СЕРВЕР ПЕРЕД СОХРАНЕНИЕМ ===
      if (_image != null) {
        try {
          final uid = DatabaseService().currentUser?.uid ?? 'unknown';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final ref = FirebaseStorage.instance.ref().child('meals/$uid/fast_scan_$timestamp.jpg');
          
          await ref.putFile(_image!); // Грузим в Storage
          uploadedImageUrl = await ref.getDownloadURL(); // Получаем ссылку
        } catch (e) {
          debugPrint("Ошибка загрузки фото: $e");
        }
      }

      // Передаем URL в наш новый параметр extraImageUrl
      await DatabaseService().logMeal(_resultData!, extraImageUrl: uploadedImageUrl);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Блюдо добавлено! ✨', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: _accentColor));
      }
    } catch (e) {
      setState(() { _errorMessage = "Не удалось сохранить в базу."; _isProcessing = false; });
    }
  }

  // === ЛОГИКА РЕДАКТИРОВАНИЯ И ПЕРЕСЧЕТА МАКРОСОВ ===
  void _editMacro(String macroType, int newValue, int oldCals, int oldP, int oldF, int oldC) {
    if (_resultData == null) return;
    List<dynamic> items = _resultData!['items'] ?? [];
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
        if (macroType == 'protein') {
          diff = newValue - oldP;
          calDiff = diff * 4;
        } else if (macroType == 'fat') {
          diff = newValue - oldF;
          calDiff = diff * 9;
        } else if (macroType == 'carbs') {
          diff = newValue - oldC;
          calDiff = diff * 4;
        }

        // Применяем разницу к первому ингредиенту, чтобы сохранить структуру JSON
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
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accentColor, width: 2)),
            suffixText: macroType == 'calories' ? 'ккал' : 'г',
          ),
          cursorColor: _accentColor,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentColor, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
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

  @override
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16), // Отступ от краев экрана
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: _isProcessing ? null : Colors.white,
        gradient: _isProcessing 
            ? LinearGradient(colors: [Colors.white, const Color(0xFFB76E79).withValues(alpha: 0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight) 
            : null, // Нежный розовый градиент при анализе
        borderRadius: BorderRadius.circular(32),
        border: _isProcessing ? Border.all(color: const Color(0xFFB76E79).withValues(alpha: 0.2), width: 1.5) : null,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(10))),
          if (_isProcessing) _buildProcessingState()
          else if (_resultData != null) _buildResultState()
          else _buildSelectionState(),
        ],
      ),
    );
  }

  Widget _buildSelectionState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_errorMessage != null) Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Text(_errorMessage!, style: const TextStyle(color: _accentColor, fontWeight: FontWeight.bold))),
        _buildMenuButton(Icons.camera_alt_outlined, "Камера", () => _pickImage(ImageSource.camera)),
        const Divider(height: 1, color: Color(0xFFF2F2F7)),
        _buildMenuButton(Icons.image_outlined, "Фотогалерея", () => _pickImage(ImageSource.gallery)),
        const Divider(height: 1, color: Color(0xFFF2F2F7)),
        _buildMenuButton(Icons.edit_note_outlined, "Записать вручную", () {
          Navigator.pop(context); 
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
        }),
      ],
    );
  }

  Widget _buildMenuButton(IconData icon, String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: _accentColor, size: 28),
            const SizedBox(width: 16),
            Text(text, style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60.0),
      child: FadeTransition(
        opacity: _pulseAnimation,
        child: const Column(
          children: [
            Icon(Icons.psychology_outlined, color: _accentColor, size: 64),
            SizedBox(height: 24),
            Text("Ева анализирует блюдо ✨", textAlign: TextAlign.center, style: TextStyle(color: _accentColor, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroEditBtn(String label, int value, String type, int tc, int tp, int tf, int tcarb, Color color) {
    return GestureDetector(
      onTap: () => _showEditDialog(label, value, type, tc, tp, tf, tcarb),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(color: _textColor, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Icon(Icons.edit_outlined, size: 14, color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text("${value}г", style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w900)),
          ]
        )
      )
    );
  }

  Widget _buildResultState() {
    final List<dynamic> items = _resultData!['items'] ?? [];
    int totalCals = 0, totalP = 0, totalF = 0, totalC = 0;
    
    for (var item in items) {
      totalCals += (item['calories'] as num?)?.toInt() ?? 0;
      totalP += (item['protein'] as num?)?.toInt() ?? 0;
      totalF += (item['fat'] as num?)?.toInt() ?? 0;
      totalC += (item['carbs'] as num?)?.toInt() ?? 0;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_image != null) ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_image!, width: 80, height: 80, fit: BoxFit.cover)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    const Text("Распознано:", style: TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.bold)), 
                    GestureDetector(
                      onTap: () => _showEditDialog('Калории', totalCals, 'calories', totalCals, totalP, totalF, totalC),
                      child: Row(
                        children: [
                          Text("$totalCals ккал", style: const TextStyle(color: _accentColor, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                          const SizedBox(width: 8),
                          const Icon(Icons.edit_outlined, size: 20, color: _subTextColor),
                        ],
                      ),
                    )
                  ]
                )
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildMacroEditBtn("Белки", totalP, "protein", totalCals, totalP, totalF, totalC, const Color(0xFFD49A89))),
              const SizedBox(width: 8),
              Expanded(child: _buildMacroEditBtn("Жиры", totalF, "fat", totalCals, totalP, totalF, totalC, const Color(0xFFE5C158))),
              const SizedBox(width: 8),
              Expanded(child: _buildMacroEditBtn("Углеводы", totalC, "carbs", totalCals, totalP, totalF, totalC, const Color(0xFF89CFF0))),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0), 
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                  children: [
                    Expanded(child: Text(item['meal_name'] ?? 'Продукт', style: const TextStyle(color: _textColor, fontWeight: FontWeight.w700))), 
                    Text("${item['weight_g']}г / ${item['calories']} ккал", style: const TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))
                  ]
                )
              )).toList()
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 56, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0), onPressed: _saveToDiary, child: const Text("ДОБАВИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)))),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: () => setState(() { _resultData = null; _image = null; }), child: const Text("Переснять фото", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))))
        ],
      ),
    );
  }
}