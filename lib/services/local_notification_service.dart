import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    // Узнаем часовой пояс телефона
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      final bool? grantedNotification = await androidImplementation
          ?.requestNotificationsPermission();
      // Для inexact таймеров нам больше не нужно жестко требовать Exact Alarms, 
      // но оставим запрос на всякий случай для совместимости
      final bool? grantedAlarm = await androidImplementation
          ?.requestExactAlarmsPermission();

      return (grantedNotification ?? false) || (grantedAlarm ?? false);
    } else if (Platform.isIOS) {
      final bool? granted = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  Future<void> scheduleDailyNotifications() async {
    // 1. Очищаем все вообще
    await cancelAll();
    
    // 2. ЖЕСТКАЯ ОЧИСТКА по ID (на случай, если cancelAll не сработал из-за кэша ОС)
    await flutterLocalNotificationsPlugin.cancel(id: 1);
    await flutterLocalNotificationsPlugin.cancel(id: 2);
    await flutterLocalNotificationsPlugin.cancel(id: 3);

    String userName = 'дорогая';
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          final nameFromDb = doc.data()?['name']?.toString().trim();
          if (nameFromDb != null && nameFromDb.isNotEmpty) {
            userName = nameFromDb;
          }
        }
      }
    } catch (e) {
      debugPrint('Ошибка получения имени: $e');
    }

    final random = Random();

    // === УТРО (10:00) ===
    final morningTitles = [
      'Доброе утро! 🌸',
      'Просыпайся, $userName! 🌅',
      'Новый день! ✨',
    ];
    final morningBodies = [
      'Не забудь выпить стакан воды — твое тело скажет тебе спасибо 💧',
      'Время для себя! Сделай глубокий вдох и настройся на позитив 🌬️',
      'Улыбнись новому дню! Ты прекрасна, и у тебя всё получится ☀️',
    ];
    int mIdx = random.nextInt(morningTitles.length);

    await _scheduleDailyNotification(
      id: 101,
      title: morningTitles[mIdx],
      body: morningBodies[mIdx],
      hour: 10,
      minute: 00,
    );

    // === ОБЕД (14:00) ===
    final noonTitles = [
      'Время перерыва ☕️',
      'Пора пообедать 🥗',
      'Выдыхай! 🧘‍♀️',
    ];
    final noonBodies = [
      'Время выдохнуть и отдохнуть пару минут. Я здесь, если захочешь поболтать ❤️',
      'Твоему телу нужна энергия. Не забудь про вкусный и полезный обед 🥑',
      'Сделай паузу, разомни спину и выпей немного воды. Ты отлично справляешься! 💦',
    ];
    int nIdx = random.nextInt(noonTitles.length);

    await _scheduleDailyNotification(
      id: 102,
      title: noonTitles[nIdx],
      body: noonBodies[nIdx],
      hour: 14,
      minute: 00,
    );

    // === ВЕЧЕР (20:30) ===
    final eveningTitles = [
      'Время выдохнуть 🌙',
      'Итоги дня 🛁',
      'Пора отдыхать 💤',
    ];
    final eveningBodies = [
      'День позади! Отложи телефон, прими теплую ванну и расслабься 🕯️',
      'Ты отлично потрудилась. Самое время поблагодарить себя за этот день 🌸',
      'Сладких снов! Пусть эта ночь принесет тебе полное восстановление ✨',
    ];
    int eIdx = random.nextInt(eveningTitles.length);

    await _scheduleDailyNotification(
      id: 103,
      title: eveningTitles[eIdx],
      body: eveningBodies[eIdx],
      hour: 20,
      minute: 30,
    );
  }

  Future<void> _scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'eva_daily_reminders_v5',
        'Заботливые напоминания',
        channelDescription: 'Ежедневные уведомления от Евы',
        importance: Importance.max,
        priority: Priority.max,
        color: Color(0xFFB76E79),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfTime(hour, minute),
      notificationDetails: details,
      // ИСПРАВЛЕНИЕ: inexactAllowWhileIdle решает проблему двойных пушей на Android
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // ИСПРАВЛЕНИЕ: Защита от моментального двойного срабатывания, если таймер ставится минута-в-минуту
    if (scheduledDate.isBefore(now) || scheduledDate.isAtSameMomentAs(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    // ФИКС 2: Жестко добиваем все возможные зависшие ID (и старые, и новые)
    await flutterLocalNotificationsPlugin.cancel(id: 1);
    await flutterLocalNotificationsPlugin.cancel(id: 2);
    await flutterLocalNotificationsPlugin.cancel(id: 3);
    await flutterLocalNotificationsPlugin.cancel(id: 101);
    await flutterLocalNotificationsPlugin.cancel(id: 102);
    await flutterLocalNotificationsPlugin.cancel(id: 103);
  }

  // === ФИКС 3: Умная синхронизация при запуске приложения ===
  Future<void> syncNotificationsOnStartup() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      // Проверяем тумблер из базы данных
      final isEnabled = doc.data()?['notificationsEnabled'] == true;
      
      if (isEnabled) {
        await scheduleDailyNotifications();
      } else {
        await cancelAll(); // Жестко отменяем, если тумблер был выключен
      }
    } catch (e) {
      debugPrint('Ошибка синхронизации пушей при старте: $e');
    }
  }

  Future<void> testPushIn5Seconds() async {
    try {
      final bool granted = await requestPermissions();
      if (!granted) return;
      
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel_v4',
          'Тестовые уведомления',
          importance: Importance.max,
          priority: Priority.max,
          color: Color(0xFFB76E79),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      
      final tz.TZDateTime scheduledTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: 999,
        title: 'Отложенный тест! ⏳',
        body: 'Таймеры в фоне тоже работают!',
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('❌ ОШИБКА ТЕСТОВОГО ПУША: $e');
    }
  }
}