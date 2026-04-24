import 'package:cruise_connect/data/services/web_position_smoother.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

void main() {
  geo.Position position({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double heading = 0,
    double speed = 0,
    double accuracy = 8,
  }) {
    return geo.Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0,
    );
  }

  group('WebPositionSmoother', () {
    test('unterdrueckt kleine GPS-Spruenge als Standrauschen', () {
      final smoother = WebPositionSmoother(
        minMovementMeters: 2.5,
        stationaryNoiseMeters: 6.0,
        minHeadingDistanceMeters: 4.0,
      );
      final start = position(
        latitude: 48.137,
        longitude: 11.575,
        timestamp: DateTime(2026, 3, 30, 12, 0, 0),
      );
      final first = smoother.update(start);
      expect(first, isNotNull);

      final jitter = position(
        latitude: 48.13701,
        longitude: 11.57501,
        timestamp: DateTime(2026, 3, 30, 12, 0, 1),
      );
      final second = smoother.update(jitter);

      expect(second, isNull);
      expect(smoother.current?.latitude, closeTo(48.137, 0.000001));
      expect(smoother.current?.longitude, closeTo(11.575, 0.000001));
    });

    test('laengere Bewegung fuehrt zu einem sichtbaren Update', () {
      final smoother = WebPositionSmoother(
        minMovementMeters: 2.5,
        stationaryNoiseMeters: 6.0,
        minHeadingDistanceMeters: 4.0,
      );
      smoother.update(
        position(
          latitude: 48.137,
          longitude: 11.575,
          timestamp: DateTime(2026, 3, 30, 12, 0, 0),
        ),
      );

      final moved = smoother.update(
        position(
          latitude: 48.13712,
          longitude: 11.57512,
          timestamp: DateTime(2026, 3, 30, 12, 0, 1),
        ),
      );

      expect(moved, isNotNull);
      expect(smoother.current, isNotNull);
      expect(smoother.current!.latitude, closeTo(48.13712, 0.0002));
      expect(smoother.current!.longitude, closeTo(11.57512, 0.0002));
    });

    test('Heading bleibt bei kleinem Rauschen stabil', () {
      final smoother = WebPositionSmoother(
        minMovementMeters: 2.5,
        stationaryNoiseMeters: 6.0,
        minHeadingDistanceMeters: 4.0,
      );

      smoother.update(
        position(
          latitude: 48.0,
          longitude: 11.0,
          timestamp: DateTime(2026, 3, 30, 12, 0, 0),
        ),
      );
      smoother.update(
        position(
          latitude: 48.0,
          longitude: 11.00012,
          timestamp: DateTime(2026, 3, 30, 12, 0, 1),
        ),
      );
      final headingAfterMove = smoother.heading;

      final jitter = smoother.update(
        position(
          latitude: 48.00001,
          longitude: 11.00013,
          timestamp: DateTime(2026, 3, 30, 12, 0, 2),
        ),
      );

      expect(jitter, isNull);
      expect(smoother.heading, closeTo(headingAfterMove, 0.01));
    });

    test('Teleport entfernt den alten State komplett', () {
      final smoother = WebPositionSmoother(
        minMovementMeters: 2.5,
        stationaryNoiseMeters: 6.0,
        maxJumpMeters: 200.0,
      );

      smoother.update(
        position(
          latitude: 48.137,
          longitude: 11.575,
          timestamp: DateTime(2026, 3, 30, 12, 0, 0),
        ),
      );

      final teleported = smoother.update(
        position(
          latitude: 49.0,
          longitude: 12.0,
          timestamp: DateTime(2026, 3, 30, 12, 0, 1),
        ),
      );

      expect(teleported, isNotNull);
      expect(teleported!.latitude, closeTo(49.0, 0.000001));
      expect(teleported.longitude, closeTo(12.0, 0.000001));
      expect(smoother.current!.latitude, closeTo(49.0, 0.000001));
      expect(smoother.current!.longitude, closeTo(12.0, 0.000001));
    });
  });
}
