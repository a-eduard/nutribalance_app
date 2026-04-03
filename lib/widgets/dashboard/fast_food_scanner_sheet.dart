import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/ai_service.dart';
import '../../services/database_service.dart';
import '../../screens/ai_chat_screen.dart';

class FastFoodScannerSheet extends StatefulWidget {
  const FastFoodScannerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (context) => const FastFoodScannerSheet(),
    );
  }

  @override
  State<FastFoodScannerSheet> createState() => _FastFoodScannerSheetState();
}

class _FastFoodScannerSheetState extends State<FastFoodScannerSheet> {
  final ImagePicker _picker = ImagePicker();
  File? _image;
  Uint8List? _imageBytes;
  
  bool _isProcessing = false;
  
  Map<String, dynamic>? _resultData;
  String? _errorMessage;

  static const Color _accentColor = Color(0xFFB76E79);
  static const Color _textColor = Color(0xFF2D2D2D);
  static const Color _subTextColor = Color(0xFF8E8E93);

  // === НАШЕ БЕЗОПАСНОЕ УВЕДОМЛЕНИЕ ===
  void _showTopSnackBar(String message, ScaffoldMessengerState messenger, {bool isError = false}) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message, 
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        backgroundColor: isError ? Colors.redAccent : _accentColor,
        behavior: SnackBarBehavior.floating,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24), // Безопасный отступ
        duration: const Duration(seconds: 2),
      )
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source, imageQuality: 30, maxWidth: 512, maxHeight: 512);
      if (pickedFile != null) {
        setState(() { _image = File(pickedFile.path); _errorMessage = null; });
        _analyzeImage();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = "Ошибка доступа к камере/галерее");
      final messenger = ScaffoldMessenger.of(context);
      _showTopSnackBar("Ошибка доступа к камере", messenger, isError: true);
    }
  }

  Future<void> _analyzeImage() async {
    _imageBytes = await _image!.readAsBytes();
    final base64Image = base64Encode(_imageBytes!);

    if (!mounted) return;
    final overlayNavigator = Navigator.of(context, rootNavigator: true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: _accentColor),
                    SizedBox(height: 16),
                    Text("Ева анализирует блюдо ✨", style: TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.none)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final response = await AIService().sendMultimodalMessage(
        userMessage: "Проанализируй это блюдо. Верни СТРОГО JSON формат (action_type: log_food), разбив на ингредиенты.",
        base64Image: base64Image,
        userContext: "", 
      );
      final parsedJson = _extractJson(response);
      
      if (!mounted) return;
      if (parsedJson != null && parsedJson['items'] != null) {
        setState(() => _resultData = parsedJson);
      } else {
        setState(() => _errorMessage = "Ева не смогла распознать еду. Попробуй сделать фото четче.");
        final messenger = ScaffoldMessenger.of(context);
        _showTopSnackBar("Не удалось распознать еду", messenger, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = "Ошибка связи с сервером. Проверь интернет.");
      final messenger = ScaffoldMessenger.of(context);
      _showTopSnackBar("Ошибка связи с сервером", messenger, isError: true);
    } finally {
      overlayNavigator.pop(); 
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
    if (_resultData == null || _isProcessing) return;
    setState(() => _isProcessing = true);

    // Захватываем мессенджер до закрытия шторки
    final messenger = ScaffoldMessenger.of(context);

    // Фоновая отправка в базу
    DatabaseService().logMeal(_resultData!, imageBytes: _imageBytes).catchError((e) {
      debugPrint("Фоновая ошибка сохранения: $e");
    });

    // Мгновенное закрытие и показ уведомления
    if (mounted) {
      Navigator.pop(context);
      _showTopSnackBar("Блюдо добавлено! ✨", messenger);
    }
  }

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
        int diff = 0, calDiff = 0;
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
    final TextEditingController ctrl = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Изменить $label', style: const TextStyle(color: _textColor, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl, keyboardType: TextInputType.number,
          style: const TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900),
          decoration: InputDecoration(focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _accentColor, width: 2)), suffixText: macroType == 'calories' ? 'ккал' : 'г'),
          cursorColor: _accentColor,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена', style: TextStyle(color: _subTextColor, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(10))),
          if (_resultData != null) _buildResultState()
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
      onTap: onTap, borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: _accentColor, size: 28), const SizedBox(width: 16),
            Text(text, style: const TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.w600)),
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text(label, style: const TextStyle(color: _textColor, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)), Icon(Icons.edit_outlined, size: 14, color: color)]),
            const SizedBox(height: 4),
            Text("$valueг", style: const TextStyle(color: _textColor, fontSize: 16, fontWeight: FontWeight.w900)),
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
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_imageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(_imageBytes!, width: 80, height: 80, fit: BoxFit.cover)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    const Text("Распознано:", style: TextStyle(color: _subTextColor, fontSize: 12, fontWeight: FontWeight.bold)), 
                    GestureDetector(
                      onTap: () => _showEditDialog('Калории', totalCals, 'calories', totalCals, totalP, totalF, totalC),
                      child: Row(children: [Text("$totalCals ккал", style: const TextStyle(color: _accentColor, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1.0)), const SizedBox(width: 8), const Icon(Icons.edit_outlined, size: 20, color: _subTextColor)]),
                    )
                  ]
                )
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildMacroEditBtn("Белки", totalP, "protein", totalCals, totalP, totalF, totalC, const Color(0xFFD49A89))), const SizedBox(width: 8),
              Expanded(child: _buildMacroEditBtn("Жиры", totalF, "fat", totalCals, totalP, totalF, totalC, const Color(0xFFE5C158))), const SizedBox(width: 8),
              Expanded(child: _buildMacroEditBtn("Углеводы", totalC, "carbs", totalCals, totalP, totalF, totalC, const Color(0xFF89CFF0))),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFF9F9F9), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(item['meal_name'] ?? 'Продукт', style: const TextStyle(color: _textColor, fontWeight: FontWeight.w700))), Text("${item['weight_g']}г / ${item['calories']} ккал", style: const TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))]))).toList()),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 56, 
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accentColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), elevation: 0), 
              onPressed: _isProcessing ? null : _saveToDiary, 
              child: _isProcessing ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text("ДОБАВИТЬ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))
            )
          ),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: () => setState(() { _resultData = null; _image = null; _imageBytes = null; }), child: const Text("Переснять фото", style: TextStyle(color: _subTextColor, fontWeight: FontWeight.w600))))
        ],
      ),
    );
  }
}