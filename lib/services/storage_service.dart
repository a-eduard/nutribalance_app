import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Загружает файл аватара в папку avatars/{userId}
  /// Возвращает URL для скачивания
  Future<String?> uploadUserAvatar(File file, String userId) async {
    try {
      // Ссылка на путь: avatars/uid.jpg
      // Перезаписываем старый файл, чтобы не плодить мусор
      final ref = _storage.ref().child('avatars').child('$userId.jpg');
      
      // Загрузка
      final task = await ref.putFile(file);
      
      // Получение ссылки
      if (task.state == TaskState.success) {
        return await ref.getDownloadURL();
      }
      return null;
    } catch (e) {
      debugPrint("Storage Upload Error: $e");
      return null;
    }
  }
}