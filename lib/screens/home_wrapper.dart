import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/local_notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/subscription_service.dart';
import '../widgets/eva_ui.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

class HomeWrapper extends StatelessWidget {
  const HomeWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const EvaSplash();
        }
        final user = snapshot.data;
        if (user == null) return const AuthScreen();
        return FirestoreRoleLoader(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

/// Элегантная заставка на время загрузки.
class EvaSplash extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  const EvaSplash({super.key, this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: EvaBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Моя Ева', style: theme.textTheme.displayMedium?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: 8),
                Text('гармония в каждой калории', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.4)),
                const SizedBox(height: 32),
                if (message == null)
                  const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.2))
                else ...[
                  Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  if (onRetry != null) ...[
                    const SizedBox(height: 16),
                    EvaPrimaryButton(label: 'Повторить', onPressed: onRetry, expand: false, height: 48),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FirestoreRoleLoader extends StatefulWidget {
  final User user;
  const FirestoreRoleLoader({super.key, required this.user});

  @override
  State<FirestoreRoleLoader> createState() => _FirestoreRoleLoaderState();
}

class _FirestoreRoleLoaderState extends State<FirestoreRoleLoader> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;
  bool _slowNetworkHint = false;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots();
    P2PChatService().resetCaches();

    // Фоновые задачи НЕ блокируют показ приложения (раньше старт ждал
    // ответа сервера о «режиме модерации» — при VPN это была вечная загрузка).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService().initialize();
      LocalNotificationService().syncNotificationsOnStartup();
    });

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slowNetworkHint = true);
    });
  }

  void _retry() {
    setState(() {
      _userStream = FirebaseFirestore.instance.collection('users').doc(widget.user.uid).snapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EvaSplash(
            message: 'Не удалось загрузить профиль. Проверьте подключение к интернету.',
            onRetry: _retry,
          );
        }
        if (!snapshot.hasData) {
          return EvaSplash(
            message: _slowNetworkHint ? 'Соединение медленное — ещё немного…' : null,
          );
        }

        if (!snapshot.data!.exists) {
          return const OnboardingScreen();
        }

        final data = snapshot.data!.data() ?? <String, dynamic>{};
        SubscriptionService().refreshIfNeeded(data);

        final bool isOnboardingCompleted = data['isOnboardingCompleted'] ?? true;
        if (isOnboardingCompleted == false) {
          return const OnboardingScreen();
        }
        return const DashboardScreen();
      },
    );
  }
}
