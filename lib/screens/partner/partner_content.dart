// Тексты режима партнёра: что с ней происходит и как поддержать.
// Без медицинских подробностей и без темы фертильности — только забота.

import 'package:flutter/material.dart';

import '../../theme/eva_colors.dart';

class PartnerPhaseInfo {
  final String title;
  final String feel;
  final List<String> support;
  final Color color;
  final String emoji;
  const PartnerPhaseInfo({required this.title, required this.feel, required this.support, required this.color, required this.emoji});
}

class PartnerContent {
  PartnerContent._();

  static PartnerPhaseInfo forKey(String? mode, String? key) {
    if (mode == 'pregnancy') return pregnancy;
    if (mode != 'cycle') return unknown;
    return switch (key) {
      'menstruation' => menstruation,
      'follicular' => follicular,
      'ovulation' => peak,
      'pms' => pms,
      _ => luteal,
    };
  }

  static const menstruation = PartnerPhaseInfo(
    title: 'Месячные',
    emoji: '🌸',
    color: EvaColors.menstruation,
    feel: 'Сил меньше обычного, могут быть тянущие боли и желание тепла и покоя.',
    support: [
      'Грелка, плед и горячий чай — проверенная классика',
      'Возьми на себя часть домашних дел, не дожидаясь просьбы',
      'Не планируй на эти дни ничего тяжёлого и шумного',
      'Спроси «Чем помочь?» — и просто сделай это',
    ],
  );

  static const follicular = PartnerPhaseInfo(
    title: 'Подъём сил',
    emoji: '🌱',
    color: EvaColors.follicular,
    feel: 'Энергия растёт, настроение лёгкое, хочется нового и движения.',
    support: [
      'Предложи прогулку, спорт вместе или новое место',
      'Хорошее время для планов и совместных идей',
      'Поддержи её начинания — сейчас она горит делами',
    ],
  );

  static const peak = PartnerPhaseInfo(
    title: 'Пик энергии',
    emoji: '✨',
    color: EvaColors.ovulation,
    feel: 'Самые яркие дни цикла: много сил, общительности и уверенности.',
    support: [
      'Отличный момент для свидания или поездки',
      'Комплименты сейчас работают особенно хорошо',
      'Зови в гости друзей или на вечеринку — она будет рада',
    ],
  );

  static const luteal = PartnerPhaseInfo(
    title: 'Спокойная фаза',
    emoji: '🍂',
    color: EvaColors.luteal,
    feel: 'Энергия становится ровнее, больше хочется уюта и спокойных вечеров.',
    support: [
      'Уютный вечер дома, фильм и вкусный ужин',
      'Меньше спонтанных шумных планов',
      'Помоги с делами, если видишь, что она устала',
    ],
  );

  static const pms = PartnerPhaseInfo(
    title: 'Дни перед циклом',
    emoji: '🫶',
    color: EvaColors.roseDeep,
    feel: 'Может быть больше усталости, чувствительности и тяги к сладкому. Это гормоны, а не ты.',
    support: [
      'Терпение: не принимай резкие слова на свой счёт',
      'Её любимые вкусности дома — маленькое чудо',
      'Обнимай чаще и говори тёплые слова',
      'Не начинай сложных разговоров — отложи на пару дней',
    ],
  );

  static const pregnancy = PartnerPhaseInfo(
    title: 'Беременность',
    emoji: '🤍',
    color: EvaColors.pregnancy,
    feel: 'Организм проделывает огромную работу — усталость и смена настроения нормальны.',
    support: [
      'Бери на себя тяжёлое и бытовое',
      'Ходите вместе к врачу, если она хочет',
      'Спрашивай, как она себя чувствует, — и слушай',
    ],
  );

  static const unknown = PartnerPhaseInfo(
    title: 'Новый цикл ещё не отмечен',
    emoji: '🌙',
    color: EvaColors.lavender,
    feel: 'Как только она отметит начало цикла в приложении, здесь появятся подсказки на каждый день.',
    support: [
      'Будь внимательным: спроси, как прошёл её день',
      'Маленькие знаки заботы важнее больших жестов',
    ],
  );

  /// Сигналы, которые она может отправить партнёру.
  static const signals = <(String, String, String)>[
    ('hug', '🤗', 'Обними меня'),
    ('sweet', '🍫', 'Хочу вкусного'),
    ('space', '🌙', 'Нужна тишина'),
    ('hard', '🫶', 'Тяжёлый день'),
    ('love', '💗', 'Люблю тебя'),
  ];

  /// Ответы партнёра.
  static const replies = <(String, String)>[
    ('ok', '❤️ Понял, я рядом'),
    ('onway', '🏃 Уже иду'),
    ('love', '💗 Люблю тебя'),
  ];

  static String daysWord(int n) {
    final int a = n % 100, b = n % 10;
    if (a >= 11 && a <= 14) return 'дней';
    if (b == 1) return 'день';
    if (b >= 2 && b <= 4) return 'дня';
    return 'дней';
  }

  static String ago(int ms) {
    if (ms <= 0) return '';
    final Duration d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'только что';
    if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
    if (d.inHours < 24) return '${d.inHours} ч назад';
    return '${d.inDays} дн назад';
  }
}
