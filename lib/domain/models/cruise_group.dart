import 'group_member.dart';

enum GroupStyle { kurvenjagd, sport, abend, entdecker }

class CruiseGroup {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final bool isPublic;
  final bool isActive;
  final int maxPeople;
  final DateTime? startTime;
  final DateTime? activatedAt;
  final DateTime createdAt;
  final String? inviteCode;

  final Map<String, dynamic>? routeData;
  final Map<String, dynamic>? startLocation;

  final List<GroupMember> members;

  const CruiseGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isPublic,
    required this.isActive,
    required this.maxPeople,
    required this.createdAt,
    this.description,
    this.startTime,
    this.activatedAt,
    this.routeData,
    this.startLocation,
    this.members = const [],
    this.inviteCode,
  });

  factory CruiseGroup.fromMap(Map<String, dynamic> m) => CruiseGroup(
    id: m['id'] as String,
    name: (m['name'] ?? '') as String,
    description: m['description'] as String?,
    ownerId: (m['created_by'] ?? m['owner_id']) as String,
    isPublic: (m['is_public'] ?? true) as bool,
    isActive: (m['is_active'] ?? false) as bool,
    maxPeople: (m['max_people'] ?? 10) as int,
    startTime: m['start_time'] != null
        ? DateTime.parse(m['start_time'] as String)
        : null,
    activatedAt: m['activated_at'] != null
        ? DateTime.parse(m['activated_at'] as String)
        : null,
    createdAt: DateTime.parse(m['created_at'] as String),
    inviteCode: m['invite_code'] as String?,
    routeData: m['route_data'] as Map<String, dynamic>?,
    startLocation: m['start_location'] as Map<String, dynamic>?,
    members: (m['group_members'] is List)
        ? (m['group_members'] as List)
              .whereType<Map<String, dynamic>>()
              .map<GroupMember>(GroupMember.fromMap)
              .toList()
        : const <GroupMember>[],
  );

  bool isOwner(String userId) =>
      ownerId == userId ||
      members.any(
        (mem) => mem.userId == userId && mem.role == MemberRole.owner,
      );
}
