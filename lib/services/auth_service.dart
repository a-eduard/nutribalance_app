import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Добавлено для PlatformException
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<dynamic> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on PlatformException catch (e) {
      // QA FIX: Защита для Huawei/устройств без Google Services
      debugPrint("GMS Error: ${e.code}");
      if (e.code == 'network_error') return "Проверьте интернет-соединение";
      return "Сервисы Google недоступны на этом устройстве";
    } catch (e) {
      debugPrint("Error signing in with Google: $e");
      return "Ошибка авторизации. Попробуйте позже";
    }
  }
}