// Health Connect (Android): шаги, сон, активные калории и вес из других приложений
// (Samsung Health, Mi Fitness, Google Fit, Huawei через синхронизацию и т.д.).
// Только чтение. Сводка по дням сохраняется в users/{uid}/health_daily/{YYYY-MM-DD},
// чтобы её видели экран «Сегодня» и Ева. В аналитику данные о здоровье НЕ отправляются.

import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

enum HealthAvailability { unsupported, notInstalled, needsUpdate, available }

class HealthService {
  HealthService._();
  static final HealthService instance = HealthService._();

  final Health _health = Health();
  bool _configured = false;
  DateTime? _lastSync;

  /// Android применяет отзыв доступа Health Connect только после перезапуска приложения:
  /// до этого hasPermissions() продолжает отвечать true, и экран «зависал» в подключённом
  /// состоянии. Поэтому после отключения считаем доступ отозванным сами.
  bool _revokedThisSession = false;

  static const List<HealthDataType> types = [
    HealthDataType.STEPS,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
  ];
  static List<HealthDataAccess> get _read => types.map((_) => HealthDataAccess.READ).toList();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthAvailability> availability() async {
    if (!supported) return HealthAvailability.unsupported;
    try {
      await _configure();
      final status = await _health.getHealthConnectSdkStatus();
      return switch (status) {
        HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HealthAvailability.needsUpdate,
        _ => HealthAvailability.notInstalled,
      };
    } catch (e) {
      debugPrint('health availability: $e');
      return HealthAvailability.notInstalled;
    }
  }

  /// Открыть установку / обновление Health Connect.
  Future<void> install() async {
    try {
      await _configure();
      await _health.installHealthConnect();
    } catch (e) {
      debugPrint('health install: $e');
    }
  }

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Запросить доступ. true — разрешения выданы, данные синхронизированы.
  Future<bool> connect() async {
    if (await availability() != HealthAvailability.available) return false;
    try {
      final bool granted = await _health.requestAuthorization(types, permissions: _read);
      if (!granted) return false;
      _revokedThisSession = false;
      await _userRef?.set({'healthConnect': true}, SetOptions(merge: true));
      await sync(force: true);
      return true;
    } catch (e) {
      debugPrint('health connect: $e');
      return false;
    }
  }

  Future<bool> hasPermissions() async {
    if (_revokedThisSession) return false;
    if (await availability() != HealthAvailability.available) return false;
    try {
      return await _health.hasPermissions(types, permissions: _read) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _configure();
      await _health.revokePermissions().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('health revoke: $e');
    }
    _revokedThisSession = true;
    _lastSync = null;
    await _userRef?.set({'healthConnect': false}, SetOptions(merge: true));
  }

  /// Подтянуть последние [days] дней. Не чаще раза в 15 минут, если не [force].
  Future<void> sync({int days = 7, bool force = false}) async {
    final ref = _userRef;
    if (ref == null || !supported) return;
    if (!force && _lastSync != null && DateTime.now().difference(_lastSync!) < const Duration(minutes: 15)) return;
    if (!await hasPermissions()) return;
    _lastSync = DateTime.now();

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final WriteBatch batch = FirebaseFirestore.instance.batch();

    // Вес — последний за 60 дней.
    double? weight;
    DateTime? weightAt;
    try {
      final pts = await _health.getHealthDataFromTypes(types: const [HealthDataType.WEIGHT], startTime: now.subtract(const Duration(days: 60)), endTime: now);
      for (final p in pts) {
        final v = _num(p);
        if (v != null && v > 25 && v < 300 && (weightAt == null || p.dateFrom.isAfter(weightAt))) {
          weight = v;
          weightAt = p.dateFrom;
        }
      }
    } catch (e) {
      debugPrint('health weight: $e');
    }

    for (int i = 0; i < days; i++) {
      final DateTime start = today.subtract(Duration(days: i));
      final DateTime end = i == 0 ? now : start.add(const Duration(days: 1));
      final Map<String, dynamic> doc = {'syncedAt': FieldValue.serverTimestamp()};
      try {
        final int? steps = await _health.getTotalStepsInInterval(start, end);
        if (steps != null) doc['steps'] = steps;
      } catch (e) {
        debugPrint('health steps: $e');
      }
      try {
        final pts = _health.removeDuplicates(await _health.getHealthDataFromTypes(types: const [HealthDataType.ACTIVE_ENERGY_BURNED], startTime: start, endTime: end));
        double kcal = 0;
        for (final p in pts) {
          kcal += _num(p) ?? 0;
        }
        if (pts.isNotEmpty) doc['activeKcal'] = kcal.round();
      } catch (e) {
        debugPrint('health energy: $e');
      }
      try {
        // Сон «этой ночи»: с 18:00 предыдущего дня до 14:00 этого.
        final pts = _health.removeDuplicates(await _health.getHealthDataFromTypes(
          types: const [HealthDataType.SLEEP_SESSION],
          startTime: start.subtract(const Duration(hours: 6)),
          endTime: start.add(const Duration(hours: 14)),
        ));
        int minutes = 0;
        for (final p in pts) {
          minutes += p.dateTo.difference(p.dateFrom).inMinutes;
        }
        if (minutes > 0 && minutes < 20 * 60) doc['sleepMin'] = minutes;
      } catch (e) {
        debugPrint('health sleep: $e');
      }
      if (i == 0 && weight != null) {
        doc['weightKg'] = double.parse(weight.toStringAsFixed(1));
        doc['weightAt'] = Timestamp.fromDate(weightAt!);
      }
      if (doc.length > 1) batch.set(ref.collection('health_daily').doc(dayKey(start)), doc, SetOptions(merge: true));
    }
    try {
      await batch.commit();
    } catch (e) {
      debugPrint('health save: $e');
    }
  }

  double? _num(HealthDataPoint p) {
    final v = p.value;
    if (v is NumericHealthValue) return v.numericValue.toDouble();
    return null;
  }
}
