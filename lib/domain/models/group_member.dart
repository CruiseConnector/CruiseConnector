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
  static const Duration defaultFreshLocationAge = Duration(seconds: 12);

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

  bool get hasLocation =>
      currentLat != null &&
      currentLng != null &&
      currentLat!.isFinite &&
      currentLng!.isFinite;

  /// Wird dieses Mitglied als eigenes Fahrzeug auf der Karte gezeichnet?
  ///
  /// 2026-08-09 (vucko, Gruppenfahrt 08.08.): Nur Fahrer sind Fahrzeuge. Die
  /// Mitfahrerin sass im selben Auto und erschien trotzdem als zweiter Marker
  /// mit eigenem Profilbild. Die Datenbank raeumt den Standort von Mitfahrern
  /// per Trigger weg; diese Pruefung faengt zusaetzlich Realtime-Broadcasts
  /// alter App-Versionen ab, die an der Datenbank vorbeigehen.
  bool get istFahrzeugAufKarte => hasLocation && rideRole == RideRole.driver;

  Duration? locationAge({DateTime? now}) {
    final updatedAt = lastUpdatedAt;
    if (updatedAt == null) return null;
    final reference = (now ?? DateTime.now()).toUtc();
    final age = reference.difference(updatedAt.toUtc());
    return age.isNegative ? Duration.zero : age;
  }

  bool hasFreshLocation({
    DateTime? now,
    Duration maxAge = defaultFreshLocationAge,
  }) {
    if (!hasLocation) return false;
    final age = locationAge(now: now);
    return age != null && age <= maxAge;
  }

  bool hasStaleLocation({
    DateTime? now,
    Duration maxAge = defaultFreshLocationAge,
  }) {
    return hasLocation && !hasFreshLocation(now: now, maxAge: maxAge);
  }

  GroupMember copyWith({
    MemberRole? role,
    RideRole? rideRole,
    double? currentLat,
    double? currentLng,
    DateTime? lastUpdatedAt,
    String? displayName,
    String? avatarUrl,
    bool clearLocation = false,
  }) {
    return GroupMember(
      id: id,
      groupId: groupId,
      userId: userId,
      role: role ?? this.role,
      rideRole: rideRole ?? this.rideRole,
      currentLat: clearLocation ? null : currentLat ?? this.currentLat,
      currentLng: clearLocation ? null : currentLng ?? this.currentLng,
      lastUpdatedAt: clearLocation ? null : lastUpdatedAt ?? this.lastUpdatedAt,
      createdAt: createdAt,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
