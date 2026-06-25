import 'package:flutter/material.dart';
import 'package:cruise_connect/presentation/widgets/skeletons/skeleton.dart';
import 'package:provider/provider.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/notification_service.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/group_lobby_page.dart';
import 'package:cruise_connect/presentation/pages/post_detail_page.dart';
import 'package:cruise_connect/presentation/pages/user_profile_page.dart';

/// Inbox-Page für alle Notifications.
/// Pull-to-Refresh + Swipe-to-Dismiss + Mark-all-as-read.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Auto-mark-as-read 1.5s nach Öffnen (User hat ja gesehen)
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      NotificationService.instance.markAllAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<AppAccentProvider>().color;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        elevation: 0,
        title: const Text(
          'Benachrichtigungen',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () => NotificationService.instance.markAllAsRead(),
            child: Text(
              'Alle gelesen',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: Consumer<NotificationService>(
        builder: (context, svc, _) {
          if (!svc.isLoaded) {
            return const SkeletonList(count: 7);
          }
          if (svc.items.isEmpty) {
            return _EmptyState(accent: accent);
          }
          return RefreshIndicator(
            color: accent,
            onRefresh: () => svc.loadInitial(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: svc.items.length,
              separatorBuilder: (ctx, _) =>
                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.04)),
              itemBuilder: (context, i) {
                final notif = svc.items[i];
                return Dismissible(
                  key: ValueKey(notif.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.redAccent.withValues(alpha: 0.85),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 26),
                  ),
                  onDismissed: (_) => svc.delete(notif.id),
                  child: _NotificationTile(notif: notif, accent: accent),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notif, required this.accent});

  final AppNotification notif;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final (title, body) = notif.renderTexts();
    final isUnread = !notif.read;
    final age = _formatAge(notif.createdAt);

    return Material(
      color: isUnread
          ? accent.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _openTarget(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarOrIcon(notif: notif, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: isUnread
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          age,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: isUnread ? 0.85 : 0.62,
                        ),
                        fontSize: 13,
                        height: 1.32,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 6),
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2026-06-25 (vucko): Deeplink je Notification-Typ. Gelöschte Ziele →
  /// „nicht mehr verfügbar"-Popup statt Navigation ins Leere.
  Future<void> _openTarget(BuildContext context) async {
    NotificationService.instance.markAsRead(notif.id);
    final type = notif.type;
    final ref = notif.referenceId;

    // Follow / Freundschaftsanfrage → Profil des Absenders.
    if (type == 'follow' || type == 'friend_request') {
      if (notif.fromUserId.isEmpty) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UserProfilePage(
            userId: notif.fromUserId,
            initialUsername: notif.fromUsername,
          ),
        ),
      );
      return;
    }

    // Post-bezogen (Like/Kommentar/Repost) → Post-Detail oder „weg".
    if (type == 'like' || type == 'comment' || type == 'repost') {
      if (ref == null) return;
      final post = await SocialService.getPostById(ref);
      if (!context.mounted) return;
      if (post == null) {
        _showUnavailable(context, 'Dieser Beitrag ist nicht mehr verfügbar.');
        return;
      }
      final profile = post['profiles'] as Map<String, dynamic>?;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostDetailPage(
            postId: ref,
            name: SocialService.publicDisplayName(
              profile,
              fallbackUserId: post['user_id'] as String?,
            ),
            handle: SocialService.publicHandle(
              profile,
              fallbackUserId: post['user_id'] as String?,
            ),
            content: (post['content'] ?? '').toString(),
            time: '',
            sharedRouteId: post['shared_route_id'] as String?,
            avatarUrl: profile?['avatar_url'] as String?,
          ),
        ),
      );
      return;
    }

    // Gruppen-bezogen → Lobby oder „diese Gruppe ist nicht mehr verfügbar".
    if (type.startsWith('group_')) {
      if (ref == null) return;
      final exists = await SocialService.groupExists(ref);
      if (!context.mounted) return;
      if (!exists) {
        _showUnavailable(context, 'Diese Gruppe ist nicht mehr verfügbar.');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupLobbyPage(groupId: ref)),
      );
      return;
    }
    // weather_recommendation / trip_reminder: rein informativ, kein Ziel.
  }

  void _showUnavailable(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E28),
        title: const Text(
          'Nicht mehr verfügbar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(
              'OK',
              style: TextStyle(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAge(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'jetzt';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays < 7) return '${diff.inDays} d';
    return '${(diff.inDays / 7).floor()} w';
  }
}

class _AvatarOrIcon extends StatelessWidget {
  const _AvatarOrIcon({required this.notif, required this.accent});

  final AppNotification notif;
  final Color accent;

  IconData get _typeIcon => switch (notif.type) {
        'follow' => Icons.person_add_alt_1,
        'like' => Icons.favorite,
        'comment' => Icons.chat_bubble_outline,
        'friend_request' => Icons.handshake_outlined,
        'group_invite' => Icons.group_add_outlined,
        'weather_recommendation' => Icons.wb_sunny_outlined,
        'trip_reminder' => Icons.route_outlined,
        _ => Icons.notifications_active_outlined,
      };

  Color get _typeColor => switch (notif.type) {
        'like' => const Color(0xFFEF4444),
        'follow' => const Color(0xFF3B82F6),
        'group_invite' || 'friend_request' => const Color(0xFF8B5CF6),
        'weather_recommendation' => const Color(0xFFFFA94D),
        'trip_reminder' => accent,
        _ => Colors.white70,
      };

  @override
  Widget build(BuildContext context) {
    final avatar = notif.fromAvatarUrl;
    if (avatar != null && avatar.isNotEmpty) {
      return Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white12,
            backgroundImage: NetworkImage(avatar),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: _typeColor,
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0xFF0B0E14), width: 1.5),
              ),
              child: Icon(_typeIcon, color: Colors.white, size: 11),
            ),
          ),
        ],
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _typeColor.withValues(alpha: 0.20),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(_typeIcon, color: _typeColor, size: 22),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.notifications_none_outlined,
              size: 38,
              color: accent.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Hier ist es ruhig',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Folge anderen Cruisern oder \nlike Posts — dann landen hier neue Updates',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
