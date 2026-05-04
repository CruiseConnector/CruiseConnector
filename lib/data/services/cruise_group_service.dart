import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/cruise_group.dart';
import '../../domain/models/group_member.dart';

/// CRUD + Realtime für `groups`/`group_members` im Cruise-Kontext.
class CruiseGroupService {
  CruiseGroupService._();
  static final _db = Supabase.instance.client;

  // ── CRUD ───────────────────────────────────────────────────────────────────

  static Future<String> create({
    required String name,
    String? description,
    required bool isPublic,
    required int maxPeople,
    DateTime? startTime,
    required Map<String, dynamic> routeData,
    required Map<String, dynamic> startLocation,
  }) async {
    final uid = _db.auth.currentUser!.id;
    final row = await _db
        .from('groups')
        .insert({
          'created_by': uid,
          'name': name,
          'description': description,
          'is_public': isPublic,
          'max_people': maxPeople,
          'start_time': startTime?.toIso8601String(),
          'route_data': routeData,
          'start_location': startLocation,
        })
        .select('id')
        .single();
    final groupId = row['id'] as String;
    if (isPublic) {
      await _notifyMutualFriendsAboutPublicGroup(groupId);
    }
    return groupId;
  }

  static Future<CruiseGroup?> fetch(String groupId) async {
    final row = await _db
        .from('groups')
        .select('*, group_members(*)')
        .eq('id', groupId)
        .maybeSingle();
    if (row == null) return null;

    // Profile-Daten separat laden (keine FK zu profiles vorhanden).
    final members = (row['group_members'] as List?) ?? const [];
    final userIds = members
        .whereType<Map<String, dynamic>>()
        .map((m) => m['user_id'] as String)
        .toList();
    if (userIds.isNotEmpty) {
      final profiles = await _db
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', userIds);
      final byId = {for (final p in profiles as List) (p as Map)['id']: p};
      for (final m in members.whereType<Map<String, dynamic>>()) {
        final p = byId[m['user_id']];
        if (p != null) m['profiles'] = p;
      }
    }
    return CruiseGroup.fromMap(row);
  }

  static Future<void> activate(String groupId) async {
    await _db
        .from('groups')
        .update({
          'is_active': true,
          'activated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', groupId);
    await _notifyGroupMembers(groupId, 'group_ride_started');
  }

  static Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required MemberRole role,
  }) async {
    final patch = <String, dynamic>{'role': memberRoleToString(role)};
    if (role != MemberRole.owner) {
      patch['ride_role'] = rideRoleToString(
        role == MemberRole.driver ? RideRole.driver : RideRole.passenger,
      );
    }
    await _db
        .from('group_members')
        .update(patch)
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  static Future<void> updateRideRole({
    required String groupId,
    required String userId,
    required RideRole rideRole,
  }) async {
    await _db
        .from('group_members')
        .update({'ride_role': rideRoleToString(rideRole)})
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  static Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', userId);
  }

  static Future<void> updateMyPosition({
    required String groupId,
    required double lat,
    required double lng,
  }) async {
    final uid = _db.auth.currentUser!.id;
    await _db
        .from('group_members')
        .update({
          'current_lat': lat,
          'current_lng': lng,
          'last_updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }

  static Future<void> join(
    String groupId, {
    MemberRole role = MemberRole.passenger,
  }) async {
    final uid = _db.auth.currentUser!.id;
    await _db.from('group_members').upsert({
      'group_id': groupId,
      'user_id': uid,
      'role': memberRoleToString(role),
      'ride_role': rideRoleToString(
        role == MemberRole.driver ? RideRole.driver : RideRole.passenger,
      ),
    });
    await _notifyGroupOwners(groupId, 'group_joined', fromUserId: uid);
  }

  static Future<void> leave(String groupId) async {
    final uid = _db.auth.currentUser!.id;
    await _db
        .from('group_members')
        .delete()
        .eq('group_id', groupId)
        .eq('user_id', uid);
  }

  // ── Realtime ───────────────────────────────────────────────────────────────

  /// Hört auf Änderungen am `groups`-Row (z.B. is_active → true).
  static RealtimeChannel subscribeGroup(
    String groupId,
    void Function(Map<String, dynamic> newRow) onChange,
  ) {
    final ch = _db.channel('group_sync_$groupId');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'groups',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: groupId,
      ),
      callback: (payload) => onChange(payload.newRecord),
    );
    ch.subscribe();
    return ch;
  }

  /// Hört auf Positions- und Rollen-Updates aller Mitglieder.
  static RealtimeChannel subscribeMembers(
    String groupId,
    void Function(Map<String, dynamic> row) onChange,
  ) {
    final ch = _db.channel('location_sync_$groupId');
    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'group_members',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'group_id',
        value: groupId,
      ),
      callback: (payload) {
        final row = payload.newRecord.isNotEmpty
            ? payload.newRecord
            : payload.oldRecord;
        onChange(row);
      },
    );
    ch.subscribe();
    return ch;
  }

  static Future<void> _notifyMutualFriendsAboutPublicGroup(
    String groupId,
  ) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final following = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted');
      final followingIds = (following as List)
          .map((r) => (r as Map)['following_id'] as String)
          .toSet();
      if (followingIds.isEmpty) return;

      final back = await _db
          .from('follows')
          .select('follower_id')
          .eq('following_id', uid)
          .eq('status', 'accepted')
          .inFilter('follower_id', followingIds.toList());
      final mutualIds = (back as List)
          .map((r) => (r as Map)['follower_id'] as String)
          .where((id) => id != uid)
          .toSet();
      if (mutualIds.isEmpty) return;

      await _db.from('notifications').insert([
        for (final target in mutualIds)
          {
            'user_id': target,
            'from_user_id': uid,
            'type': 'group_public_created',
            'reference_id': groupId,
          },
      ]);
    } catch (_) {
      // Notifications must not block group creation.
    }
  }

  static Future<void> _notifyGroupMembers(String groupId, String type) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final members = await _db
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);
      final targets = (members as List)
          .map((r) => (r as Map)['user_id'] as String?)
          .whereType<String>()
          .where((id) => id != uid)
          .toSet();
      if (targets.isEmpty) return;
      await _db.from('notifications').insert([
        for (final target in targets)
          {
            'user_id': target,
            'from_user_id': uid,
            'type': type,
            'reference_id': groupId,
          },
      ]);
    } catch (_) {
      // Best-effort notification.
    }
  }

  static Future<void> _notifyGroupOwners(
    String groupId,
    String type, {
    required String fromUserId,
  }) async {
    try {
      final owners = await _db
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .eq('role', 'owner');
      final targets = (owners as List)
          .map((r) => (r as Map)['user_id'] as String?)
          .whereType<String>()
          .where((id) => id != fromUserId)
          .toSet();
      if (targets.isEmpty) return;
      await _db.from('notifications').insert([
        for (final target in targets)
          {
            'user_id': target,
            'from_user_id': fromUserId,
            'type': type,
            'reference_id': groupId,
          },
      ]);
    } catch (_) {
      // Best-effort notification.
    }
  }
}
