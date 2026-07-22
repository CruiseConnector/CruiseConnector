import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/core/input_limits.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/domain/models/community_chat_message.dart';

class CommunityChatServiceException implements Exception {
  const CommunityChatServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CommunityChatService {
  CommunityChatService._();

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _userId => _db.auth.currentUser?.id;
  static const String duplicateRoutePostMessage =
      'Diese Route hast du in dieser Community schon gepostet.';

  static const String _communitySelect =
      'id, owner_id, name, description, is_public, invite_code, created_at, '
      'updated_at, owner_only_messages, community_members(user_id, role), '
      'profiles:owner_id(id, username, avatar_url)';

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
      throw CommunityChatServiceException(e.message);
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
      throw CommunityChatServiceException(e.message);
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
