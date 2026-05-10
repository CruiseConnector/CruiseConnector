import 'package:cruise_connect/domain/models/cruise_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> groupRow({
    Map<String, dynamic>? routeData,
    Map<String, dynamic>? currentRouteData,
    int routeRevision = 1,
    List<Map<String, dynamic>> members = const [],
  }) {
    return {
      'id': 'group-1',
      'name': 'Abendrunde',
      'created_by': 'owner-1',
      'is_public': true,
      'is_active': true,
      'max_people': 4,
      'created_at': '2026-05-09T10:00:00Z',
      'route_data': routeData,
      'current_route_data': currentRouteData,
      'route_revision': routeRevision,
      'route_updated_by': 'driver-1',
      'route_updated_at': '2026-05-09T10:05:00Z',
      'group_members': members,
    };
  }

  Map<String, dynamic> memberRow({
    required String userId,
    String role = 'passenger',
    String rideRole = 'passenger',
  }) {
    return {
      'id': 'member-$userId',
      'group_id': 'group-1',
      'user_id': userId,
      'role': role,
      'ride_role': rideRole,
      'created_at': '2026-05-09T10:00:00Z',
    };
  }

  test('nutzt current_route_data als aktive Gruppenroute', () {
    final group = CruiseGroup.fromMap(
      groupRow(
        routeData: {'fingerprint': 'original'},
        currentRouteData: {'fingerprint': 'canonical'},
        routeRevision: 7,
      ),
    );

    expect(group.routeRevision, 7);
    expect(group.activeRouteData?['fingerprint'], 'canonical');
    expect(group.routeUpdatedBy, 'driver-1');
    expect(group.routeUpdatedAt, DateTime.parse('2026-05-09T10:05:00Z'));
  });

  test('faellt fuer alte Gruppen auf route_data zurueck', () {
    final group = CruiseGroup.fromMap(
      groupRow(routeData: {'fingerprint': 'legacy'}),
    );

    expect(group.routeRevision, 1);
    expect(group.activeRouteData?['fingerprint'], 'legacy');
  });

  test('erlaubt Route-Updates fuer Owner und Fahrer', () {
    final group = CruiseGroup.fromMap(
      groupRow(
        members: [
          memberRow(userId: 'owner-1', role: 'owner'),
          memberRow(userId: 'driver-1', rideRole: 'driver'),
          memberRow(userId: 'passenger-1'),
        ],
      ),
    );

    expect(group.canUpdateRoute('owner-1'), isTrue);
    expect(group.canUpdateRoute('driver-1'), isTrue);
    expect(group.canUpdateRoute('passenger-1'), isFalse);
  });
}
