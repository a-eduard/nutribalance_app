import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class CoachProfileSettings extends StatefulWidget {
  const CoachProfileSettings({super.key});

  @override
  State<CoachProfileSettings> createState() => _CoachProfileSettingsState();
}

class _CoachProfileSettingsState extends State<CoachProfileSettings> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _specializationController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  bool _isFetching = true;
  bool _isLoading = false;

  // ПЕРЕМЕННЫЕ ДЛЯ BASE64
  String? _base64Image;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCoachData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _bioController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadCoachData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('coaches').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _specializationController.text = data['specialization'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _priceController.text = data['price']?.toString() ?? '';
          _base64Image = data['photoUrl'] as String?; // Загружаем Base64 строку
        });
      }
    } catch (e) {
      print("Ошибка при загрузке профиля тренера: $e");
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  // ВЫБОР И ЖЕСТКОЕ СЖАТИЕ ФОТО
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 200,
        maxHeight: 200,
        imageQuality: 20, // Критично для Firestore
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _base64Image = base64Encode(bytes); // Кодируем в Base64
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ошибка выбора фото: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _saveProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('coaches').doc(uid).set({
        'name': _nameController.text.trim(),
        'specialization': _specializationController.text.trim(),
        'bio': _bioController.text.trim(),
        'price': _priceController.text.trim(),
        'photoUrl': _base64Image ?? '', // Сохраняем Base64 строку
        'rating': 5.0,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Профиль обновлен в Маркетплейсе!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: Color(0xFFCCFF00),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка сохранения: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFCCFF00)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFCCFF00).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCFF00).withOpacity(0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFFCCFF00), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Заполните данные, чтобы клиенты могли найти вас в Маркетплейсе.",
                    style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // АВАТАРКА БАЗЫ 64
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: const Color(0xFF1C1C1E),
                    backgroundImage: (_base64Image != null && _base64Image!.isNotEmpty)
                        ? MemoryImage(base64Decode(_base64Image!))
                        : null,
                    child: (_base64Image == null || _base64Image!.isEmpty)
                        ? const Icon(Icons.person, size: 60, color: Colors.grey)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCCFF00),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: const Icon(Icons.camera_alt, size: 20, color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          _buildLabel("ИМЯ / ФАМИЛИЯ"),
          _buildInputField(_nameController, "Как к вам обращаться?", Icons.person),
          const SizedBox(height: 20),

          _buildLabel("СПЕЦИАЛИЗАЦИЯ"),
          _buildInputField(_specializationController, "Например: Набор массы, Сушка", Icons.fitness_center),
          const SizedBox(height: 20),

          _buildLabel("О СЕБЕ (ОПЫТ, ДОСТИЖЕНИЯ)"),
          _buildInputField(_bioController, "Расскажите клиентам о своем опыте...", null, maxLines: 3),
          const SizedBox(height: 20),

          _buildLabel("СТОИМОСТЬ УСЛУГ"),
          _buildInputField(_priceController, "Например: 5000 руб/мес", Icons.payments),
          
          const SizedBox(height: 40),

          // КНОПКА СОХРАНИТЬ
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFCCFF00).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                )
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCCFF00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                : const Text("СОХРАНИТЬ В МАРКЕТПЛЕЙС", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.0)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String hint, IconData? icon, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: const Color(0xFFCCFF00),
        decoration: InputDecoration(
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey, size: 20) : null,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: maxLines > 1 ? 16 : 18),
        ),
      ),
    );
  }
}