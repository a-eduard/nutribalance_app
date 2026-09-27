import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart';

import 'database_service.dart';

/// Работа с подписками RuStore.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService _instance = SubscriptionService._();
  factory SubscriptionService() => _instance;

  bool _refreshedThisSession = false;

  /// Отправляет активные покупки на сервер. Возвращает true, если хотя бы одна подтверждена.
  /// Бросает исключение, если магазин RuStore недоступен.
  Future<bool> restorePurchases() async {
    final response = await RustoreBillingClient.purchases().timeout(const Duration(seconds: 20));
    final purchasesList = response.purchases;
    bool hasActive = false;

    for (var p in purchasesList) {
      if (p == null) continue;
      final stateStr = p.purchaseState?.toString().toUpperCase() ?? '';
      if (!(stateStr.contains('PAID') || stateStr.contains('CONFIRMED') || stateStr.contains('COMPLETED'))) continue;

      final String pToken = p.purchaseId ?? "";
      final String pId = p.productId ?? "";
      if (pToken.isEmpty) continue;
      try {
        await FirebaseFunctions.instance
            .httpsCallable('verifyRuStorePurchase', options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
            .call({'productId': pId, 'purchaseToken': pToken});
        hasActive = true;
      } catch (e) {
        debugPrint("Ошибка восстановления чека $pToken: $e");
      }
    }
    return hasActive;
  }

  /// Тихое продление: если подписка вот-вот закончится (или уже закончилась),
  /// проверяем покупки в RuStore — автопродлённая подписка снова продлит доступ.
  Future<void> refreshIfNeeded(Map<String, dynamic>? userData) async {
    if (_refreshedThisSession || userData == null) return;
    final DateTime? until = DatabaseService.proUntil(userData);
    if (userData['isPro'] != true || until == null) return;
    if (until.difference(DateTime.now()).inDays > 3) return;
    _refreshedThisSession = true;
    try {
      await restorePurchases();
    } catch (e) {
      // RuStore недоступен (например, пользователь за границей) — не страшно.
      debugPrint('Тихое продление подписки не удалось: $e');
    }
  }
}
