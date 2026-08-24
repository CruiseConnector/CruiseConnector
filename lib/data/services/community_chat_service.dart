import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/emoji_guard.dart';
import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
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

  /// ACHTUNG fuer spaeter: das Leserecht auf `community_messages` ist seit der
  /// Migration 20260824160000 SPALTENWEISE. Jede neue Spalte braucht ein
  /// eigenes `grant select` — sonst meldet PostgREST „permission denied" statt
  /// „column does not exist", und der [_isMissingColumn]-Rueckfall greift NICHT.
  static const String _messageSelect =
      'id, community_id, user_id, body, created_at, updated_at, deleted_at, '
      'reply_to_message_id, route_attachment, pinned_at, pinned_by, '
      'bearbeitet_am, '
      'profiles:user_id(id, username, avatar_url), '
      'community_message_reactions(emoji, user_id)';

  /// Stand VOR der Migration 20260824160000 (kein `bearbeitet_am`).
  static const String _messageSelectOhneBearbeitet =
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

  /// 2026-08-24 (Aufgabe 1.2, Aufnahme 1 [00:44]): „wenn eine Community
  /// jünger als sieben Tage ist, dass da drunter dann ‚neu' steht oder halt
  /// ‚vor kurzem erstellt'".
  ///
  /// Liest das Gründungsdatum aus einer Community-Zeile. `created_at` ist
  /// bereits in allen drei Quellen enthalten (`_communitySelect`,
  /// `_legacyCommunitySelect` und der RPC `find_community_by_code`, die es
  /// in Migration 20260823123000 ausdrücklich mitgibt) — es braucht also
  /// KEINE zusätzliche Abfrage.
  ///
  /// Der Wert kommt von PostgREST als ISO-Zeichenkette mit Zeitzone.
  /// [DateTime.tryParse] ergibt daraus eine UTC-Zeit; verglichen wird
  /// deshalb konsequent in UTC, sonst verschiebt die Gerätezeitzone die
  /// 7-Tage-Grenze um bis zu einen halben Tag.
  static DateTime? createdAt(Map<String, dynamic>? community) {
    final raw = community?['created_at'];
    if (raw is DateTime) return raw.toUtc();
    final text = raw?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  /// Wie lange eine Community als „vor kurzem erstellt" gilt.
  static const Duration neuFenster = Duration(days: 7);

  /// 2026-08-24 (Aufgabe 1.2): true, solange die Community jünger als
  /// [neuFenster] ist.
  ///
  /// Die Grenze liegt EXAKT bei 7 Tagen (Akzeptanzkriterium 3: „nicht bei 6
  /// oder 8"): bei genau 7 Tagen Alter ist das Label WEG. Gemessen am
  /// 24.08.2026 trügen 4 von 6 Communities das Label, eine fällt in rund
  /// 18 Stunden heraus.
  ///
  /// Ohne verwertbares Datum wird bewusst `false` geliefert: lieber kein
  /// Label als ein falsches. [jetzt] ist nur für den Test da.
  static bool istVorKurzemErstellt(
    Map<String, dynamic>? community, {
    DateTime? jetzt,
  }) {
    final erstellt = createdAt(community);
    if (erstellt == null) return false;
    final referenz = (jetzt ?? DateTime.now()).toUtc();
    final alter = referenz.difference(erstellt);
    // Ein Datum in der Zukunft (Uhr des Geräts geht nach) zählt als neu,
    // nicht als uralt. isNegative faengt genau diesen Fall ab.
    if (alter.isNegative) return true;
    return alter < neuFenster;
  }

  /// 2026-08-24 — Aufgabe 10b aus dem Nachtrag vom 24.08.
  ///
  /// Vucko: „und wie gesagt ein badge in der community wo man sieht wann es
  /// gegruendet wurde."
  ///
  /// Nicht zu verwechseln mit dem Etikett „Vor kurzem erstellt" aus Aufgabe
  /// 1.2: Das eine sagt „jünger als 7 Tage" und steht in der LISTE, das hier
  /// zeigt IMMER das Datum und steht IN der Community. Und es ist auch nicht
  /// das Erfolgs-Abzeichen für das Gründen einer Community — das liegt in
  /// `badge.dart` und wird woanders gebaut.
  ///
  /// Das Gründungsdatum ist `communities.created_at`. Die Spalte
  /// `founder_id` aus Migration 20260824103000 wird hier bewusst NICHT
  /// gelesen: Sie steht nicht in [_communitySelect], und das Leserecht auf
  /// `communities` ist seit dem 23.08. spaltenweise vergeben — jede neue
  /// Spalte bräuchte ihr eigenes `grant select`. Vucko hat nach dem WANN
  /// gefragt, nicht nach dem WER.
  ///
  /// Angezeigt wird in Ortszeit. Ein Gründungsdatum ist ein Kalendertag, kein
  /// Zeitpunkt; in UTC stünde bei einer Gründung um 01:00 Uhr der Vortag da.
  static String? gruendungsdatumText(Map<String, dynamic>? community) {
    final erstellt = createdAt(community)?.toLocal();
    if (erstellt == null) return null;
    final tt = erstellt.day.toString().padLeft(2, '0');
    final mm = erstellt.month.toString().padLeft(2, '0');
    return 'Gegründet am $tt.$mm.${erstellt.year}';
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

  /// Die Auswahllisten in absteigender Vollstaendigkeit. Faellt eine Spalte
  /// weg (aeltere Datenbank), wird die naechste probiert.
  static const List<String> _messageSelectStufen = <String>[
    _messageSelect,
    _messageSelectOhneBearbeitet,
    _messageSelectWithoutPins,
    _legacyMessageSelect,
  ];

  /// Holt die Nachrichten einer Community.
  ///
  /// 2026-08-24 (Auftrag Vucko): Es kommen jetzt ZWEI Listen zurueck, in einer
  /// zusammengefuehrt.
  ///
  ///  1. Die lebenden Nachrichten, wie bisher.
  ///  2. Die HUELLEN der fuer alle geloeschten — nur Kennung, Verfasser und
  ///     Zeitpunkt, damit die Oberflaeche „Diese Nachricht wurde geloescht."
  ///     an der richtigen Stelle zeigen kann, statt dass eine Antwort ins
  ///     Leere verweist.
  ///
  /// WARUM EINE ZWEITE, SCHMALE ABFRAGE und nicht einfach der Filter weg:
  /// `deleted_at` zu setzen loescht den Text NICHT, `body` steht weiter in der
  /// Zeile und ist fuer jedes Mitglied lesbar. Wuerde hier der Filter
  /// wegfallen, laege der Text jeder geloeschten Nachricht wieder auf dem
  /// Geraet — „fuer alle geloescht" waere ein Etikett ohne Wirkung. Die
  /// Huellen-Abfrage fragt `body` gar nicht erst ab.
  static Future<List<Map<String, dynamic>>> fetchMessages(
    String communityId,
  ) async {
    dynamic rows;
    PostgrestException? letzterFehler;
    for (final auswahl in _messageSelectStufen) {
      try {
        rows = await _db
            .from('community_messages')
            .select(auswahl)
            .eq('community_id', communityId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: true)
            .limit(150);
        letzterFehler = null;
        break;
      } on PostgrestException catch (e) {
        letzterFehler = e;
        if (!_isMissingColumn(e)) rethrow;
      }
    }
    if (letzterFehler != null) throw letzterFehler;

    final lebendig = (rows as List).map((row) {
      final roh = Map<String, dynamic>.from(row as Map);
      final karte = CommunityChatMessage.fromJson(roh).toJson();
      // `CommunityChatMessage` kennt `bearbeitet_am` nicht und wuerde es beim
      // Umweg ueber toJson() verlieren. Das Modell gehoert einem anderen
      // Auftrag, deshalb wird der Wert hier zurueckgelegt.
      if (roh.containsKey('bearbeitet_am')) {
        karte['bearbeitet_am'] = roh['bearbeitet_am'];
      }
      return karte;
    }).toList();

    final huellen = await _fetchGeloeschteHuellen(communityId);
    if (huellen.isEmpty) return List<Map<String, dynamic>>.unmodifiable(lebendig);

    final zusammen = <Map<String, dynamic>>[...lebendig, ...huellen]
      ..sort((a, b) {
        final az =
            DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bz =
            DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return az.compareTo(bz);
      });
    return List<Map<String, dynamic>>.unmodifiable(zusammen);
  }

  /// Die Huellen der fuer alle geloeschten Nachrichten. OHNE `body` — siehe
  /// die Begruendung in [fetchMessages].
  static Future<List<Map<String, dynamic>>> _fetchGeloeschteHuellen(
    String communityId,
  ) async {
    try {
      final rows = await _db
          .from('community_messages')
          .select(
            'id, community_id, user_id, created_at, deleted_at, '
            'reply_to_message_id, profiles:user_id(id, username, avatar_url)',
          )
          .eq('community_id', communityId)
          .not('deleted_at', 'is', null)
          .order('created_at', ascending: true)
          .limit(150);
      return [
        for (final row in rows as List)
          if (row is Map)
            <String, dynamic>{
              ...Map<String, dynamic>.from(row),
              'body': '',
              '_geloescht': true,
            },
      ];
    } catch (e) {
      debugPrint('[CommunityChatService] Geloeschte Huellen lesen: $e');
      return const [];
    }
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

  // --------------------------------------------------------------------------
  // 2026-08-24 (Auftrag Vucko): bearbeiten, löschen, Verlauf, Chat-Art
  // --------------------------------------------------------------------------

  /// Die Frist, innerhalb derer eine eigene Nachricht bearbeitet werden darf.
  ///
  /// DIESE KONSTANTE SETZT NICHTS DURCH. Sie ist die Kopie der Frist, die im
  /// Trigger `trg_wacht_ueber_community_nachricht` steht, damit die Oberfläche
  /// „noch 4 Std. 12 Min." anzeigen kann. Wer sie hier ändert, ändert nur den
  /// Text — die Datenbank lehnt weiterhin nach sechs Stunden ab.
  static const Duration bearbeitungsfrist = Duration(hours: 6);

  /// Benannter Grund, damit [CommunityChatServiceException] durch den
  /// Rauschfilter der Oberfläche kommt (siehe [writeLockedCode]). Die
  /// Ablehnungen der Datenbank („Frist abgelaufen") sind fachliche Antworten
  /// und dürfen NIE als „Aktion gerade nicht möglich." verschluckt werden.
  static const String nachrichtAbgelehntCode = 'CC003';

  /// Wie lange noch bearbeitet werden darf.
  ///
  /// `null` heißt „unbekannt": entweder fehlt der Zeitstempel oder es wurde
  /// noch keine Serverzeit gemessen. Der Aufrufer zeigt dann keine Frist an
  /// und lässt den Bearbeiten-Eintrag trotzdem stehen — die Datenbank
  /// entscheidet.
  static Duration? verbleibendeBearbeitungszeit({
    required DateTime? erstelltAm,
    required DateTime? serverJetzt,
  }) {
    if (erstelltAm == null || serverJetzt == null) return null;
    final rest =
        bearbeitungsfrist - serverJetzt.toUtc().difference(erstelltAm.toUtc());
    return rest.isNegative ? Duration.zero : rest;
  }

  /// Darf diese Nachricht gerade bearbeitet werden?
  ///
  /// Bewusst großzügig bei [verbleibend] == null: ohne gemessene Serverzeit
  /// wird der Eintrag angeboten und der Server lehnt gegebenenfalls mit einer
  /// ehrlichen Meldung ab. Der umgekehrte Fehler wäre schlimmer — ein Nutzer,
  /// dem die Bearbeitung genommen wird, weil sein Handy falsch geht.
  static bool darfBearbeiten({
    required bool istEigene,
    required bool istGeloescht,
    required bool istUnterwegs,
    required Duration? verbleibend,
  }) {
    if (!istEigene || istGeloescht || istUnterwegs) return false;
    if (verbleibend == null) return true;
    return verbleibend > Duration.zero;
  }

  /// „Noch 4 Std. 12 Min." — ohne Gedankenstriche, mit echten Umlauten.
  static String fristText(Duration verbleibend) {
    if (verbleibend <= Duration.zero) return 'Frist abgelaufen';
    if (verbleibend.inHours >= 1) {
      final minuten = verbleibend.inMinutes % 60;
      return minuten == 0
          ? 'Noch ${verbleibend.inHours} Std. bearbeitbar'
          : 'Noch ${verbleibend.inHours} Std. $minuten Min. bearbeitbar';
    }
    if (verbleibend.inMinutes >= 1) {
      return 'Noch ${verbleibend.inMinutes} Min. bearbeitbar';
    }
    return 'Noch ${verbleibend.inSeconds} Sek. bearbeitbar';
  }

  /// Übersetzt die Ablehnungen der Datenbank in Sätze mit echten Umlauten.
  ///
  /// Die Meldungen der Migration 20260824160000 sind bewusst ohne Umlaute
  /// geschrieben (SQL-Datei). Angezeigt wird in dieser App aber mit Umlauten,
  /// also werden die bekannten Fälle hier umgesetzt. Ein unbekannter Fall
  /// fällt auf einen ehrlichen Sammelsatz zurück, statt Postgres-Rohtext zu
  /// zeigen.
  static String _lesbareNachrichtenmeldung(
    PostgrestException e, {
    required String rueckfall,
  }) {
    final roh = e.message;
    if (roh.contains('Bearbeitungsfrist')) {
      return 'Die Bearbeitungsfrist von 6 Stunden ist abgelaufen.';
    }
    if (roh.contains('geloeschte Nachricht')) {
      return 'Eine gelöschte Nachricht kann nicht mehr bearbeitet werden.';
    }
    if (roh.contains('Verfasser kann seine Nachricht')) {
      return 'Nur der Verfasser kann seine Nachricht bearbeiten.';
    }
    if (roh.contains('Verfasser oder ein Admin')) {
      return 'Nur der Verfasser oder ein Admin kann diese Nachricht für alle löschen.';
    }
    if (roh.contains('darf nicht leer sein')) {
      return 'Die Nachricht darf nicht leer sein.';
    }
    if (roh.contains('zu lang')) return 'Nachricht ist zu lang.';
    if (roh.contains('nicht gefunden')) return 'Nachricht nicht gefunden.';
    if (roh.contains('melde dich an')) return 'Bitte melde dich an.';
    return rueckfall;
  }

  static bool _funktionFehlt(PostgrestException e) {
    final text = e.message.toLowerCase();
    return _isMissingColumn(e) ||
        text.contains('function') ||
        text.contains('schema cache');
  }

  /// Bearbeitet die eigene Nachricht. Die Frist setzt die Datenbank durch.
  ///
  /// Rückgabe: der Zeitpunkt der Bearbeitung, wie ihn die Datenbank gesetzt
  /// hat. Er ist ein echter Serverzeitstempel und wird gleich benutzt, um den
  /// Versatz der [Serverzeit] nachzuziehen — so wird die angezeigte Frist mit
  /// jeder Bearbeitung genauer, ohne einen zusätzlichen Aufruf.
  static Future<DateTime?> editMessage({
    required String messageId,
    required String body,
  }) async {
    final sauber = body.trim();
    if (sauber.isEmpty) {
      throw const CommunityChatServiceException(
        'Die Nachricht darf nicht leer sein.',
        code: nachrichtAbgelehntCode,
      );
    }
    if (sauber.length > AppInputLimits.communityMessageMaxLength) {
      throw const CommunityChatServiceException(
        'Nachricht ist zu lang.',
        code: nachrichtAbgelehntCode,
      );
    }
    try {
      final antwort = await _db.rpc(
        'community_nachricht_bearbeiten',
        params: {'p_message_id': messageId, 'p_body': sauber},
      );
      final zeit = DateTime.tryParse(antwort?.toString() ?? '')?.toUtc();
      if (zeit != null) Serverzeit.merkeServerzeit(zeit);
      return zeit;
    } on PostgrestException catch (e) {
      if (_funktionFehlt(e)) {
        throw const CommunityChatServiceException(
          'Bearbeiten ist in der Datenbank noch nicht aktiv.',
          code: nachrichtAbgelehntCode,
        );
      }
      throw CommunityChatServiceException(
        _lesbareNachrichtenmeldung(
          e,
          rueckfall: 'Nachricht konnte nicht bearbeitet werden.',
        ),
        code: nachrichtAbgelehntCode,
      );
    }
  }

  /// Löscht eine Nachricht — für alle oder nur für den Aufrufer.
  ///
  /// [fuerAlle] `true`  setzt `deleted_at` (Serverzeit, unbefristet, nur
  ///                    Verfasser oder Moderation).
  /// [fuerAlle] `false` legt eine Zeile in `community_nachricht_ausgeblendet`
  ///                    an — am Konto, nicht am Gerät.
  ///
  /// Der alte Weg (direktes UPDATE mit `DateTime.now()` des Geräts) ist
  /// ersatzlos weg. Er war genau die Manipulierbarkeit, die Vucko
  /// ausschließen wollte. Der Rückfall unten schreibt zwar wieder direkt, aber
  /// nur auf einer Datenbank OHNE die Migration — dort gibt es die Frist
  /// ohnehin nicht.
  static Future<void> deleteMessage(
    String messageId, {
    required bool fuerAlle,
  }) async {
    try {
      await _db.rpc(
        'community_nachricht_loeschen',
        params: {'p_message_id': messageId, 'p_fuer_alle': fuerAlle},
      );
    } on PostgrestException catch (e) {
      if (_funktionFehlt(e)) {
        if (!fuerAlle) {
          throw const CommunityChatServiceException(
            'Nur für mich löschen ist in der Datenbank noch nicht aktiv.',
            code: nachrichtAbgelehntCode,
          );
        }
        await _db
            .from('community_messages')
            .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', messageId);
        return;
      }
      throw CommunityChatServiceException(
        _lesbareNachrichtenmeldung(
          e,
          rueckfall: 'Nachricht konnte nicht gelöscht werden.',
        ),
        code: nachrichtAbgelehntCode,
      );
    }
  }

  /// Nimmt ein „nur für mich" zurück. Das ist die Rückgängig-Taste im Hinweis
  /// nach dem Ausblenden — deshalb darf sie nicht scheitern, ohne dass es
  /// jemand merkt.
  static Future<void> zeigeNachrichtWiederAn(String messageId) async {
    final uid = _userId;
    if (uid == null) return;
    await _db
        .from('community_nachricht_ausgeblendet')
        .delete()
        .eq('user_id', uid)
        .eq('message_id', messageId);
  }

  /// Die Kennungen der Nachrichten, die der Aufrufer „nur für mich" gelöscht
  /// hat. Schlägt die Abfrage fehl (alte Datenbank, kein Netz), kommt eine
  /// leere Menge zurück: dann sieht man eine Nachricht wieder, die man
  /// weggeräumt hatte. Das ist der harmlosere der beiden Fehler — die
  /// Gegenrichtung wäre, Nachrichten stumm zu verstecken.
  static Future<Set<String>> fetchAusgeblendeteIds(String communityId) async {
    final uid = _userId;
    if (uid == null) return <String>{};
    try {
      final rows = await _db
          .from('community_nachricht_ausgeblendet')
          .select('message_id')
          .eq('user_id', uid)
          .eq('community_id', communityId);
      return {
        for (final row in rows as List)
          if (row is Map && row['message_id'] != null)
            row['message_id'].toString(),
      };
    } catch (e) {
      debugPrint('[CommunityChatService] Ausgeblendete lesen fehlgeschlagen: $e');
      return <String>{};
    }
  }

  static const String _verlaufSelect =
      'id, community_id, user_id, art, ausgeloest_von, am, nachgetragen, '
      'profiles:user_id(id, username, avatar_url)';

  /// Wer kam und wer ging (Tabelle `community_mitglieder_verlauf`).
  ///
  /// Die Tabelle ist nur lesbar, geschrieben wird ausschließlich vom Trigger
  /// `trg_community_mitgliedschaft_protokoll`. Fehlt sie (alte Datenbank),
  /// kommt eine leere Liste — der Chat sieht dann aus wie bisher.
  ///
  /// ZWEI WEGE, weil es zwei Fremdschlüssel auf `profiles` gibt (`user_id`
  /// und `ausgeloest_von`). Lehnt PostgREST das eingebettete Profil ab, holt
  /// der zweite Weg die Namen mit einer eigenen Abfrage nach. Ohne diesen
  /// Rückfall wäre der Verlauf im Fehlerfall STILL leer — und niemand würde
  /// merken, dass es an der Abfrage liegt und nicht daran, dass niemand
  /// beigetreten ist.
  static Future<List<Map<String, dynamic>>> fetchVerlauf(
    String communityId,
  ) async {
    List<Map<String, dynamic>> zeilen;
    try {
      final rows = await _db
          .from('community_mitglieder_verlauf')
          .select(_verlaufSelect)
          .eq('community_id', communityId)
          .order('am', ascending: true)
          .limit(300);
      return [
        for (final row in rows as List) Map<String, dynamic>.from(row as Map),
      ];
    } catch (e) {
      debugPrint(
        '[CommunityChatService] Verlauf mit Profil fehlgeschlagen, '
        'zweiter Weg: $e',
      );
    }
    try {
      final rows = await _db
          .from('community_mitglieder_verlauf')
          .select('id, community_id, user_id, art, ausgeloest_von, am, nachgetragen')
          .eq('community_id', communityId)
          .order('am', ascending: true)
          .limit(300);
      zeilen = [
        for (final row in rows as List) Map<String, dynamic>.from(row as Map),
      ];
    } catch (e) {
      debugPrint('[CommunityChatService] Verlauf lesen fehlgeschlagen: $e');
      return const [];
    }
    if (zeilen.isEmpty) return zeilen;
    try {
      final kennungen = <String>{
        for (final zeile in zeilen)
          if (zeile['user_id'] != null) zeile['user_id'].toString(),
      };
      final profile = await _db
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', kennungen.toList());
      final nachId = <String, Map<String, dynamic>>{
        for (final row in profile as List)
          if (row is Map && row['id'] != null)
            row['id'].toString(): Map<String, dynamic>.from(row),
      };
      for (final zeile in zeilen) {
        final profil = nachId[zeile['user_id']?.toString()];
        if (profil != null) zeile['profiles'] = profil;
      }
    } catch (e) {
      debugPrint('[CommunityChatService] Verlaufs-Namen nachladen: $e');
    }
    return zeilen;
  }

  /// Ein Beitritt soll sofort auftauchen, ohne dass jemand neu lädt. Die
  /// Tabelle liegt dafür in der Publikation `supabase_realtime`
  /// (Migration 20260824160000).
  static RealtimeChannel subscribeVerlauf(
    String communityId,
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    final channel = _db.channel('community_verlauf_$communityId');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'community_mitglieder_verlauf',
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

  /// Schlüssel des Spiegels in den SharedPreferences (kontogebunden, siehe
  /// [NutzerPrefsSchluessel]).
  static const String chatDarstellungPrefsBasis = 'community_chat_darstellung_v1';

  /// Ersetzbar, damit der Test ohne Supabase auskommt.
  @visibleForTesting
  static Future<ChatDarstellung?> Function()? chatDarstellungLeserFuerTests;

  /// Ersetzbar, damit der Test ohne Supabase auskommt.
  @visibleForTesting
  static Future<void> Function(ChatDarstellung art)?
  chatDarstellungSchreiberFuerTests;

  @visibleForTesting
  static void resetChatDarstellungFuerTests() {
    chatDarstellungLeserFuerTests = null;
    chatDarstellungSchreiberFuerTests = null;
  }

  /// Die zuletzt gewählte Darstellung, aus dem Gerätespiegel.
  ///
  /// WARUM ÜBERHAUPT EIN SPIEGEL, wenn der Wert am Konto steht: damit der Chat
  /// beim Öffnen SOFORT in der richtigen Art erscheint. Ohne ihn zeichnete die
  /// Seite erst die Beitragsansicht und klappte eine Zehntelsekunde später in
  /// die Nachrichten-Ansicht um. Der Spiegel ist die Anzeige, das Konto ist
  /// die Wahrheit.
  static Future<ChatDarstellung?> chatDarstellungVomGeraet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schluessel = NutzerPrefsSchluessel.fuer(chatDarstellungPrefsBasis);
      return ChatDarstellung.ausWert(prefs.getString(schluessel));
    } catch (e) {
      debugPrint('[CommunityChatService] Chat-Art vom Gerät lesen: $e');
      return null;
    }
  }

  /// Die Darstellung, wie sie am Konto steht (`profiles.chat_darstellung`).
  /// `null` = noch nie gewählt oder nicht lesbar.
  static Future<ChatDarstellung?> chatDarstellungVomKonto() async {
    final test = chatDarstellungLeserFuerTests;
    if (test != null) return test();
    final uid = _userId;
    if (uid == null) return null;
    try {
      final row = await _db
          .from('profiles')
          .select('chat_darstellung')
          .eq('id', uid)
          .maybeSingle();
      return ChatDarstellung.ausWert(row?['chat_darstellung']);
    } catch (e) {
      debugPrint('[CommunityChatService] Chat-Art vom Konto lesen: $e');
      return null;
    }
  }

  /// Merkt sich die Wahl — erst am Gerät (sofort wirksam), dann am Konto.
  ///
  /// Schlägt das Konto fehl (kein Netz), bleibt die Wahl trotzdem am Gerät
  /// stehen und der Neustart überlebt sie. Beim nächsten Umschalten mit Netz
  /// wandert sie hoch.
  static Future<void> merkeChatDarstellung(ChatDarstellung art) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final schluessel = NutzerPrefsSchluessel.fuer(chatDarstellungPrefsBasis);
      await prefs.setString(schluessel, art.wert);
    } catch (e) {
      debugPrint('[CommunityChatService] Chat-Art am Gerät merken: $e');
    }
    final test = chatDarstellungSchreiberFuerTests;
    if (test != null) {
      await test(art);
      return;
    }
    final uid = _userId;
    if (uid == null) return;
    try {
      await _db
          .from('profiles')
          .update({'chat_darstellung': art.wert})
          .eq('id', uid);
    } catch (e) {
      debugPrint('[CommunityChatService] Chat-Art am Konto merken: $e');
    }
  }

}

// ############################################################################
// 2026-08-24 (Auftrag Vucko): Chat-Art, Bearbeiten, Löschen, Verlauf
// ############################################################################

/// Die beiden Darstellungen des Community-Chats.
///
/// Vucko am 24.08.: „man soll die chat art optimieren koennen wie bspw. ob man
/// den standart chat oder einen Nachrichten Chat bevorzugt".
///
/// * [standard] — die Beitragsansicht, wie sie bis heute die einzige war:
///   breite Karten untereinander, Kopfzeile „r/Thema · Name · Uhrzeit",
///   Antwortzähler, eine Aktionsleiste unter jedem Beitrag. Das liest sich wie
///   ein Forum und ist gut, wenn wenige, längere Beiträge stehen.
/// * [nachrichten] — die Messenger-Ansicht: schmale Sprechblasen, eigene
///   rechts, fremde links, aufeinanderfolgende Beiträge derselben Person
///   zusammengefasst, Tagestrenner. Das ist gut, wenn viele kurze Zeilen
///   hin und her gehen.
///
/// Der Wert steht auf `profiles.chat_darstellung` (Migration 20260824160000),
/// also am KONTO und nicht am Gerät — die Wahl kommt aufs nächste Handy mit.
enum ChatDarstellung {
  standard('standard'),
  nachrichten('nachrichten');

  const ChatDarstellung(this.wert);

  /// Der Wert, wie er in der Datenbank steht (CHECK
  /// `profiles_chat_darstellung_chk`).
  final String wert;

  static ChatDarstellung? ausWert(Object? roh) {
    final text = roh?.toString();
    for (final art in ChatDarstellung.values) {
      if (art.wert == text) return art;
    }
    return null;
  }

  String get titel =>
      this == ChatDarstellung.standard ? 'Beiträge' : 'Nachrichten';
}

/// Die Uhr, die zählt.
///
/// Vucko am 24.08.: „und nicht durch zeit zurueckstellen oder datum
/// zurueckstellen irgendwie manipuliert werden kann".
///
/// DURCHGESETZT wird die 6-Stunden-Frist ausschließlich in der Datenbank
/// (Trigger `trg_wacht_ueber_community_nachricht`, Migration 20260824160000).
/// Diese Klasse ist NUR für die ANZEIGE da: „noch 4 Std. 12 Min. bearbeitbar".
/// Würde die Anzeige gegen `DateTime.now()` rechnen, zeigte ein verstelltes
/// Handy Unsinn an — mal „abgelaufen" bei einer frischen Nachricht, mal „noch
/// 5 Stunden" bei einer von gestern.
///
/// WOHER DIE SERVERZEIT KOMMT: aus dem `Date`-Kopf jeder HTTP-Antwort der
/// Supabase-Schnittstelle. Absichtlich kein neuer Aufruf in der Datenbank —
/// jede Antwort trägt den Zeitstempel ohnehin, und ein HEAD auf die REST-Wurzel
/// kostet keine Zeile und keine Rechte. Der Versatz wird EINMAL beim Öffnen
/// des Chats gemessen und danach jedes Mal nachgezogen, wenn die Datenbank
/// ohnehin einen echten Serverzeitstempel zurückgibt (siehe
/// [CommunityChatService.editMessage]).
///
/// IST DER VERSATZ UNBEKANNT, wird KEINE Frist angezeigt und der
/// Bearbeiten-Eintrag bleibt sichtbar. Lieber ein Angebot, das der Server
/// ablehnt (mit ehrlicher Meldung), als ein Eintrag, den eine falsche Uhr
/// vorschnell wegnimmt.
class Serverzeit {
  Serverzeit._();

  static Duration? _versatz;

  /// Ersetzbar, damit der Test ohne Netz auskommt.
  @visibleForTesting
  static Future<DateTime?> Function()? abfrageFuerTests;

  /// Ersetzbar, damit der Test die Geräteuhr selbst bestimmt.
  @visibleForTesting
  static DateTime Function()? geraetezeitFuerTests;

  @visibleForTesting
  static void resetForTests() {
    _versatz = null;
    abfrageFuerTests = null;
    geraetezeitFuerTests = null;
  }

  static DateTime _geraetezeit() =>
      (geraetezeitFuerTests?.call() ?? DateTime.now()).toUtc();

  /// `true`, sobald ein Serverzeitstempel gemessen wurde.
  static bool get istAbgeglichen => _versatz != null;

  /// Der aktuelle Zeitpunkt aus Sicht des Servers, oder `null`, solange
  /// niemand abgeglichen hat. `null` heißt ausdrücklich „ich weiß es nicht" —
  /// nicht „jetzt".
  static DateTime? get jetzt {
    final versatz = _versatz;
    if (versatz == null) return null;
    return _geraetezeit().add(versatz);
  }

  /// Merkt sich den Versatz aus einem bekannten Serverzeitpunkt.
  static void merkeServerzeit(DateTime serverzeit, {DateTime? gemessenAm}) {
    final bezug = (gemessenAm ?? _geraetezeit()).toUtc();
    _versatz = serverzeit.toUtc().difference(bezug);
  }

  /// Holt die Serverzeit aus dem `Date`-Kopf der REST-Schnittstelle.
  /// Liefert `true`, wenn danach ein Versatz bekannt ist.
  static Future<bool> abgleichen() async {
    final abfrage = abfrageFuerTests;
    if (abfrage != null) {
      final zeit = await abfrage();
      if (zeit == null) return false;
      merkeServerzeit(zeit);
      return true;
    }
    try {
      final rest = Supabase.instance.client.rest;
      final vorher = _geraetezeit();
      final antwort = await http
          .head(Uri.parse(rest.url), headers: rest.headers)
          .timeout(const Duration(seconds: 6));
      final roh = antwort.headers['date'];
      if (roh == null || roh.isEmpty) return false;
      final serverzeit = HttpDate.parse(roh).toUtc();
      final nachher = _geraetezeit();
      // Der Kopf entstand irgendwo zwischen Absenden und Empfang. Die halbe
      // Laufzeit ist die beste Schätzung, die ohne zweiten Aufruf zu haben
      // ist; sie liegt in der Praxis unter einer Sekunde und ist gegenüber
      // einer 6-Stunden-Frist bedeutungslos.
      final halbeLaufzeit = Duration(
        microseconds: nachher.difference(vorher).inMicroseconds ~/ 2,
      );
      merkeServerzeit(serverzeit.add(halbeLaufzeit), gemessenAm: nachher);
      return true;
    } catch (e) {
      debugPrint('[Serverzeit] Abgleich fehlgeschlagen: $e');
      return false;
    }
  }
}

/// Was in der Zeitleiste des Chats stehen kann.
enum ChatZeileArt {
  /// Eine echte Nachricht.
  nachricht,

  /// Eine für alle gelöschte Nachricht. Der Text ist NICHT dabei — der Client
  /// holt ihn gar nicht erst (siehe [CommunityChatService.fetchMessages]).
  geloescht,

  /// Eine oder mehrere Zu- oder Abgänge, zu einer Zeile zusammengefasst.
  verlauf,
}

/// Eine Zeile der Chat-Zeitleiste. Beide Darstellungen zeichnen dieselbe
/// Liste — deshalb liegt das Zusammenstellen hier und nicht in einem Widget.
class ChatZeile {
  const ChatZeile({
    required this.art,
    required this.zeit,
    this.nachricht,
    this.verlauf = const [],
    this.angepinnt = false,
  });

  final ChatZeileArt art;
  final DateTime zeit;
  final Map<String, dynamic>? nachricht;
  final List<Map<String, dynamic>> verlauf;
  final bool angepinnt;

  String? get id => art == ChatZeileArt.verlauf
      ? 'verlauf-${verlauf.isEmpty ? zeit.toIso8601String() : verlauf.first['id']}'
      : nachricht?['id']?.toString();
}

/// Stellt die Zeitleiste zusammen: Nachrichten, Grabsteine gelöschter
/// Nachrichten und die Zu- und Abgänge.
class CommunityChatTimeline {
  CommunityChatTimeline._();

  /// Ab wie vielen Namen eine Verlaufszeile zusammenfasst.
  ///
  /// Vucko: die Zu- und Abgänge „sollen den Verlauf zeigen, aber den Chat
  /// nicht dominieren". Deshalb werden AUFEINANDERFOLGENDE Ereignisse
  /// derselben Art zu EINER Zeile zusammengezogen. Treten an einem Tag zehn
  /// Leute bei, steht dort eine einzige graue Zeile statt zehn — und wer die
  /// Namen sehen will, tippt sie an.
  static const int namenImText = 3;

  static DateTime _zeitpunkt(Object? roh) =>
      DateTime.tryParse(roh?.toString() ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// Baut die Zeitleiste.
  ///
  /// [ausgeblendet] sind die Kennungen der Nachrichten, die der Aufrufer „nur
  /// für mich" gelöscht hat. Sie fallen restlos weg — auch der Grabstein.
  /// Genau das ist der Unterschied zu „für alle": bei „nur für mich" soll die
  /// Zeile weg sein, nicht durchgestrichen dastehen.
  ///
  /// [angepinntZuerst] gilt nur für die Beitragsansicht. Die
  /// Nachrichten-Ansicht ist streng chronologisch (alles andere fühlt sich in
  /// einem Messenger kaputt an); dort steht das Angepinnte in einem Band über
  /// der Liste.
  static List<ChatZeile> baue({
    required List<Map<String, dynamic>> nachrichten,
    required List<Map<String, dynamic>> verlauf,
    required Set<String> ausgeblendet,
    required bool angepinntZuerst,
  }) {
    final zeilen = <ChatZeile>[];

    for (final nachricht in nachrichten) {
      final id = nachricht['id']?.toString();
      if (id != null && ausgeblendet.contains(id)) continue;
      final istGeloescht =
          nachricht['_geloescht'] == true || nachricht['deleted_at'] != null;
      zeilen.add(
        ChatZeile(
          art: istGeloescht ? ChatZeileArt.geloescht : ChatZeileArt.nachricht,
          zeit: _zeitpunkt(nachricht['created_at']),
          nachricht: nachricht,
          angepinnt: !istGeloescht && nachricht['pinned_at'] != null,
        ),
      );
    }

    for (final eintrag in verlauf) {
      zeilen.add(
        ChatZeile(
          art: ChatZeileArt.verlauf,
          zeit: _zeitpunkt(eintrag['am']),
          verlauf: [eintrag],
        ),
      );
    }

    zeilen.sort((a, b) => a.zeit.compareTo(b.zeit));

    final zusammengefasst = _fasseVerlaufZusammen(zeilen);
    if (!angepinntZuerst) return zusammengefasst;

    final angepinnte = zusammengefasst.where((z) => z.angepinnt).toList()
      ..sort((a, b) {
        final ap = _zeitpunkt(a.nachricht?['pinned_at']);
        final bp = _zeitpunkt(b.nachricht?['pinned_at']);
        return bp.compareTo(ap);
      });
    final rest = zusammengefasst.where((z) => !z.angepinnt).toList();
    return [...angepinnte, ...rest];
  }

  /// Zieht direkt aufeinanderfolgende Verlaufszeilen GLEICHER Art zusammen.
  ///
  /// Gleiche Art, nicht nur „irgendwie Verlauf": „Anna und Ben sind
  /// beigetreten" und „Cem hat die Community verlassen" gehören nicht in einen
  /// Satz. Steht eine Nachricht dazwischen, bleibt die Trennung erhalten — der
  /// Verlauf soll ja zeigen, WANN jemand kam.
  static List<ChatZeile> _fasseVerlaufZusammen(List<ChatZeile> zeilen) {
    final ergebnis = <ChatZeile>[];
    for (final zeile in zeilen) {
      if (zeile.art != ChatZeileArt.verlauf || ergebnis.isEmpty) {
        ergebnis.add(zeile);
        continue;
      }
      final letzte = ergebnis.last;
      if (letzte.art != ChatZeileArt.verlauf ||
          letzte.verlauf.last['art'] != zeile.verlauf.first['art']) {
        ergebnis.add(zeile);
        continue;
      }
      ergebnis[ergebnis.length - 1] = ChatZeile(
        art: ChatZeileArt.verlauf,
        zeit: letzte.zeit,
        verlauf: [...letzte.verlauf, ...zeile.verlauf],
      );
    }
    return ergebnis;
  }

  /// Der Satz unter einer zusammengefassten Verlaufszeile.
  ///
  /// Ein Name: „Anna ist beigetreten."
  /// Zwei:     „Anna und Ben sind beigetreten."
  /// Drei:     „Anna, Ben und Cem sind beigetreten."
  /// Mehr:     „Anna, Ben, Cem und 7 weitere sind beigetreten."
  static String verlaufText(List<Map<String, dynamic>> gruppe) {
    if (gruppe.isEmpty) return '';
    final namen = <String>[];
    for (final eintrag in gruppe) {
      final profil = eintrag['profiles'];
      namen.add(
        CommunityChatService.displayName(
          profil is Map ? Map<String, dynamic>.from(profil) : null,
          fallbackUserId: eintrag['user_id']?.toString(),
        ),
      );
    }
    final art = gruppe.first['art']?.toString();
    final mehrzahl = namen.length > 1;
    final verb = switch (art) {
      'austritt' => mehrzahl
          ? 'haben die Community verlassen'
          : 'hat die Community verlassen',
      'entfernt' => mehrzahl ? 'wurden entfernt' : 'wurde entfernt',
      _ => mehrzahl ? 'sind beigetreten' : 'ist beigetreten',
    };

    if (namen.length == 1) return '${namen.first} $verb.';
    if (namen.length <= namenImText) {
      final vorne = namen.sublist(0, namen.length - 1).join(', ');
      return '$vorne und ${namen.last} $verb.';
    }
    final weitere = namen.length - namenImText;
    final vorne = namen.sublist(0, namenImText).join(', ');
    return '$vorne und $weitere weitere $verb.';
  }
}
