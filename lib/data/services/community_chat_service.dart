import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/emoji_guard.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/community_chat_message.dart';

class CommunityChatServiceException implements Exception {
  const CommunityChatServiceException(this.message, {this.code});

  final String message;

  /// 2026-08-23 (Auftrag Vucko): benannter Grund, damit die Oberfläche einen
  /// Fehler NICHT als Rauschen wegfiltert. Gemessen: `_friendlyError` in
  /// community_chat_detail_page.dart wirft jede Meldung weg, die „policy" oder
  /// „row-level" enthält — genau das schickt Postgres aber, wenn der Admin das
  /// Schreiben gesperrt hat. Das Mitglied sah deshalb nur „Nachricht konnte
  /// nicht gesendet werden." und wusste nie, warum. Siehe
  /// [CommunityChatService.writeLockedCode], Vorbild ist das bestehende CC001.
  final String? code;

  @override
  String toString() => message;
}

/// 2026-08-23 (Entscheidung Vucko): Was ein Einladungscode bewirkt hat.
/// Spiegelt `status` aus der RPC `join_community_with_code_v2`.
enum CommunityJoinStatus {
  /// Öffentliche Community: sofort Mitglied.
  joined,

  /// War schon Mitglied. Bestehende Mitglieder behalten ihren Zugang, auch
  /// wenn die Community inzwischen privat ist.
  alreadyMember,

  /// Privat: eine Beitrittsanfrage liegt jetzt beim Admin.
  requestCreated,

  /// Privat: eine Anfrage lag schon offen, es wird keine zweite gestellt.
  requestPending,

  /// Privat: vor kurzem abgelehnt, die Sperrfrist von sieben Tagen läuft noch.
  requestRejected,
}

class CommunityJoinResult {
  const CommunityJoinResult({
    required this.communityId,
    required this.status,
    this.name,
    this.isPublic = false,
  });

  factory CommunityJoinResult.fromJson(Map<String, dynamic> json) {
    final raw = json['status']?.toString();
    final status = switch (raw) {
      'joined' => CommunityJoinStatus.joined,
      'already_member' => CommunityJoinStatus.alreadyMember,
      'request_created' => CommunityJoinStatus.requestCreated,
      'request_pending' => CommunityJoinStatus.requestPending,
      'request_rejected' => CommunityJoinStatus.requestRejected,
      _ => CommunityJoinStatus.joined,
    };
    return CommunityJoinResult(
      communityId: json['community_id']?.toString() ?? '',
      status: status,
      name: json['name']?.toString(),
      isPublic: json['is_public'] == true,
    );
  }

  final String communityId;
  final CommunityJoinStatus status;
  final String? name;
  final bool isPublic;

  /// Nur bei diesen beiden Ausgängen darf die App den Chat öffnen. Bei den
  /// drei Anfrage-Ausgängen ist der Nutzer NICHT drin und würde sonst in eine
  /// leere, nicht lesbare Seite laufen.
  bool get opensCommunity =>
      status == CommunityJoinStatus.joined ||
      status == CommunityJoinStatus.alreadyMember;

  /// Der Satz, den der Nutzer danach sieht. Ohne Gedankenstriche, mit
  /// ausgeschriebenen Umlauten.
  String get userMessage {
    final label = (name == null || name!.trim().isEmpty)
        ? 'der Community'
        : '„${name!.trim()}"';
    return switch (status) {
      CommunityJoinStatus.joined => 'Willkommen bei $label.',
      CommunityJoinStatus.alreadyMember => 'Du bist schon bei $label dabei.',
      CommunityJoinStatus.requestCreated =>
        '$label ist privat. Deine Anfrage liegt jetzt beim Admin.',
      CommunityJoinStatus.requestPending =>
        'Deine Anfrage an $label liegt schon beim Admin. Bitte warte auf die Antwort.',
      CommunityJoinStatus.requestRejected =>
        'Deine Anfrage an $label wurde abgelehnt. In sieben Tagen kannst du erneut fragen.',
    };
  }
}

class CommunityChatService {
  CommunityChatService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;
  static const String duplicateRoutePostMessage =
      'Diese Route hast du in dieser Community schon gepostet.';

  /// 2026-08-23 (Auftrag Vucko): benannter Grund für „Der Admin hat das
  /// Schreiben gerade gesperrt." Vorbild ist das bestehende CC001 im
  /// Premium-Gate: ein eigener Code statt eines generischen 42501, weil 42501
  /// für JEDE Regelverletzung auf JEDER Tabelle steht und deshalb von
  /// `_friendlyError` bewusst weggefiltert wird.
  static const String writeLockedCode = 'CC002';

  static const String writeLockedMessage =
      'Der Admin hat das Schreiben gerade gesperrt.';

  /// Der Text, der im nur-Admin-Modus über dem Eingabefeld steht, und die
  /// Erklärung in den Einstellungen. Beide MESSEN das tatsächliche Verhalten:
  ///
  /// Gemessen am 23.08.2026 an der Regel `members_write_community_messages`:
  /// im nur-Admin-Modus dürfen `owner` UND `moderator` schreiben, nicht nur
  /// der Owner. Der alte Menütext „Nur Owner schreibt" war also sachlich
  /// falsch. Reagieren bleibt offen, weil `cmr_insert` nur Mitgliedschaft
  /// verlangt und `owner_only_messages` gar nicht liest — das ist seit
  /// Vuckos Entscheidung vom 23.08.2026 ausdrücklich gewollt.
  static const String writeModeAdminsTitle = 'Nur Admins und Moderatoren';

  static const String writeModeEveryoneTitle = 'Alle Mitglieder';

  static const String writeModeExplanation =
      'Ist das an, schreiben nur Admins und Moderatoren neue Beiträge. '
      'Mit Emoji reagieren bleibt für alle offen.';

  /// 2026-08-23 (Auftrag Vucko): `invite_code` ist hier RAUSGEFLOGEN und
  /// `avatar_url` dazugekommen.
  ///
  /// Gemessen am 23.08.2026: jeder angemeldete Nutzer konnte den
  /// `invite_code` JEDER öffentlichen Community lesen — die Zeilenregel
  /// `communities_visible_public_or_member` gibt öffentliche Zeilen frei und
  /// `authenticated` hatte ein tabellenweites Leserecht. Codes ließen sich
  /// also auf Vorrat sammeln und nach einem Wechsel auf privat einlösen. Die
  /// Migration 20260823123000 hat das Leserecht deshalb auf eine Spaltenliste
  /// OHNE `invite_code` verengt. Bliebe die Spalte hier stehen, käme ab sofort
  /// bei jedem Laden ein „permission denied for table communities" (42501) —
  /// und der `_isMissingColumn`-Fallback greift dort NICHT, weil das kein
  /// fehlende-Spalte-Fehler ist. Der eigene Code kommt jetzt über
  /// [inviteCodeFor] (RPC `get_community_invite_code`, nur für Mitglieder).
  ///
  /// ACHTUNG für später: das Leserecht ist jetzt spaltenweise. Jede neue
  /// Spalte auf `public.communities` braucht ein eigenes `grant select`.
  static const String _communitySelect =
      'id, owner_id, name, description, is_public, created_at, '
      'updated_at, owner_only_messages, avatar_url, '
      'community_members(user_id, role), '
      'profiles:owner_id(id, username, avatar_url)';

  /// UNVERÄNDERT mit Absicht. Diese Liste läuft nur, wenn die Datenbank
  /// `owner_only_messages`/`avatar_url` gar nicht kennt — also auf einem alten
  /// Stand VOR der Migration 20260823123000. Dort ist `invite_code` noch
  /// tabellenweit lesbar, die Abfrage geht also durch.
  static const String _legacyCommunitySelect =
      'id, owner_id, name, description, is_public, invite_code, created_at, '
      'updated_at, community_members(user_id, role), '
      'profiles:owner_id(id, username, avatar_url)';

  static const String _messageSelect =
      'id, community_id, user_id, body, created_at, updated_at, deleted_at, '
      'reply_to_message_id, route_attachment, pinned_at, pinned_by, '
      'profiles:user_id(id, username, avatar_url), '
      'community_message_reactions(emoji, user_id)';

  static const String _messageSelectWithoutPins =
      'id, community_id, user_id, body, created_at, updated_at, deleted_at, '
      'reply_to_message_id, route_attachment, '
      'profiles:user_id(id, username, avatar_url), '
      'community_message_reactions(emoji, user_id)';

  static const String _legacyMessageSelect =
      'id, community_id, user_id, body, created_at, updated_at, deleted_at, '
      'profiles:user_id(id, username, avatar_url)';

  static const String _memberSelect =
      'id, community_id, user_id, role, created_at, '
      'profiles:user_id(id, username, avatar_url)';

  static String? normalizeInviteCode(String raw) {
    final cleaned = raw.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (cleaned.startsWith('CCC') && cleaned.length == 9) {
      final body = cleaned.substring(3);
      if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(body)) return null;
      return 'CCC-$body';
    }
    if (!cleaned.startsWith('CM') || cleaned.length != 8) return null;
    final body = cleaned.substring(2);
    if (!RegExp(r'^[A-Z2-9]{6}$').hasMatch(body)) return null;
    return 'CM-$body';
  }

  static bool _isMissingColumn(PostgrestException e) {
    final message = e.message.toLowerCase();
    return e.code == '42703' ||
        message.contains('column') && message.contains('does not exist') ||
        message.contains('could not find') && message.contains('column');
  }

  static Map<String, dynamic>? ownerProfile(Map<String, dynamic> community) {
    final direct = community['profiles'];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    final rpc = community['owner_profile'];
    if (rpc is Map) return Map<String, dynamic>.from(rpc);
    return null;
  }

  static String displayName(
    Map<String, dynamic>? profile, {
    String? fallbackUserId,
  }) {
    return SocialService.publicDisplayName(
      profile,
      fallbackUserId: fallbackUserId,
    );
  }

  static int memberCount(Map<String, dynamic> community) {
    final rpcCount = community['member_count'];
    if (rpcCount is num) return rpcCount.toInt();
    final members = community['community_members'];
    if (members is List) return members.length;
    return 0;
  }

  /// 2026-08-23 (Auftrag Vucko „Profilbilder für Communities"): liest das
  /// Bild aus einer Community-Zeile. Die Spaltenabfrage und die RPC
  /// `find_community_by_code` liefern beide `avatar_url`; ein leerer String
  /// zählt wie kein Bild, damit der Platzhalter greift.
  static String? avatarUrl(Map<String, dynamic>? community) {
    final raw = community?['avatar_url']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static bool isCurrentUserMember(Map<String, dynamic> community) {
    final uid = _userId;
    if (uid == null) return false;
    if (community['owner_id'] == uid) return true;
    final members = community['community_members'];
    if (members is! List) return false;
    return members.any((member) {
      if (member is! Map) return false;
      return member['user_id'] == uid;
    });
  }

  static String? currentUserRole(Map<String, dynamic> community) {
    final uid = _userId;
    if (uid == null) return null;
    if (community['owner_id'] == uid) return 'owner';
    final members = community['community_members'];
    if (members is! List) return null;
    for (final member in members) {
      if (member is Map && member['user_id'] == uid) {
        return member['role']?.toString();
      }
    }
    return null;
  }

  static bool canInvite(Map<String, dynamic> community) {
    final role = currentUserRole(community);
    return role == 'owner' || role == 'moderator';
  }

  static bool canManageRoles(String? role) => role == 'owner';

  static bool canModerate(String? role) =>
      role == 'owner' || role == 'moderator';

  static String roleLabel(String? role) {
    switch (role) {
      case 'owner':
        return 'Admin';
      case 'moderator':
        return 'Moderator';
      default:
        return 'User';
    }
  }

  static Future<List<Map<String, dynamic>>> getMyCommunities() async {
    final uid = _userId;
    if (uid == null) return [];

    final memberships = await _db
        .from('community_members')
        .select('community_id')
        .eq('user_id', uid);
    final ids = <String>{
      ...(memberships as List).map((row) => row['community_id'] as String),
    };
    if (ids.isEmpty) return [];

    try {
      final rows = await _db
          .from('communities')
          .select(_communitySelect)
          .inFilter('id', ids.toList())
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e)) rethrow;
      final rows = await _db
          .from('communities')
          .select(_legacyCommunitySelect)
          .inFilter('id', ids.toList())
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    }
  }

  static Future<List<Map<String, dynamic>>> getDiscoverCommunities() async {
    final uid = _userId;
    final blocked = await SocialService.getBlockedAndBlockerIds();
    dynamic rows;
    try {
      rows = await _db
          .from('communities')
          .select(_communitySelect)
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(60);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e)) rethrow;
      rows = await _db
          .from('communities')
          .select(_legacyCommunitySelect)
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(60);
    }
    final list = List<Map<String, dynamic>>.from(rows as List);

    return list
        .where((community) {
          if (blocked.contains(community['owner_id'])) return false;
          if (uid == null) return true;
          if (community['owner_id'] == uid) return false;
          return !isCurrentUserMember(community);
        })
        .take(40)
        .toList();
  }

  static Future<String> createCommunity({
    required String name,
    String? description,
    required bool isPublic,
    bool ownerOnlyMessages = false,
  }) async {
    final uid = _userId;
    if (uid == null) {
      throw const CommunityChatServiceException('Bitte melde dich an.');
    }

    final cleanName = name.trim();
    final cleanDescription = description?.trim();
    if (cleanName.isEmpty ||
        cleanName.length > AppInputLimits.communityNameMaxLength) {
      throw const CommunityChatServiceException(
        'Community-Name ist ungültig.',
      );
    }
    if ((cleanDescription?.length ?? 0) >
        AppInputLimits.communityDescriptionMaxLength) {
      throw const CommunityChatServiceException(
        'Community-Beschreibung ist zu lang.',
      );
    }

    try {
      final payload = {
        'owner_id': uid,
        'name': cleanName,
        'description': cleanDescription == null || cleanDescription.isEmpty
            ? null
            : cleanDescription,
        'is_public': isPublic,
        'owner_only_messages': ownerOnlyMessages,
      };
      Map row;
      try {
        row = await _db
            .from('communities')
            .insert(payload)
            .select('id')
            .single();
      } on PostgrestException catch (e) {
        if (!_isMissingColumn(e)) rethrow;
        payload.remove('owner_only_messages');
        row = await _db
            .from('communities')
            .insert(payload)
            .select('id')
            .single();
      }
      return row['id'] as String;
    } on PostgrestException catch (e) {
      // CC001 = server-seitiges Premium-Gate (Trigger, folgt nach Rollout
      // dieser App-Version) — eigener Code statt generischem 42501, weil
      // das für JEDE RLS-Verletzung auf JEDER Tabelle stehen würde.
      if (e.code == 'CC001') {
        throw const CommunityChatServiceException(
          'Communities erstellen ist ab Premium verfügbar. Jetzt upgraden.',
        );
      }
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> joinCommunity(String communityId) async {
    final uid = _userId;
    if (uid == null) {
      throw const CommunityChatServiceException('Bitte melde dich an.');
    }

    try {
      await _db.from('community_members').insert({
        'community_id': communityId,
        'user_id': uid,
        'role': 'member',
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') return;
      if (e.code == '42501') {
        throw const CommunityChatServiceException(
          'Diese Community ist privat. Nutze den Invite-Code vom Leader.',
        );
      }
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<Map<String, dynamic>?> findCommunityByCode(
    String rawCode,
  ) async {
    final code = normalizeInviteCode(rawCode);
    if (code == null) return null;

    try {
      final row = await _db.rpc(
        'find_community_by_code',
        params: {'p_code': code},
      );
      if (row is Map) return Map<String, dynamic>.from(row);
      return null;
    } catch (e) {
      debugPrint('[CommunityChatService] find_community_by_code Fehler: $e');
      return null;
    }
  }

  /// 2026-08-23 (Entscheidung Vucko, bindend): „Wechselt eine Community von
  /// öffentlich auf privat, führt ein alter, schon geteilter Link NICHT mehr
  /// direkt hinein, sondern löst eine BEITRITTSANFRAGE beim Admin aus, die er
  /// annehmen oder ablehnen kann. Bestehende Mitglieder behalten ihren
  /// Zugang."
  ///
  /// Gemessen am 23.08.2026 war das Gegenteil der Fall: die alte RPC
  /// `join_community_with_code` (SECURITY DEFINER) las `is_public` an KEINER
  /// Stelle und trug direkt in `community_members` ein. Der Privat-Schalter
  /// war damit wirkungslos. Die neue RPC `join_community_with_code_v2` sagt
  /// zusätzlich, WAS passiert ist, damit hier der richtige Text erscheint.
  static Future<CommunityJoinResult> joinCommunityByCode(
    String rawCode,
  ) async {
    final code = normalizeInviteCode(rawCode);
    if (code == null) {
      throw const CommunityChatServiceException('Code ungültig.');
    }

    try {
      final result = await _db.rpc(
        'join_community_with_code_v2',
        params: {'p_code': code},
      );
      if (result is Map) {
        return CommunityJoinResult.fromJson(Map<String, dynamic>.from(result));
      }
      throw const CommunityChatServiceException(
        'Beitritt gerade nicht möglich. Bitte später erneut versuchen.',
      );
    } on PostgrestException catch (e) {
      // Eine Datenbank ohne die neue RPC darf nicht mit „function does not
      // exist" antworten — dann zählt der alte Weg, der wenigstens
      // öffentliche Communities öffnet.
      if (e.code == 'PGRST202' ||
          e.message.toLowerCase().contains('could not find the function')) {
        final id = await joinCommunityWithCode(rawCode);
        return CommunityJoinResult(
          communityId: id,
          status: CommunityJoinStatus.joined,
        );
      }
      throw CommunityChatServiceException(_lesbarerBeitrittsfehler(e));
    }
  }

  /// Die RPCs melden fachliche Fehler per `raise exception`. Der Text ist
  /// bereits deutsch, aber PostgREST hängt manchmal Zusätze an.
  static String _lesbarerBeitrittsfehler(PostgrestException e) {
    final message = e.message.trim();
    if (message.isEmpty) {
      return 'Beitritt gerade nicht möglich.';
    }
    if (message.toLowerCase().contains('code ung')) return 'Code ungültig.';
    if (message.length > 140) return 'Beitritt gerade nicht möglich.';
    return message;
  }

  /// Alter Weg, bleibt für den Rückfall auf Datenbanken ohne die neue RPC.
  static Future<String> joinCommunityWithCode(String rawCode) async {
    final code = normalizeInviteCode(rawCode);
    if (code == null) {
      throw const CommunityChatServiceException('Code ungültig.');
    }

    try {
      final result = await _db.rpc(
        'join_community_with_code',
        params: {'p_code': code},
      );
      return result as String;
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(_lesbarerBeitrittsfehler(e));
    }
  }

  static Future<Map<String, dynamic>> fetchCommunity(String communityId) async {
    dynamic row;
    try {
      row = await _db
          .from('communities')
          .select(_communitySelect)
          .eq('id', communityId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e)) rethrow;
      row = await _db
          .from('communities')
          .select(_legacyCommunitySelect)
          .eq('id', communityId)
          .maybeSingle();
    }
    if (row == null) {
      throw const CommunityChatServiceException(
        'Community wurde nicht gefunden.',
      );
    }
    return Map<String, dynamic>.from(row as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(
    String communityId,
  ) async {
    dynamic rows;
    try {
      rows = await _db
          .from('community_messages')
          .select(_messageSelect)
          .eq('community_id', communityId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: true)
          .limit(150);
    } on PostgrestException catch (e) {
      if (!_isMissingColumn(e)) rethrow;
      try {
        rows = await _db
            .from('community_messages')
            .select(_messageSelectWithoutPins)
            .eq('community_id', communityId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: true)
            .limit(150);
      } on PostgrestException catch (fallbackError) {
        if (!_isMissingColumn(fallbackError)) rethrow;
        rows = await _db
            .from('community_messages')
            .select(_legacyMessageSelect)
            .eq('community_id', communityId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: true)
            .limit(150);
      }
    }
    return (rows as List)
        .map(
          (row) => CommunityChatMessage.fromJson(
            Map<String, dynamic>.from(row as Map),
          ).toJson(),
        )
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> fetchMembers(
    String communityId,
  ) async {
    final rows = await _db
        .from('community_members')
        .select(_memberSelect)
        .eq('community_id', communityId)
        .order('role', ascending: true)
        .order('created_at', ascending: true);
    final list = List<Map<String, dynamic>>.from(rows as List);
    list.sort((a, b) {
      final rankA = _roleSortRank(a['role']?.toString());
      final rankB = _roleSortRank(b['role']?.toString());
      if (rankA != rankB) return rankA.compareTo(rankB);
      final nameA = displayName(_memberProfile(a)).toLowerCase();
      final nameB = displayName(_memberProfile(b)).toLowerCase();
      return nameA.compareTo(nameB);
    });
    return list;
  }

  static int _roleSortRank(String? role) {
    switch (role) {
      case 'owner':
        return 0;
      case 'moderator':
        return 1;
      default:
        return 2;
    }
  }

  static Map<String, dynamic>? _memberProfile(Map<String, dynamic> member) {
    final profile = member['profiles'];
    if (profile is Map) return Map<String, dynamic>.from(profile);
    return null;
  }

  static Future<void> setMemberRole({
    required String communityId,
    required String userId,
    required String role,
  }) async {
    try {
      await _db.rpc(
        'set_community_member_role',
        params: {
          'p_community_id': communityId,
          'p_user_id': userId,
          'p_role': role,
        },
      );
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> removeMember({
    required String communityId,
    required String userId,
  }) async {
    try {
      await _db.rpc(
        'remove_community_member',
        params: {'p_community_id': communityId, 'p_user_id': userId},
      );
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> deleteCommunity(String communityId) async {
    try {
      await _db.rpc(
        'delete_community',
        params: {'p_community_id': communityId},
      );
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> setOwnerOnlyMessages({
    required String communityId,
    required bool enabled,
  }) async {
    try {
      await _db
          .from('communities')
          .update({'owner_only_messages': enabled})
          .eq('id', communityId);
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  /// 2026-07-13 (vucko): Owner kann seine Community nachträglich zwischen
  /// privat und öffentlich umschalten. `.select('id')` holt die geänderte
  /// Zeile zurück — ein leeres Ergebnis heißt: RLS hat blockiert (kein Owner)
  /// → ehrlicher Fehler statt stillem Fehlschlag (Muster wie Foto-Update).
  static Future<void> setCommunityVisibility({
    required String communityId,
    required bool isPublic,
  }) async {
    try {
      final rows = await _db
          .from('communities')
          .update({'is_public': isPublic})
          .eq('id', communityId)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const CommunityChatServiceException(
          'Nur der Owner kann die Sichtbarkeit ändern.',
        );
      }
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// 2026-08-23 (Auftrag Vucko, Sprachnachricht): Name und Beschreibung waren
  /// nach dem Anlegen ÜBERHAUPT NICHT mehr änderbar — im ganzen Repo gab es
  /// keinen einzigen Aufruf, der `communities.name` oder `.description`
  /// aktualisiert. Das fällt sofort auf, sobald es eine Einstellungs-Seite
  /// gibt, also kommt es hier mit dazu.
  ///
  /// `.select('id')` holt die geänderte Zeile zurück: eine leere Antwort
  /// heißt, die Regel `leaders_update_communities` hat blockiert (kein Admin).
  /// Gleiches Muster wie [setCommunityVisibility].
  static Future<void> updateCommunityProfile({
    required String communityId,
    required String name,
    String? description,
  }) async {
    final cleanName = name.trim();
    final cleanDescription = description?.trim();
    if (cleanName.isEmpty ||
        cleanName.length > AppInputLimits.communityNameMaxLength) {
      throw const CommunityChatServiceException('Community-Name ist ungültig.');
    }
    if ((cleanDescription?.length ?? 0) >
        AppInputLimits.communityDescriptionMaxLength) {
      throw const CommunityChatServiceException(
        'Community-Beschreibung ist zu lang.',
      );
    }

    try {
      final rows = await _db
          .from('communities')
          .update({
            'name': cleanName,
            'description': cleanDescription == null || cleanDescription.isEmpty
                ? null
                : cleanDescription,
          })
          .eq('id', communityId)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const CommunityChatServiceException(
          'Nur Admins können Name und Beschreibung ändern.',
        );
      }
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  /// Speichert die Bild-URL an der Community. Wird NACH dem erfolgreichen
  /// Hochladen aufgerufen; `null` entfernt das Bild wieder.
  static Future<void> setCommunityAvatarUrl({
    required String communityId,
    required String? avatarUrl,
  }) async {
    try {
      final rows = await _db
          .from('communities')
          .update({'avatar_url': avatarUrl})
          .eq('id', communityId)
          .select('id');
      if ((rows as List).isEmpty) {
        throw const CommunityChatServiceException(
          'Nur Admins können das Community-Bild ändern.',
        );
      }
    } on PostgrestException catch (e) {
      // Eine alte Datenbank ohne die Spalte darf keine rohe Ausnahme zeigen.
      if (_isMissingColumn(e)) {
        throw const CommunityChatServiceException(
          'Community-Bilder sind in der Datenbank noch nicht aktiv.',
        );
      }
      throw CommunityChatServiceException(e.message);
    }
  }

  /// 2026-08-23: Der Einladungscode kommt NICHT mehr aus der Spalte, sondern
  /// über eine RPC, die nur Mitgliedern antwortet. Grund steht bei
  /// [_communitySelect]: die Spalte war für jeden angemeldeten Nutzer jeder
  /// öffentlichen Community lesbar, damit war der Privat-Schalter wertlos.
  static Future<String?> inviteCodeFor(String communityId) async {
    try {
      final code = await _db.rpc(
        'get_community_invite_code',
        params: {'p_community_id': communityId},
      );
      final text = code?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (e) {
      debugPrint('[CommunityChatService] get_community_invite_code Fehler: $e');
      return null;
    }
  }

  /// Offene Beitrittsanfragen für einen Admin. Ohne diese Liste versanden die
  /// Anfragen, die seit dem 23.08.2026 entstehen, wenn jemand mit einem alten
  /// Link in eine inzwischen private Community will.
  static Future<List<Map<String, dynamic>>> fetchJoinRequests(
    String communityId,
  ) async {
    try {
      final rows = await _db.rpc(
        'get_community_join_requests',
        params: {'p_community_id': communityId},
      );
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (e) {
      debugPrint('[CommunityChatService] Beitrittsanfragen Fehler: $e');
      return const [];
    }
  }

  static Future<void> acceptJoinRequest(String requestId) async {
    try {
      await _db.rpc(
        'accept_community_join_request',
        params: {'req_id': requestId},
      );
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(_joinRequestError(e));
    }
  }

  static Future<void> rejectJoinRequest(String requestId) async {
    try {
      await _db.rpc(
        'reject_community_join_request',
        params: {'req_id': requestId},
      );
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(_joinRequestError(e));
    }
  }

  /// Die beiden RPCs werfen englische Entwicklertexte („request is not
  /// pending"). Die dürfen so nie im Toast landen.
  static String _joinRequestError(PostgrestException e) {
    final lower = e.message.toLowerCase();
    if (lower.contains('not pending')) {
      return 'Diese Anfrage wurde schon beantwortet.';
    }
    if (lower.contains('not found')) {
      return 'Diese Anfrage gibt es nicht mehr.';
    }
    if (lower.contains('leaders')) {
      return 'Nur Admins können Beitrittsanfragen beantworten.';
    }
    return 'Anfrage konnte nicht beantwortet werden.';
  }

  static Future<void> sendMessage(
    String communityId,
    String body, {
    String? replyToMessageId,
    Map<String, dynamic>? routeAttachment,
  }) async {
    final uid = _userId;
    if (uid == null) {
      throw const CommunityChatServiceException('Bitte melde dich an.');
    }
    final cleanBody = body.trim();
    if (cleanBody.isEmpty) return;
    if (cleanBody.length > AppInputLimits.communityMessageMaxLength) {
      throw const CommunityChatServiceException('Nachricht ist zu lang.');
    }
    final routeId = routeAttachment?['route_id']?.toString().trim();
    if (routeId != null && routeId.isNotEmpty) {
      final alreadyPosted = await hasOwnRoutePostForCommunity(
        communityId: communityId,
        routeId: routeId,
      );
      if (alreadyPosted) {
        throw const CommunityChatServiceException(duplicateRoutePostMessage);
      }
    }

    try {
      final payload = <String, dynamic>{
        'community_id': communityId,
        'user_id': uid,
        'body': cleanBody,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (routeAttachment != null) 'route_attachment': routeAttachment,
      };
      try {
        await _db.from('community_messages').insert(payload);
      } on PostgrestException catch (e) {
        if (_isMissingColumn(e) && routeAttachment != null) {
          throw const CommunityChatServiceException(
            'Routen-Anhänge sind in Supabase noch nicht aktiv.',
          );
        }
        if (e.code == '23505') {
          throw const CommunityChatServiceException(duplicateRoutePostMessage);
        }
        if (!_isMissingColumn(e)) rethrow;
        payload
          ..remove('reply_to_message_id')
          ..remove('route_attachment');
        await _db.from('community_messages').insert(payload);
      }
    } on PostgrestException catch (e) {
      // 2026-08-23 (Auftrag Vucko): Der einzige Fall, in dem 42501 hier
      // auftreten kann, der den Nutzer wirklich betrifft, ist der gesperrte
      // Schreibmodus. Gemessen an der Regel `members_write_community_messages`:
      // sie lässt im nur-Admin-Modus nur `owner` und `moderator` durch.
      // Postgres schickt dazu „new row violates row-level security policy" —
      // und genau das filtert `_friendlyError` als Rauschen weg. Deshalb wird
      // hier nachgeschaut und ein BENANNTER Fehler geworfen. Vorher las das
      // Mitglied nur „Nachricht konnte nicht gesendet werden." und schrieb
      // seinen langen Beitrag ein zweites Mal.
      if (e.code == '42501' && await isWriteLocked(communityId)) {
        throw const CommunityChatServiceException(
          writeLockedMessage,
          code: writeLockedCode,
        );
      }
      throw CommunityChatServiceException(e.message);
    }
  }

  /// Prüft frisch an der Datenbank, ob der Schreibmodus gerade gesperrt ist
  /// UND die eigene Rolle nicht schreiben darf. Absichtlich eine eigene,
  /// kleine Abfrage statt eines Blicks in den zwischengespeicherten Zustand:
  /// wer den Chat offen hat, während der Admin umschaltet, hat einen
  /// veralteten Stand — genau das war der gemessene Mangel.
  static Future<bool> isWriteLocked(String communityId) async {
    final uid = _userId;
    if (uid == null) return false;
    try {
      final community = await _db
          .from('communities')
          .select('owner_only_messages')
          .eq('id', communityId)
          .maybeSingle();
      if (community == null) return false;
      if (community['owner_only_messages'] != true) return false;

      final membership = await _db
          .from('community_members')
          .select('role')
          .eq('community_id', communityId)
          .eq('user_id', uid)
          .maybeSingle();
      return !canModerate(membership?['role']?.toString());
    } catch (e) {
      debugPrint('[CommunityChatService] Schreibmodus-Prüfung Fehler: $e');
      return false;
    }
  }

  static Future<bool> hasOwnRoutePostForCommunity({
    required String communityId,
    required String routeId,
  }) async {
    final uid = _userId;
    final cleanedCommunityId = communityId.trim();
    final cleanedRouteId = routeId.trim();
    if (uid == null || cleanedCommunityId.isEmpty || cleanedRouteId.isEmpty) {
      return false;
    }

    try {
      final rows = await _db
          .from('community_messages')
          .select('id')
          .eq('community_id', cleanedCommunityId)
          .eq('user_id', uid)
          .isFilter('deleted_at', null)
          .filter('route_attachment->>route_id', 'eq', cleanedRouteId)
          .limit(1);
      return (rows as List).isNotEmpty;
    } on PostgrestException catch (e) {
      if (_isMissingColumn(e)) return false;
      rethrow;
    }
  }

  static Future<void> deleteMessage(String messageId) async {
    try {
      await _db
          .from('community_messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', messageId);
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> setMessagePinned({
    required String messageId,
    required bool pinned,
  }) async {
    try {
      await _db.rpc(
        'set_community_message_pinned',
        params: {'p_message_id': messageId, 'p_pinned': pinned},
      );
    } on PostgrestException catch (e) {
      if (_isMissingColumn(e) || e.message.contains('function')) {
        throw const CommunityChatServiceException(
          'Pin-Funktion ist in der Datenbank noch nicht aktiv.',
        );
      }
      throw CommunityChatServiceException(e.message);
    }
  }

  static Future<void> leaveCommunity(String communityId) async {
    try {
      await _db.rpc('leave_community', params: {'p_community_id': communityId});
    } on PostgrestException catch (e) {
      throw CommunityChatServiceException(e.message);
    }
  }

  /// Emoji-Reaktion setzen (idempotent — doppeltes Setzen ist ein No-Op).
  /// Gespiegelt von GroupChatService.addReaction.
  static Future<void> addReaction(String messageId, String emoji) async {
    // 2026-07-23 (vucko "nur Emoji, kein Text bei Reaktionen"): Defense in
    // Depth auf Service-Ebene — die UI filtert schon, aber falls ein
    // künftiger Aufrufer diese Prüfung umgeht, greift sie hier nochmal.
    if (!EmojiGuard.isSingleEmoji(emoji)) return;
    final uid = _userId;
    if (uid == null) return;
    await _db.from('community_message_reactions').upsert(
      {'message_id': messageId, 'user_id': uid, 'emoji': emoji},
      onConflict: 'message_id,user_id,emoji',
      ignoreDuplicates: true,
    );
  }

  /// Eigene Emoji-Reaktion entfernen.
  static Future<void> removeReaction(String messageId, String emoji) async {
    final uid = _userId;
    if (uid == null) return;
    await _db
        .from('community_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', uid)
        .eq('emoji', emoji);
  }

  static RealtimeChannel subscribeMessages(
    String communityId,
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final channel = _db.channel('community_messages_$communityId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'community_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'community_id',
        value: communityId,
      ),
      callback: (_) => onChange(),
    );
    // Reaktionen haben kein community_id → kein Spalten-Filter möglich; RLS
    // liefert per Realtime nur Reaktionen aus den eigenen Communities aus,
    // also unkritisch (gespiegelt von GroupChatService.subscribeMessages).
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'community_message_reactions',
      callback: (_) => onChange(),
    );
    channel.subscribe(onStatus);
    return channel;
  }

  /// 2026-08-23 (Auftrag Vucko): Wer den Chat offen hat, merkte vom
  /// Umschalten NICHTS. Gemessen: `subscribeMessages` und `subscribeMembers`
  /// horchen auf `community_messages` und `community_members`, aber nie auf
  /// `communities` — obwohl die Tabelle in der Publikation
  /// `supabase_realtime` liegt (am 23.08.2026 nachgesehen). Folge: ein
  /// Mitglied tippte im nur-Admin-Modus einen langen Beitrag und bekam erst
  /// beim Senden „Nachricht konnte nicht gesendet werden."
  static RealtimeChannel subscribeCommunity(
    String communityId,
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final channel = _db.channel('community_row_$communityId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'communities',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: communityId,
      ),
      callback: (_) => onChange(),
    );
    channel.subscribe(onStatus);
    return channel;
  }

  static RealtimeChannel subscribeMembers(
    String communityId,
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final channel = _db.channel('community_members_$communityId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'community_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'community_id',
        value: communityId,
      ),
      callback: (_) => onChange(),
    );
    channel.subscribe(onStatus);
    return channel;
  }
}
