enum MemberRole { owner, driver, passenger }

enum RideRole { driver, passenger }

MemberRole memberRoleFromString(String? s) {
  switch (s) {
    case 'owner':
      return MemberRole.owner;
    case 'driver':
      return MemberRole.driver;
    default:
      return MemberRole.passenger;
  }
}

String memberRoleToString(MemberRole r) => r.name;

RideRole rideRoleFromString(String? s, {MemberRole? fallbackRole}) {
  switch (s) {
    case 'driver':
      return RideRole.driver;
    case 'passenger':
      return RideRole.passenger;
    default:
      return fallbackRole == MemberRole.driver
          ? RideRole.driver
          : RideRole.passenger;
  }
}

String rideRoleToString(RideRole r) => r.name;

class GroupMember {
  final String id;
  final String groupId;
  final String userId;
  final MemberRole role;
  final RideRole rideRole;
  final double? currentLat;
  final double? currentLng;
  final DateTime? lastUpdatedAt;
  final DateTime createdAt;

  // Optionaler Join mit profiles
  final String? displayName;
  final String? avatarUrl;

  const GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    this.rideRole = RideRole.passenger,
    required this.createdAt,
    this.currentLat,
    this.currentLng,
    this.lastUpdatedAt,
    this.displayName,
    this.avatarUrl,
  });

  factory GroupMember.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    final role = memberRoleFromString(m['role'] as String?);
    return GroupMember(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      userId: m['user_id'] as String,
      role: role,
      rideRole: rideRoleFromString(
        m['ride_role'] as String?,
        fallbackRole: role,
      ),
      currentLat: (m['current_lat'] as num?)?.toDouble(),
      currentLng: (m['current_lng'] as num?)?.toDouble(),
      lastUpdatedAt: m['last_updated_at'] != null
          ? DateTime.parse(m['last_updated_at'] as String)
          : null,
      createdAt: DateTime.parse(m['created_at'] as String),
      displayName:
          profile?['display_name'] as String? ??
          profile?['username'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }
}
