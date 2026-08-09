import 'package:cruise_connect/domain/models/group_member.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> memberRow({
    String? lastUpdatedAt,
    double? lat = 47.4201,
    double? lng = 9.7402,
    String rideRole = 'driver',
  }) {
    return {
      'id': 'member-1',
      'group_id': 'group-1',
      'user_id': 'user-1',
      'role': 'driver',
      'ride_role': rideRole,
      'current_lat': lat,
      'current_lng': lng,
      'last_updated_at': lastUpdatedAt,
      'created_at': '2026-05-09T10:00:00Z',
      'profiles': {
        'display_name': 'Vucko',
        'username': 'fallback-name',
        'avatar_url': 'avatar.png',
      },
    };
  }

  group('GroupMember parsing', () {
    test('liest Profil, Rolle und Live-Position', () {
      final member = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T10:00:08Z'),
      );

      expect(member.role, MemberRole.driver);
      expect(member.rideRole, RideRole.driver);
      expect(member.displayName, 'Vucko');
      expect(member.avatarUrl, 'avatar.png');
      expect(member.hasLocation, isTrue);
    });

    test('faellt bei fehlender ride_role auf MemberRole zurueck', () {
      final row = memberRow(lastUpdatedAt: '2026-05-09T10:00:08Z')
        ..remove('ride_role');

      final member = GroupMember.fromMap(row);

      expect(member.rideRole, RideRole.driver);
    });
  });

  group('GroupMember freshness', () {
    final now = DateTime.parse('2026-05-09T10:00:20Z');

    test('markiert kuerzlich aktualisierte Position als frisch', () {
      final member = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T10:00:10Z'),
      );

      expect(member.hasFreshLocation(now: now), isTrue);
      expect(member.hasStaleLocation(now: now), isFalse);
    });

    test('markiert alte Position als stale statt ohne Location', () {
      final member = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T09:59:30Z'),
      );

      expect(member.hasLocation, isTrue);
      expect(member.hasFreshLocation(now: now), isFalse);
      expect(member.hasStaleLocation(now: now), isTrue);
    });

    test('Position ohne Timestamp ist nicht frisch, bleibt aber sichtbar', () {
      final member = GroupMember.fromMap(memberRow());

      expect(member.hasLocation, isTrue);
      expect(member.hasFreshLocation(now: now), isFalse);
      expect(member.hasStaleLocation(now: now), isTrue);
    });

    // 2026-08-09 (vucko, Gruppenfahrt 08.08.): Die Mitfahrerin sass im selben
    // Auto und stand trotzdem als zweiter Marker mit eigenem Profilbild auf der
    // Karte. Nur Fahrer sind Fahrzeuge — auch dann, wenn eine alte App-Version
    // per Realtime-Broadcast noch eine Position vorbeischickt.
    test('Mitfahrer ist nie ein Fahrzeug auf der Karte', () {
      final fahrer = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T10:00:08Z'),
      );
      expect(fahrer.istFahrzeugAufKarte, isTrue);

      final mitfahrer = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T10:00:08Z', rideRole: 'passenger'),
      );
      expect(mitfahrer.hasLocation, isTrue, reason: 'Rohdaten haben Position');
      expect(mitfahrer.istFahrzeugAufKarte, isFalse);
    });

    test('Fahrer ohne Position ist ebenfalls kein Marker', () {
      final ohnePosition = GroupMember.fromMap(
        memberRow(lat: null, lng: null),
      );
      expect(ohnePosition.rideRole, RideRole.driver);
      expect(ohnePosition.istFahrzeugAufKarte, isFalse);
    });

    test('ungueltige Koordinaten zaehlen nicht als Location', () {
      final member = GroupMember.fromMap(
        memberRow(lastUpdatedAt: '2026-05-09T10:00:10Z', lat: double.nan),
      );

      expect(member.hasLocation, isFalse);
      expect(member.hasFreshLocation(now: now), isFalse);
    });
  });
}
