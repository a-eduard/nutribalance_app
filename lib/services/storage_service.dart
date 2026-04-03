import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Загружает файл аватара в папку avatars/{userId}
  /// Возвращает URL для скачивания
  Future<String?> uploadUserAvatar(File imageFile, String uid) async {
    try {
      // ФИКС КЭША: Генерируем уникальное имя файла с помощью timestamp
      final String fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('users/$uid/$fileName');
      
      await ref.putFile(imageFile);
      final downloadUrl = await ref.getDownloadURL();
      
      return downloadUrl;
    } catch (e) {
      print("Ошибка загрузки аватарки: $e");
      return null;
    }
  }
}