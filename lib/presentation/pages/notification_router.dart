import 'package:flutter/material.dart';

import '../../data/services/notification_service.dart';
import '../../data/services/social_service.dart';
import 'community_chat_detail_page.dart';
import 'cruise_mode_page.dart';
import 'group_join_gate.dart';
import 'post_detail_page.dart';
import 'user_profile_page.dart';

/// 2026-08-23 (vucko, Sprachnachricht: „ueber die Glocke bzw. ueber den
/// Quicklink dann joinen will [...] dass ein Fehler kommt"):
///
/// „Notif-Tap pro Typ" lag bisher als private Methode `_openTarget` in
/// `notifications_page.dart` und war damit nur von der Glocke aus erreichbar.
/// Die getippte Handy-Push lief in `_handleTapData` gegen einen leeren Rumpf
/// mit TODO und landete auf der Startseite. Deshalb steht der Weg jetzt hier,
/// einmal, und beide Eingaenge rufen ihn auf.
class NotificationRouter {
  NotificationRouter._();

  /// Oeffnet das Ziel einer Benachrichtigung.
  ///
  /// [context] ist optional: Aus einer getippten Push heraus gibt es keinen
  /// Kontext, dann arbeitet der Router auf dem Wurzel-Navigator.
  static Future<void> oeffne({
    required String type,
    String? referenceId,
    String? fromUserId,
    String? fromUsername,
    Map<String, dynamic> payload = const {},
    BuildContext? context,
  }) async {
    final ref = (referenceId != null && referenceId.trim().isNotEmpty)
        ? referenceId.trim()
        : null;

    // Gruppen-bezogen → EIN gemeinsamer Weg fuer Glocke, Quicklink und Push.
    if (type.startsWith('group_')) {
      if (ref == null) return;
      await GruppenEinstieg.oeffnen(
        ref,
        context: context,
        einladerName: fromUsername,
        gruppenNameAusMeldung: payload['group_name'] as String?,
      );
      return;
    }

    final nav = _navigator(context);
    if (nav == null) return;

    // Follow / Freundschaftsanfrage → Profil des Absenders.
    if (type == 'follow' || type == 'friend_request') {
      if (fromUserId == null || fromUserId.isEmpty) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => UserProfilePage(
            userId: fromUserId,
            initialUsername: fromUsername,
          ),
        ),
      );
      return;
    }

    // 2026-08-28 (Fehler 6): Community-Chat → direkt in den Chat.
    if (type == 'community_message') {
      if (ref == null) return;
      await nav.push(
        MaterialPageRoute<void>(
          builder: (_) => CommunityChatDetailPage(communityId: ref),
        ),
      );
      return;
    }

    // Post-bezogen (Like/Kommentar/Repost/neuer Beitrag) → Post-Detail
    // oder „weg". feed_post (Fehler 6) traegt die Post-Id als reference_id
    // und laeuft denselben Weg.
    if (type == 'like' ||
        type == 'comment' ||
        type == 'repost' ||
        type == 'feed_post') {
      if (ref == null) return;
      final post = await SocialService.getPostById(ref);
      if (!nav.mounted) return;
      if (post == null) {
        zeigeNichtVerfuegbar(nav, 'Dieser Beitrag ist nicht mehr verfügbar.');
        return;
      }
      final profile = post['profiles'] as Map<String, dynamic>?;
      await nav.push(
        MaterialPageRoute<void>(
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
            sharedGroupId: post['shared_group_id'] as String?,
            avatarUrl: profile?['avatar_url'] as String?,
          ),
        ),
      );
      return;
    }

    // Tägliche Wetterempfehlung / Trip-Reminder → zurück zum Home und auf den
    // Cruise-Tab (Route generieren / losfahren). Tab-Wechsel statt loser
    // Vollbild-Seite, damit die Bottom-Nav erhalten bleibt.
    if (type == 'weather_recommendation' || type == 'trip_reminder') {
      nav.popUntil((r) => r.isFirst);
      CruiseModePage.openCruiseTab.value =
          CruiseModePage.openCruiseTab.value + 1;
      return;
    }
  }

  /// Eingang fuer die getippte Handy-Push. Die Schluessel kommen aus
  /// `supabase/functions/send-push/index.ts` (type, reference_id,
  /// from_user_id, notification_id).
  static Future<void> ausPushDaten(Map<String, dynamic> daten) async {
    final type = daten['type']?.toString() ?? '';
    if (type.isEmpty) return;
    final notifId = daten['notification_id']?.toString();
    if (notifId != null && notifId.isNotEmpty) {
      // Angetippt heisst gelesen — sonst bleibt der Punkt an der Glocke.
      NotificationService.instance.markAsRead(notifId);
    }
    await oeffne(
      type: type,
      referenceId: daten['reference_id']?.toString(),
      fromUserId: daten['from_user_id']?.toString(),
      fromUsername: daten['from_username']?.toString(),
      payload: <String, dynamic>{
        if (daten['group_name'] != null) 'group_name': daten['group_name'],
      },
    );
  }

  static NavigatorState? _navigator(BuildContext? context) {
    if (context != null && context.mounted) {
      return Navigator.of(context, rootNavigator: true);
    }
    return GruppenEinstieg.rootNavigatorSchluessel?.currentState;
  }

  static void zeigeNichtVerfuegbar(NavigatorState nav, String text) {
    showDialog<void>(
      context: nav.context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1E28),
        title: const Text(
          'Nicht mehr verfügbar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(text, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Ok'),
          ),
        ],
      ),
    );
  }
}
