import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../screens/ai_chat_screen.dart';
import 'app_navigator.dart';
import 'analytics_service.dart';

/// Одно «заботливое» сообщение Евы: короткий текст для шторки уведомлений
/// и полный текст, который пользователь читает в чате с Евой.
class _CareMessage {
  final String title;
  final String teaser;
  final String full;
  const _CareMessage(this.title, this.teaser, this.full);
}

class _CareSlot {
  final String key;
  final int hour;
  final int minute;
  final List<_CareMessage> messages;
  const _CareSlot(this.key, this.hour, this.minute, this.messages);
}

class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Обработчик нажатий на прочие локальные уведомления (например, пуши чата,
  /// показанные, пока приложение открыто). Регистрирует PushNotificationService.
  static void Function(Map<String, dynamic> data)? externalTapHandler;

  bool _initialized = false;
  Map<String, dynamic>? _pendingCare;

  // --- Заботливые напоминания ---
  // Канал оставлен прежним, чтобы не сбрасывать настройки звука у пользователей.
  static const String _careChannelId = 'eva_daily_reminders_v5';
  static const String _careChannelName = 'Заботливые напоминания';

  /// ID разовых напоминаний: 2000 + день * 3 + слот.
  static const int _careIdBase = 2000;
  static const int _careIdEnd = 2100;
  static const int _daysAhead = 7;

  /// ID повторяющихся напоминаний из прошлых версий приложения.
  static const List<int> _legacyIds = [1, 2, 3, 101, 102, 103, 999];

  Future<void> init() async {
    // ФИКС ЗАПУСКА ЗА РУБЕЖОМ: если часовой пояс устройства отсутствует в базе
    // (старые/нестандартные идентификаторы), tz.getLocation бросал исключение
    // прямо в main() и приложение зависало на заставке. Теперь — безопасный фолбэк.
    await _initTimeZone();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    _initialized = true;

    // Приложение запустили нажатием на уведомление — откроем сообщение после входа.
    try {
      final details = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
      final String? payload = details?.notificationResponse?.payload;
      if (details?.didNotificationLaunchApp == true && payload != null) {
        final data = _decode(payload);
        if (data != null && data['type'] == 'eva_care') _pendingCare = data;
      }
    } catch (e) {
      debugPrint('launch details: $e');
    }
  }

  bool get isInitialized => _initialized;

  Future<void> _initTimeZone() async {
    try {
      tz.initializeTimeZones();
    } catch (e) {
      debugPrint('tz init: $e');
      return;
    }
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone().timeout(const Duration(seconds: 3));
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      return;
    } catch (e) {
      debugPrint('Часовой пояс устройства не распознан: $e');
    }
    // Фолбэк: ищем любую зону с таким же текущим смещением от UTC.
    try {
      final Duration offset = DateTime.now().timeZoneOffset;
      for (final loc in tz.timeZoneDatabase.locations.values) {
        if (tz.TZDateTime.now(loc).timeZoneOffset == offset) {
          tz.setLocalLocation(loc);
          return;
        }
      }
      tz.setLocalLocation(tz.getLocation('UTC'));
    } catch (e) {
      debugPrint('tz fallback: $e');
    }
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final bool? grantedNotification = await androidImplementation?.requestNotificationsPermission();
      // Разрешение на точные будильники не запрашиваем: напоминания работают в
      // inexact-режиме, а запрос открывал системные настройки при каждом запуске.
      return grantedNotification ?? true;
    } else if (Platform.isIOS) {
      final bool? granted = await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  // ===========================================================================
  // Планирование
  // ===========================================================================

  /// Планирует заботливые напоминания на ближайшие 7 дней.
  ///
  /// ПОЧЕМУ НЕ ПОВТОРЯЮЩИЕСЯ: раньше использовался `matchDateTimeComponents`.
  /// После показа плагин сам переносит уведомление на «сегодня в то же время,
  /// если оно ещё не наступило». Некоторые прошивки (MIUI/HyperOS и др.)
  /// выравнивают будильники и срабатывают на несколько минут РАНЬШЕ — тогда
  /// «сегодня 14:00» ещё не наступило, и уведомление приходило второй раз через
  /// ~5 минут. Разовые уведомления на неделю вперёд такой проблемы не имеют и
  /// обновляются при каждом запуске приложения.
  Future<void> scheduleDailyNotifications() async {
    await cancelCareReminders();

    final String name = await _loadUserName();
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final NotificationDetails details = _careDetails;

    for (int dayOffset = 0; dayOffset < _daysAhead; dayOffset++) {
      for (int slotIndex = 0; slotIndex < _slots.length; slotIndex++) {
        final _CareSlot slot = _slots[slotIndex];
        final tz.TZDateTime when = tz.TZDateTime(tz.local, now.year, now.month, now.day + dayOffset, slot.hour, slot.minute);
        if (!when.isAfter(now.add(const Duration(minutes: 1)))) continue;

        final int dayNumber = DateTime(when.year, when.month, when.day).difference(DateTime(2024)).inDays;
        final _CareMessage msg = slot.messages[(dayNumber + slotIndex * 2) % slot.messages.length];
        final String title = _fill(msg.title, name);
        final String teaser = _fill(msg.teaser, name);
        final String full = _fill(msg.full, name);
        final String dateKey = '${when.year}${when.month.toString().padLeft(2, '0')}${when.day.toString().padLeft(2, '0')}';

        try {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            id: _careIdBase + dayOffset * _slots.length + slotIndex,
            title: title,
            body: teaser,
            scheduledDate: when,
            notificationDetails: _withBigText(details, title, full),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: jsonEncode({'type': 'eva_care', 'id': 'care_${dateKey}_${slot.key}', 'title': title, 'text': full}),
          );
        } catch (e) {
          debugPrint('schedule care: $e');
        }
      }
    }
  }

  NotificationDetails get _careDetails => const NotificationDetails(
        android: AndroidNotificationDetails(
          _careChannelId,
          _careChannelName,
          channelDescription: 'Ежедневные уведомления от Евы',
          importance: Importance.high,
          priority: Priority.high,
          color: Color(0xFFB76E79),
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      );

  NotificationDetails _withBigText(NotificationDetails base, String title, String full) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _careChannelId,
        _careChannelName,
        channelDescription: 'Ежедневные уведомления от Евы',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFFB76E79),
        // Свёрнутое уведомление — короткая фраза, развёрнутое — полный текст.
        styleInformation: BigTextStyleInformation(full, contentTitle: title, summaryText: 'Ева'),
      ),
      iOS: base.iOS,
    );
  }

  Future<String> _loadUserName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      try {
        doc = await ref.get().timeout(const Duration(seconds: 6));
      } catch (e) {
        debugPrint('Ошибка получения имени: $e');
      }
    }
    final String name = (doc?.data()?['name'] ?? '').toString().trim();
    return name.split(' ').first;
  }

  String _fill(String template, String name) {
    final String n = name.isEmpty ? 'дорогая' : name;
    final String capital = n[0].toUpperCase() + n.substring(1);
    return template.replaceAll('{Name}', capital).replaceAll('{name}', n);
  }

  /// Отменяет только заботливые напоминания (и старые повторяющиеся).
  Future<void> cancelCareReminders() async {
    final Set<int> ids = {..._legacyIds};
    for (int id = _careIdBase; id < _careIdBase + _daysAhead * _slots.length; id++) {
      ids.add(id);
    }
    try {
      final pending = await flutterLocalNotificationsPlugin.pendingNotificationRequests();
      for (final p in pending) {
        if ((p.id >= _careIdBase && p.id < _careIdEnd) || _legacyIds.contains(p.id)) ids.add(p.id);
      }
    } catch (e) {
      debugPrint('pending notifications: $e');
    }
    for (final id in ids) {
      try {
        await flutterLocalNotificationsPlugin.cancel(id: id);
      } catch (_) {}
    }
  }

  /// Полная очистка (выход из аккаунта, удаление аккаунта).
  Future<void> cancelAll() async {
    try {
      await flutterLocalNotificationsPlugin.cancelAll();
    } catch (_) {}
    await cancelCareReminders();
  }

  /// Убирает из шторки уже показанные уведомления (например, при открытии чата),
  /// НЕ трогая запланированные напоминания.
  Future<void> dismissDisplayed() async {
    try {
      final active = await flutterLocalNotificationsPlugin.getActiveNotifications();
      for (final n in active) {
        final int? id = n.id;
        if (id == null) continue;
        await flutterLocalNotificationsPlugin.cancel(id: id, tag: n.tag);
      }
    } catch (e) {
      debugPrint('dismiss notifications: $e');
    }
  }

  /// Синхронизация при запуске приложения: тумблер хранится в профиле.
  Future<void> syncNotificationsOnStartup() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref.get(const GetOptions(source: Source.cache));
      } catch (_) {
        doc = await ref.get().timeout(const Duration(seconds: 8));
      }
      if (doc.data()?['notificationsEnabled'] == true) {
        await scheduleDailyNotifications();
      } else {
        await cancelCareReminders();
      }
    } catch (e) {
      debugPrint('Ошибка синхронизации напоминаний при старте: $e');
    }
  }

  // ===========================================================================
  // Нажатие на уведомление
  // ===========================================================================

  Map<String, dynamic>? _decode(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _onNotificationTap(NotificationResponse response) {
    final String? payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final data = _decode(payload);
    if (data == null) return;
    if (data['type'] == 'eva_care') {
      _openCareMessage(data);
    } else {
      externalTapHandler?.call(data);
    }
  }

  /// Вызывается после входа в аккаунт: если приложение открыли тапом по
  /// напоминанию, показываем сообщение Евы в чате.
  void handlePendingLaunch() {
    final data = _pendingCare;
    if (data == null) return;
    _pendingCare = null;
    _openCareMessage(data);
  }

  void _openCareMessage(Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final nav = AppNavigator.nav;
    if (uid == null || nav == null) {
      _pendingCare = data;
      return;
    }
    final String text = (data['text'] ?? '').toString().trim();
    final String docId = (data['id'] ?? '').toString();
    if (text.isNotEmpty && RegExp(r'^[A-Za-z0-9_]{1,80}$').hasMatch(docId)) {
      // Полный текст напоминания появляется в чате с Евой — на него можно ответить.
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ai_chats_dietitian')
          .doc(docId)
          .set({
            'text': text,
            'role': 'ai',
            'kind': 'care',
            'timestamp': FieldValue.serverTimestamp(),
            'isActionCompleted': true,
          })
          .catchError((Object e) => debugPrint('care message save: $e'));
    }
    final String slot = docId.split('_').last;
    Analytics.event('care_reminder_open', {'slot': slot});
    nav.push(MaterialPageRoute(builder: (_) => const AIChatScreen(botType: 'dietitian')));
  }

  // ===========================================================================
  // Тексты
  // ===========================================================================

  static const List<_CareSlot> _slots = [
    _CareSlot('morning', 10, 0, [
      _CareMessage('Доброе утро 🌸', 'Начнём день со стакана воды?',
          'Доброе утро, {name}! 🌸 За ночь организм теряет немало жидкости, поэтому стакан тёплой воды — лучший способ мягко проснуться. Можно добавить дольку лимона. Я рядом, если захочешь подобрать вкусный завтрак ☀️'),
      _CareMessage('Новый день ✨', 'Маленькая цель на сегодня',
          'Привет, {name}! ✨ Давай выберем одну маленькую цель на сегодня: 10 минут прогулки, тарелка овощей к обеду или лечь спать на полчаса раньше. Маленькие шаги каждый день дают большой результат. Какую выберешь?'),
      _CareMessage('Время завтрака 🥣', 'Белок утром — энергия до обеда',
          'Доброе утро, {name}! 🥣 Завтрак с белком — яйца, творог, греческий йогурт — даёт ровную энергию и помогает меньше тянуться к сладкому днём. Хочешь, подскажу пару быстрых вариантов на 5 минут?'),
      _CareMessage('С добрым утром ☀️', 'Три глубоких вдоха — и в путь',
          '{Name}, с добрым утром! ☀️ Прежде чем открыть соцсети, сделай три медленных вдоха и потянись. Это займёт минуту, но настроит тебя на спокойный день. Ты справишься со всем, что запланировала 💛'),
      _CareMessage('Доброе утро 💧', 'Как ты себя чувствуешь?',
          'Доброе утро, {name}! 💧 Прислушайся к себе: как спалось, есть ли энергия? Отметь самочувствие в «Гармонии» — так мне будет проще давать советы именно под твой цикл и настроение.'),
      _CareMessage('Утро для себя 🌿', 'Пара минут только для тебя',
          '{Name}, доброе утро! 🌿 Подари себе пару минут тишины: чашка чая, окно, спокойное дыхание. Забота о себе — не роскошь, а основа хорошего дня. Я в тебя верю!'),
    ]),
    _CareSlot('noon', 14, 0, [
      _CareMessage('Время обеда 🥗', 'Половину тарелки — овощам',
          '{Name}, как проходит день? 🥗 Подсказка к обеду: половина тарелки — овощи, четверть — белок (мясо, рыба, бобовые), четверть — крупы или хлеб. Так сытость сохранится надолго. Сфотографируй обед — я посчитаю КБЖУ 📸'),
      _CareMessage('Пауза ☕️', 'Разомни плечи и выпей воды',
          'Привет, {name}! ☕️ Самое время для короткой паузы: разомни шею и плечи, пройдись пару минут и выпей стакан воды. Даже небольшая активность снимает дневную усталость. Ты отлично справляешься!'),
      _CareMessage('Как ты? 💛', 'Я рядом, если нужна поддержка',
          '{Name}, просто хотела напомнить: ты молодец 💛 Если день выдался напряжённым — выдохни и не требуй от себя идеальности. Можешь написать мне о чём угодно: о еде, самочувствии или настроении.'),
      _CareMessage('Вода 💧', 'Уже выпила пару стаканов?',
          '{Name}, середина дня — хороший момент проверить, сколько воды ты уже выпила 💧 Часто лёгкая усталость и головная боль — это просто жажда. Отмечай стаканы на главном экране, чтобы не сбиться.'),
      _CareMessage('Перекус с пользой 🍎', 'Идеи, если хочется сладкого',
          '{Name}, если после обеда тянет на сладкое 🍎 — попробуй яблоко с горстью орехов, йогурт с ягодами или пару долек тёмного шоколада. Сладкое не запрещено: главное — с удовольствием и без чувства вины.'),
      _CareMessage('Минутка тишины 🧘‍♀️', 'Одна минута — и снова в строй',
          'Привет, {name}! 🧘‍♀️ Закрой глаза на минуту: вдох на 4 счёта, выдох на 6. Такое дыхание помогает снизить стресс прямо посреди дня. Вернёшься к делам с ясной головой ✨'),
    ]),
    _CareSlot('evening', 20, 30, [
      _CareMessage('Время выдохнуть 🌙', 'День позади — ты молодец',
          '{Name}, день позади 🌙 Вспомни три вещи, за которые ты сегодня благодарна себе — даже самые маленькие. Эта простая привычка со временем делает нас спокойнее и счастливее. Спокойного вечера!'),
      _CareMessage('Вечерний ритуал 🛁', 'Тёплый душ и меньше экранов',
          '{Name}, пора замедлиться 🛁 Тёплый душ, приглушённый свет и час без телефона перед сном помогают уснуть быстрее и глубже. А хороший сон — лучшая поддержка для гормонов и настроения.'),
      _CareMessage('Итоги дня ✨', 'Загляни в дневник питания',
          'Привет, {name}! ✨ Загляни в дневник: всё ли записано за сегодня? Не переживай, если что-то пошло не по плану — важен общий курс, а не один день. Завтра — новая возможность позаботиться о себе.'),
      _CareMessage('Лёгкий ужин 🍵', 'Ужин за 2–3 часа до сна',
          '{Name}, подсказка на вечер 🍵 Лёгкий ужин за 2–3 часа до сна помогает лучше спать и просыпаться бодрой. Подойдут рыба или курица с овощами, омлет или творог. Хочешь рецепт?'),
      _CareMessage('Сладких снов 💤', 'Пусть ночь будет спокойной',
          '{Name}, ты сегодня отлично потрудилась 💤 Отложи телефон пораньше, проветри комнату и позволь себе полноценно отдохнуть. Во сне тело восстанавливается. Спокойной ночи!'),
      _CareMessage('Как прошёл день? 🌸', 'Расскажи мне, я выслушаю',
          '{Name}, как прошёл твой день? 🌸 Если хочется — расскажи мне, я выслушаю. А ещё можно отметить настроение в «Гармонии»: со временем ты увидишь, как оно связано с циклом.'),
    ]),
  ];
}
