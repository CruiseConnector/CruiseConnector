import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/trip_service.dart';

void main() {
  group('TripSummary', () {
    test('uebernimmt group_id fuer Gruppen-Resume', () {
      final summary = TripSummary.fromMap({
        'id': 'trip-1',
        'owner_id': 'user-1',
        'title': 'Gruppenfahrt',
        'status': 'paused',
        'total_distance_km': 12.5,
        'total_duration_seconds': 1800,
        'stop_count': 3,
        'default_style': 'Sport',
        'group_id': 'group-1',
      });

      expect(summary.groupId, 'group-1');
    });
  });
}
