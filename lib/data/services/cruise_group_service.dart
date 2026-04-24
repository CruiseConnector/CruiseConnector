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
    final row = await _db.from('groups').insert({
      'created_by': uid,
      'name': name,
      'description': description,
      'is_public': isPublic,
      'max_people': maxPeople,
      'start_time': startTime?.toIso8601String(),
      'route_data': routeData,
      'start_location': startLocation,
    }).select('id').single();
    return row['id'] as String;
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
      final byId = {
        for (final p in profiles as List) (p as Map)['id']: p,
      };
      for (final m in members.whereType<Map<String, dynamic>>()) {
        final p = byId[m['user_id']];
        if (p != null) m['profiles'] = p;
      }
    }
    return CruiseGroup.fromMap(row);
  }

  static Future<void> activate(String groupId) async {
    await _db.from('groups').update({
      'is_active': true,
      'activated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', groupId);
  }

  static Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required MemberRole role,
  }) async {
    await _db
        .from('group_members')
        .update({'role': memberRoleToString(role)})
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

  static Future<void> join(String groupId,
      {MemberRole role = MemberRole.passenger}) async {
    final uid = _db.auth.currentUser!.id;
    await _db.from('group_members').upsert({
      'group_id': groupId,
      'user_id': uid,
      'role': memberRoleToString(role),
    });
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
}
