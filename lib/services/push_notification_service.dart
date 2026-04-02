import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static String? currentActiveChatId;

  Future<void> initialize() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('FCM: Доступ разрешен');
      
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings, 
        iOS: DarwinInitializationSettings()
      );
      
      // ФИКС: Используем именованный параметр
      await _localNotifications.initialize(settings: initSettings);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', 
        'High Importance Notifications', 
        description: 'Важные уведомления от тренера',
        importance: Importance.max,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      String? token = await _fcm.getToken();
      if (token != null) _saveTokenToDatabase(token);
      
      _fcm.onTokenRefresh.listen(_saveTokenToDatabase);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final senderId = message.data['senderId']; 
        
        if (currentUserId != null && senderId == currentUserId) return;

        String? incomingChatId = message.data['chatId'] ?? message.data['botType'];
        
        if (incomingChatId == null && senderId != null && currentUserId != null) {
          List<String> ids = [currentUserId, senderId.toString()];
          ids.sort();
          incomingChatId = ids.join('_');
        }

        if (incomingChatId != null && incomingChatId == currentActiveChatId) {
          debugPrint("Пуш заглушен: пользователь уже находится в чате $incomingChatId");
          return;
        }

        if (notification != null && android != null) {
          // ФИКС: Используем именованные параметры
          _localNotifications.show(
            id: notification.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.max,
                priority: Priority.high,
                color: const Color(0xFFB76E79), 
              ),
            ),
          );
        }
      });
    }
  }

  Future<void> clearAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<void> forceUpdateToken() async {
    String? token = await _fcm.getToken();
    if (token != null) {
      await _saveTokenToDatabase(token);
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token, 'lastTokenUpdate': FieldValue.serverTimestamp()}, 
        SetOptions(merge: true)
      );
    }
  }

  Future<void> clearToken() async {
    String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': FieldValue.delete(),
        });
      } catch (e) {
        debugPrint("Ошибка при удалении токена FCM: $e");
      }
    }
  }
}