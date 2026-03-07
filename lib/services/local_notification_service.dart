import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class LocalNotificationService {
  // Делаем класс Синглтоном, чтобы он не создавался дважды
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Инициализация таймзон
    tz.initializeTimeZones();
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    // 2. Настройки Android (используем стандартную иконку лаунчера)
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // 3. Настройки iOS (с запросом разрешений)
    final DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleDailyNotifications() async {
    await cancelAll(); // Сначала очищаем старые, чтобы не плодить дубли

    final random = Random();

    // Массивы фраз
    final morningMessages = [
      "Доброе утро! Не забудь выпить стакан воды перед завтраком ✨",
      "Привет! Ева на связи. Начинаем день с заботы о себе 🌸",
      "Твой идеальный день начинается сейчас. Запишем завтрак? 🥑"
    ];
    
    final afternoonMessages = [
      "Время обеда! Что у нас сегодня вкусного и полезного? 🥗",
      "Сделай паузу. Твоему организму нужна энергия на вторую половину дня ☀️",
      "Даже в суете не забывай про обед. Скинь мне фото своей тарелки! 📸"
    ];

    final eveningMessages = [
      "День почти позади. Заходи, проверим наш баланс и выпьем воды 🌙",
      "Ты сегодня отлично справилась! Посмотрим, как закрылись наши кольца КБЖУ? ✨",
      "Время расслабиться. Ева ждет тебя, чтобы подвести итоги дня 🧘‍♀️"
    ];

    // Планируем (id, Заголовок, Рандомный текст, Часы, Минуты)
    await _schedule(1, "Доброе утро! ☀️", morningMessages[random.nextInt(morningMessages.length)], 9, 30);
    await _schedule(2, "Время подкрепиться! 🍽", afternoonMessages[random.nextInt(afternoonMessages.length)], 14, 0);
    await _schedule(3, "Итоги дня ✨", eveningMessages[random.nextInt(eveningMessages.length)], 20, 30);
  }

  Future<void> _schedule(int id, String title, String body, int hour, int minute) async {
    await _flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nutribalance_daily', // ID канала
          'Заботливые напоминания', // Имя канала
          channelDescription: 'Напоминания о питании и воде от Евы',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFB76E79), // Наш Rose Gold акцент для иконки Android
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Чтобы повторялось КАЖДЫЙ ДЕНЬ
    );
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // Если время сегодня уже прошло, ставим на завтра
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> cancelAll() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
  }
}