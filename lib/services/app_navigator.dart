import 'package:flutter/material.dart';

/// Глобальный навигатор — нужен, чтобы открывать экраны из пушей и сервисов.
class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

  static NavigatorState? get nav => key.currentState;
  static BuildContext? get context => key.currentContext;
}
