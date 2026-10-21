import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/ai_chat_screen.dart';
import '../screens/p2p_chat_screen.dart';
import 'app_navigator.dart';
import 'local_notification_service.dart';

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService _instance = PushNotificationService._();
  factory PushNotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _localNotifications = LocalNotificationService().flutterLocalNotificationsPlugin;

  static String? currentActiveChatId;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Сообщения и важные уведомления',
    description: 'Новые сообщения в чатах и ответы Евы',
    importance: Importance.max,
  );

  bool _initialized = false;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  FirebaseMessaging? get _fcm {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final fcm = _fcm;
    if (fcm == null) return;

    try {
      final settings = await fcm.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM: уведомления запрещены пользователем');
      }
    } catch (e) {
      debugPrint('FCM permission error: $e');
    }

    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    } catch (e) {
      debugPrint('FCM channel error: $e');
    }

    await forceUpdateToken();
    _tokenSub ??= fcm.onTokenRefresh.listen(_saveTokenToDatabase, onError: (e) => debugPrint('onTokenRefresh: $e'));

    _messageSub ??= FirebaseMessaging.onMessage.listen(_onForegroundMessage, onError: (e) => debugPrint('onMessage: $e'));
    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage, onError: (e) => debugPrint('onMessageOpenedApp: $e'));
    // Нажатие на пуш, показанный как локальное уведомление (приложение было открыто).
    LocalNotificationService.externalTapHandler = (data) => _openFromData(data);

    try {
      final initial = await fcm.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openFromMessage(initial));
      }
    } catch (e) {
      debugPrint('getInitialMessage: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final RemoteNotification? notification = message.notification;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final senderId = message.data['senderId']?.toString();

    if (currentUserId != null && senderId == currentUserId) return;

    String? incomingChatId = message.data['chatId']?.toString() ?? message.data['botType']?.toString();
    if (incomingChatId == null && senderId != null && currentUserId != null) {
      final ids = [currentUserId, senderId]..sort();
      incomingChatId = ids.join('_');
    }

    if (incomingChatId != null && incomingChatId == currentActiveChatId) {
      return; // пользователь уже в этом чате
    }

    if (notification == null) return;
    try {
      final String body = notification.body ?? '';
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: body,
        payload: jsonEncode({...message.data, if (notification.title != null) 'title': notification.title}),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: '@mipmap/launcher_icon',
            importance: Importance.max,
            priority: Priority.high,
            color: const Color(0xFFB76E79),
            // Длинные сообщения целиком видны при разворачивании уведомления.
            styleInformation: BigTextStyleInformation(body, contentTitle: notification.title),
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
      );
    } catch (e) {
      debugPrint('local show error: $e');
    }
  }

  /// Открытие нужного экрана по тапу на пуш.
  void _openFromMessage(RemoteMessage message) {
    _openFromData(message.data, title: message.notification?.title);
  }

  void _openFromData(Map<String, dynamic> data, {String? title}) {
    final nav = AppNavigator.nav;
    if (nav == null) return;
    final String type = (data['type'] ?? '').toString();
    try {
      if (type == 'chat') {
        final String? senderId = data['senderId']?.toString();
        String? otherId = senderId;
        final me = FirebaseAuth.instance.currentUser?.uid;
        if ((otherId == null || otherId.isEmpty) && data['chatId'] != null && me != null) {
          otherId = data['chatId'].toString().split('_').firstWhere((id) => id != me, orElse: () => '');
        }
        if (otherId == null || otherId.isEmpty) return;
        final String target = otherId;
        final String name = (data['senderName'] ?? title ?? data['title'] ?? 'Собеседник').toString();
        nav.push(MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: target, otherUserName: name)));
      } else if (type == 'eva' || type == 'ai') {
        nav.push(MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
      }
    } catch (e) {
      debugPrint('open from push: $e');
    }
  }

  /// Убирает показанные уведомления из шторки. Запланированные напоминания
  /// Евы НЕ трогает (раньше cancelAll() удалял и их при каждом открытии чата).
  Future<void> clearAllNotifications() => LocalNotificationService().dismissDisplayed();

  Future<void> forceUpdateToken() async {
    final fcm = _fcm;
    if (fcm == null) return;
    // На устройствах без Google Play Services (Huawei и др.) и при блокировках
    // getToken() может бросать исключение — это не должно мешать работе приложения.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final String? token = await fcm.getToken().timeout(const Duration(seconds: 15));
        if (token != null) await _saveTokenToDatabase(token);
        return;
      } catch (e) {
        debugPrint('FCM getToken (попытка ${attempt + 1}): $e');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'fcmToken': token, 'lastTokenUpdate': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      ).catchError((e) => debugPrint("⚠️ Не удалось сохранить FCM токен: $e"));
    } catch (e) {
      debugPrint("⚠️ Не удалось сохранить FCM токен: $e");
    }
  }

  Future<void> clearToken() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': FieldValue.delete()})
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint("Ошибка при удалении токена FCM: $e");
    }
    try {
      await _fcm?.deleteToken().timeout(const Duration(seconds: 5));
    } catch (_) {}
    _initialized = false;
  }
}
