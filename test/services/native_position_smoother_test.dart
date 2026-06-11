import 'package:cruise_connect/data/services/native_position_smoother.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

void main() {
  geo.Position position({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double heading = 0,
    double headingAccuracy = 5,
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
      headingAccuracy: headingAccuracy,
      speed: speed,
      speedAccuracy: 0,
    );
  }

  group('NativePositionSmoother', () {
    test('initialisiert Speed sofort wenn die App bereits rollt', () {
      final smoother = NativePositionSmoother();
      final first = smoother.update(
        position(
          latitude: 47.4125,
          longitude: 9.7417,
          timestamp: DateTime.utc(2026, 6, 11, 12),
          speed: 70 / 3.6,
        ),
      );

      expect(first, isNotNull);
      expect(smoother.speed, closeTo(70 / 3.6, 0.01));
    });

    test('Speed konvergiert bei echtem 1Hz-GPS ohne sekundenlangen Lag', () {
      final smoother = NativePositionSmoother();
      final start = DateTime.utc(2026, 6, 11, 12);
      smoother.update(
        position(
          latitude: 47.4125,
          longitude: 9.7417,
          timestamp: start,
          speed: 0,
        ),
      );

      smoother.update(
        position(
          latitude: 47.41267,
          longitude: 9.7417,
          timestamp: start.add(const Duration(seconds: 1)),
          speed: 70 / 3.6,
        ),
      );

      expect(
        smoother.speed,
        greaterThan(17.0),
        reason: 'route render lock catch-up must see real drive speed at 1Hz',
      );
      expect(smoother.speed, lessThanOrEqualTo(70 / 3.6));
    });

    test('Speed bleibt bei 20Hz-Simulator-Ticks weiterhin geglaettet', () {
      final smoother = NativePositionSmoother();
      final start = DateTime.utc(2026, 6, 11, 12);
      smoother.update(
        position(
          latitude: 47.4125,
          longitude: 9.7417,
          timestamp: start,
          speed: 0,
        ),
      );

      smoother.update(
        position(
          latitude: 47.41251,
          longitude: 9.7417,
          timestamp: start.add(const Duration(milliseconds: 50)),
          speed: 70 / 3.6,
        ),
      );

      expect(smoother.speed, closeTo((70 / 3.6) * 0.3, 0.1));
    });
  });
}
