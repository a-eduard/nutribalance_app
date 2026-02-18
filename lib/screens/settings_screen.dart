import 'dart:convert'; 
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/base_background.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _expController = TextEditingController();
  final _priceController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  
  bool _isLoading = false;
  String _selectedRole = 'user'; 
  
  String? _currentPhotoUrl;
  File? _newPhotoFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _bioController.text = data['bio'] ?? '';
          _selectedRole = data['activeRole'] ?? 'user';
          _expController.text = data['experience'] ?? '';
          _priceController.text = data['price']?.toString() ?? '';
          _ageController.text = data['age']?.toString() ?? '';
          _heightController.text = data['height']?.toString() ?? '';
          _weightController.text = data['weight']?.toString() ?? '';
          _currentPhotoUrl = data['photoUrl'];
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _newPhotoFile = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true); // ВКЛЮЧАЕМ ЛОАДЕР
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    if (uid == null) return;

    try {
      String? photoUrlToSave = _currentPhotoUrl;

      if (_newPhotoFile != null) {
        final url = await StorageService().uploadUserAvatar(_newPhotoFile!, uid);
        if (url != null) photoUrlToSave = url;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'photoUrl': photoUrlToSave,
        'activeRole': _selectedRole,
        if (_selectedRole == 'coach') 'experience': _expController.text.trim(),
        if (_selectedRole == 'coach') 'price': int.tryParse(_priceController.text) ?? 0,
        if (_selectedRole == 'user') 'age': int.tryParse(_ageController.text) ?? 0,
        if (_selectedRole == 'user') 'height': int.tryParse(_heightController.text) ?? 0,
        if (_selectedRole == 'user') 'weight': double.tryParse(_weightController.text.replaceAll(',', '.')) ?? 0.0,
      });

      if (_selectedRole == 'user' && _weightController.text.isNotEmpty) {
        double? newWeight = double.tryParse(_weightController.text.replaceAll(',', '.'));
        if (newWeight != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).collection('weight_history').add({'weight': newWeight, 'date': FieldValue.serverTimestamp()});
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('data_saved'.tr()), backgroundColor: const Color(0xFF9CD600)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${'error_msg'.tr()}: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false); // ВЫКЛЮЧАЕМ ЛОАДЕР
    }
  }

  Widget _buildAvatarSection() {
    ImageProvider? imageProvider;
    
    if (_newPhotoFile != null) {
      imageProvider = FileImage(_newPhotoFile!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      if (_currentPhotoUrl!.startsWith('http')) {
        imageProvider = NetworkImage(_currentPhotoUrl!);
      } else {
        try { imageProvider = MemoryImage(base64Decode(_currentPhotoUrl!)); } catch (_) {}
      }
    }

    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Stack(
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[800],
              backgroundImage: imageProvider,
              child: imageProvider == null 
                  ? const Icon(Icons.person, size: 50, color: Colors.white) 
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF9CD600),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt, size: 16, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleButton(String title, String role) {
    final isActive = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: isActive ? const Color(0xFF9CD600) : Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: isActive ? const Color(0xFF9CD600) : Colors.grey.withOpacity(0.3))),
          child: Text(title, style: TextStyle(color: isActive ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label, {int maxLines = 1, bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: Colors.black.withOpacity(0.5), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('settings'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatarSection(),
                const SizedBox(height: 32),
                
                Row(
                  children: [
                    _buildRoleButton('role_user'.tr(), "user"),
                    const SizedBox(width: 12),
                    _buildRoleButton('role_coach'.tr(), "coach"),
                  ],
                ),
                const SizedBox(height: 32),

                _buildInputField(_nameController, 'name'.tr()),
                _buildInputField(_bioController, 'about_me'.tr(), maxLines: 3),

                if (_selectedRole == 'coach') ...[
                  Padding(padding: const EdgeInsets.only(bottom: 12, top: 8), child: Text('pro_data'.tr(), style: const TextStyle(color: Color(0xFF9CD600), fontSize: 12, fontWeight: FontWeight.bold))),
                  _buildInputField(_expController, 'experience'.tr()),
                  _buildInputField(_priceController, 'price_services'.tr(), isNumber: true),
                ],

                if (_selectedRole == 'user') ...[
                  _buildInputField(_ageController, 'age_years'.tr(), isNumber: true),
                  _buildInputField(_heightController, 'height_cm'.tr(), isNumber: true),
                  _buildInputField(_weightController, 'weight_kg'.tr(), isNumber: true),
                ],

                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.language, color: Colors.white),
                    title: Text('language'.tr(), style: const TextStyle(color: Colors.white)),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        dropdownColor: const Color(0xFF2C2C2E),
                        value: context.locale.languageCode,
                        style: const TextStyle(color: Color(0xFF9CD600), fontWeight: FontWeight.bold),
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF9CD600)),
                        items: const [DropdownMenuItem(value: 'ru', child: Text('Русский')), DropdownMenuItem(value: 'en', child: Text('English'))],
                        onChanged: (String? newLang) {
                          if (newLang != null) context.setLocale(Locale(newLang));
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // КНОПКА СОХРАНИТЬ С ЛОАДЕРОМ
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9CD600), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _isLoading ? null : _saveChanges, // БЛОКИРОВКА ПРИ ЗАГРУЗКЕ
                    child: _isLoading 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                      : Text('save_changes'.tr(), style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                  ),
                ),
                const SizedBox(height: 32),
                
                ListTile(
                  contentPadding: EdgeInsets.zero, leading: const Icon(Icons.logout, color: Colors.redAccent), title: Text('logout_account'.tr(), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}