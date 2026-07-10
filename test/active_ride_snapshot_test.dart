import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActiveRideSnapshot', () {
    Map<String, dynamic> geometry() => {
      'type': 'LineString',
      'coordinates': [
        [9.7417, 47.4125],
        [9.7500, 47.4200],
        [9.7600, 47.4300],
      ],
    };

    test('toJson/fromJson Roundtrip erhält alle Felder', () {
      final snapshot = ActiveRideSnapshot(
        savedAt: DateTime(2026, 7, 6, 12, 30),
        startedAt: DateTime(2026, 7, 6, 12, 0),
        style: 'Kurvenjagd',
        distanceKm: 47.5,
        geometry: geometry(),
        isRoundTrip: true,
        durationSeconds: 3600,
        drivenKm: 12.3,
        elapsedSeconds: 1800,
        wasPaused: true,
        lastLat: 47.42,
        lastLng: 9.75,
      );

      final restored = ActiveRideSnapshot.fromJson(snapshot.toJson());

      expect(restored, isNotNull);
      expect(restored!.savedAt, snapshot.savedAt);
      expect(restored.startedAt, snapshot.startedAt);
      expect(restored.style, 'Kurvenjagd');
      expect(restored.distanceKm, 47.5);
      expect(restored.isRoundTrip, isTrue);
      expect(restored.durationSeconds, 3600);
      expect(restored.drivenKm, 12.3);
      expect(restored.elapsedSeconds, 1800);
      expect(restored.wasPaused, isTrue);
      expect(restored.lastLat, 47.42);
      expect(restored.lastLng, 9.75);
      expect(
        (restored.geometry['coordinates'] as List).length,
        3,
      );
    });

    test('fromJson lehnt fremde Schema-Version ab', () {
      final json = ActiveRideSnapshot(
        savedAt: DateTime(2026, 7, 6),
        startedAt: DateTime(2026, 7, 6),
        style: 'Entdecker',
        distanceKm: 30,
        geometry: geometry(),
        isRoundTrip: false,
      ).toJson();
      json['version'] = 99;
      expect(ActiveRideSnapshot.fromJson(json), isNull);
    });

    test('fromJson lehnt kaputte Geometrie ab', () {
      final json = ActiveRideSnapshot(
        savedAt: DateTime(2026, 7, 6),
        startedAt: DateTime(2026, 7, 6),
        style: 'Entdecker',
        distanceKm: 30,
        geometry: geometry(),
        isRoundTrip: false,
      ).toJson();
      json['geometry'] = {
        'type': 'LineString',
        'coordinates': [
          [9.7, 47.4],
        ], // nur 1 Punkt — unbrauchbar
      };
      expect(ActiveRideSnapshot.fromJson(json), isNull);
    });

    test('fromJson toleriert fehlende optionale Felder', () {
      final json = {
        'version': ActiveRideSnapshot.schemaVersion,
        'saved_at': DateTime(2026, 7, 6).toIso8601String(),
        'started_at': DateTime(2026, 7, 6).toIso8601String(),
        'style': 'Sport',
        'distance_km': 55.0,
        'geometry': geometry(),
        'is_round_trip': true,
      };
      final restored = ActiveRideSnapshot.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.drivenKm, 0);
      expect(restored.elapsedSeconds, 0);
      expect(restored.wasPaused, isFalse);
      expect(restored.lastLat, isNull);
    });
  });
}
