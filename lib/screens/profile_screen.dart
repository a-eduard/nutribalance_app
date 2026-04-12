import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../widgets/base_background.dart';
import 'profile_settings_screen.dart';
import '../paywall_screen.dart';
import 'p2p_chat_screen.dart';
import 'smart_questionnaire_screen.dart';
import 'specialist_paywall_screen.dart';
import '../services/database_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Исправлено: используем lowerCamelCase для констант по стандартам Dart
  static const String supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  Widget _buildMenuItem(
    IconData icon,
    String title, {
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? const Color(0xFF2D2D2D),
        size: 24,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF2D2D2D),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Color(0xFFC7C7CC),
        size: 16,
      ),
      onTap: onTap,
    );
  }

  Widget _divider() =>
      Divider(color: Colors.grey.withValues(alpha: 0.1), height: 1, indent: 56);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(backgroundColor: Color(0xFFF9F9F9));

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'Профиль',
            style: TextStyle(
              color: Color(0xFF2D2D2D),
              fontWeight: FontWeight.w900,
              fontSize: 26,
              letterSpacing: -0.5,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            // Исправлено: добавлены обязательные фигурные скобки
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFB76E79)),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final String name =
                data['name']?.toString().trim() ?? 'Пользователь';
            final String photoUrl = data['photoUrl'] ?? '';
            final String nickname = data['nickname']?.toString().trim() ?? '';
            final String displayNickname = nickname.isNotEmpty
                ? '@$nickname'
                : '';

            // Читаем флаг доступа к специалисту
            final bool hasSpecialistAccess =
                data['hasSpecialistAccess'] ?? false;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFB76E79,
                            ).withValues(alpha: 0.2),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        color: const Color(0xFFF2F2F7),
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl,
                                fit: BoxFit.cover,
                                // Если ссылка битая, показываем красивый градиент с буквой
                                errorWidget: (c, u, e) => Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFB6A6CA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  ),
                                  alignment: Alignment.center,
                                  // Исправлено: переменная name всегда имеет значение, убрали мертвый код
                                  child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                                ),
                              )
                            // Если фото изначально нет, тоже показываем градиент с первой буквой имени
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [Color(0xFFB76E79), Color(0xFFB6A6CA)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                ),
                                alignment: Alignment.center,
                                // Исправлено: убрали избыточную проверку isNotEmpty
                                child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Color(0xFF2D2D2D),
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (displayNickname.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          displayNickname,
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildMenuItem(
                            Icons.psychology_alt,
                            'Сделать Еву умнее (Пройти опрос)',
                            iconColor: const Color(0xFFB76E79),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SmartQuestionnaireScreen(),
                              ),
                            ),
                          ),
                          _divider(),
                          _buildMenuItem(
                            Icons.tune,
                            'Мои параметры',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ProfileSettingsScreen(),
                              ),
                            ),
                          ),
                          _divider(),
                          _buildMenuItem(
                            Icons.workspace_premium,
                            'Управление подпиской',
                            iconColor: const Color(0xFFB76E79),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PaywallScreen(isFromProfile: true),
                              ),
                            ),
                          ),
                          _divider(),
                          _buildMenuItem(
                            Icons.favorite_border,
                            'Заботливая поддержка',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const P2PChatScreen(
                                    // Исправлено: используем правильное имя константы
                                    otherUserId: supportAdminUid,
                                    otherUserName: 'Поддержка MyEva',
                                  ),
                                ),
                              );
                            },
                          ),
                          _divider(),

                          _buildMenuItem(
                            FontAwesomeIcons.vk, // Векторный логотип VK
                            'Наше комьюнити в VK',
                            // Успокаиваем цвет, чтобы он не ломал общую пастельную эстетику
                            iconColor: const Color(0xFF8E8E93), 
                            onTap: () async {
                              const url = 'https://vk.com/club237160300';
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                          _divider(),

                          // === КНОПКА СВЯЗИ СО СПЕЦИАЛИСТОМ ===
                          Builder(
                            builder: (context) {
                              // ИСПРАВЛЕНИЕ: Переменная вынесена ВНЕ StatefulBuilder.
                              // Теперь при вызове setTileState она сохранит свое значение true!
                              bool isOpeningChat = false;
                              
                              return StatefulBuilder(
                                builder: (context, setTileState) {
                                  return ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.star,
                                        color: Colors.amber,
                                        size: 20,
                                      ),
                                    ),
                                    title: const Text(
                                      'Связь со специалистом',
                                      style: TextStyle(
                                        color: Color(0xFF2D2D2D),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    trailing: isOpeningChat
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFB76E79),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.arrow_forward_ios,
                                            color: Color(0xFFC7C7CC),
                                            size: 16,
                                          ),
                                    onTap: () async {
                                      if (isOpeningChat) return; 
                                      
                                      setTileState(() => isOpeningChat = true);

                                      final bool inReview = await DatabaseService().isAppInReview();

                                      if (hasSpecialistAccess || inReview) {
                                        final specInfo = await DatabaseService().getSpecialistInfo();

                                        if (context.mounted) {
                                          setTileState(() => isOpeningChat = false);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => P2PChatScreen(
                                                otherUserId: specInfo['uid']!,
                                                otherUserName: specInfo['name']!,
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        if (context.mounted) {
                                          setTileState(() => isOpeningChat = false);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const SpecialistPaywallScreen(),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  );
                                },
                              );
                            }
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
