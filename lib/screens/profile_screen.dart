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
import 'progress_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const String supportAdminUid = 'VlTTLh2o7GVaXUzw32sNUtQ6alD3';

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title, {
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? theme.colorScheme.onSurface,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        size: 16,
      ),
      onTap: onTap,
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1), height: 1, indent: 56);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);
    
    if (uid == null) return Scaffold(backgroundColor: theme.scaffoldBackgroundColor);

    return BaseBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            'Профиль',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 26,
              letterSpacing: -0.5,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final String name = data['name']?.toString().trim() ?? 'Пользователь';
            final String photoUrl = data['photoUrl'] ?? '';
            final String nickname = data['nickname']?.toString().trim() ?? '';
            final String displayNickname = nickname.isNotEmpty ? '@$nickname' : '';
            final bool hasSpecialistAccess = data['hasSpecialistAccess'] ?? false;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.surface, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.2),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        color: theme.scaffoldBackgroundColor,
                      ),
                      child: ClipOval(
                        child: photoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: photoUrl, fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Container(
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.colorScheme.primary, const Color(0xFFB6A6CA)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                                  alignment: Alignment.center,
                                  child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.colorScheme.primary, const Color(0xFFB6A6CA)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                                alignment: Alignment.center,
                                child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      name,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
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
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
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
                          _buildMenuItem(context, Icons.psychology_alt, 'Сделать Еву умнее (Пройти опрос)', iconColor: theme.colorScheme.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartQuestionnaireScreen()))),
                          _divider(context),
                         _buildMenuItem(context, Icons.tune, 'Мои параметры', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()))),
                          _divider(context),
                          _buildMenuItem(context, Icons.insights, 'Мой прогресс', iconColor: theme.colorScheme.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProgressScreen()))),
                          _divider(context),
                          _buildMenuItem(context, Icons.workspace_premium, 'Управление подпиской', iconColor: theme.colorScheme.primary, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen(isFromProfile: true)))),
                          _divider(context),
                          _buildMenuItem(context, Icons.favorite_border, 'Заботливая поддержка', onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => const P2PChatScreen(otherUserId: supportAdminUid, otherUserName: 'Поддержка Моя Ева'))); }),
                          _divider(context),
                          _buildMenuItem(context, FontAwesomeIcons.vk, 'Наше комьюнити в VK', iconColor: theme.colorScheme.onSurfaceVariant, onTap: () async { const url = 'https://vk.com/club237160300'; final uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
                          _divider(context),
                          _buildMenuItem(context, Icons.play_circle_fill_outlined, 'Видео-обзор приложения', iconColor: theme.colorScheme.primary, onTap: () async { const url = 'https://vkvideo.ru/video-237160300_456239022'; final uri = Uri.parse(url); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
                          _divider(context),
                          Builder(
                            builder: (builderContext) {
                              bool isOpeningChat = false;
                              return StatefulBuilder(
                                builder: (ctx, setTileState) {
                                  return ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), shape: BoxShape.circle),
                                      child: const Icon(Icons.star, color: Colors.amber, size: 20),
                                    ),
                                    title: Text('Связь со специалистом', style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.w800)),
                                    trailing: isOpeningChat ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)) : Icon(Icons.arrow_forward_ios, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), size: 16),
                                    onTap: () async {
                                      if (isOpeningChat) return; 
                                      setTileState(() => isOpeningChat = true);
                                      
                                      // Сохраняем Navigator заранее, чтобы не обращаться к context после await
                                      final nav = Navigator.of(context);
                                      
                                      try {
                                        final bool inReview = await DatabaseService().isAppInReview();
                                        if (hasSpecialistAccess || inReview) {
                                          final specInfo = await DatabaseService().getSpecialistInfo();
                                          if (ctx.mounted) {
                                            setTileState(() => isOpeningChat = false);
                                          }
                                          nav.push(MaterialPageRoute(builder: (_) => P2PChatScreen(otherUserId: specInfo['uid']!, otherUserName: specInfo['name']!)));
                                        } else {
                                          if (ctx.mounted) {
                                            setTileState(() => isOpeningChat = false);
                                          }
                                          nav.push(MaterialPageRoute(builder: (_) => const SpecialistPaywallScreen()));
                                        }
                                      } catch (e) {
                                        if (ctx.mounted) {
                                          setTileState(() => isOpeningChat = false);
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