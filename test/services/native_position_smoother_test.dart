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

    test(
      'predict() extrapoliert das Heading in Drehrichtung (Kamera-Abbiege-Glide)',
      () async {
        // 2026-06-13 (vucko Kamera-Abbiege-Ruckeln): Beim Abbiegen muss
        // predict(future) das Heading ÜBER den letzten geglätteten Wert hinaus
        // weiterdrehen (Dead Reckoning), damit das Kamera-Ziel zwischen den
        // 1Hz-Fixes kontinuierlich wandert statt zu springen.
        final smoother = NativePositionSmoother();
        var lat = 47.4125;
        const lng = 9.7417;
        // Stetige Rechtsdrehung 0→60° in 6 Schritten mit echten Zeitlücken,
        // damit die Winkelgeschwindigkeit (aus Wall-Clock-dt) aufgebaut wird.
        // Die Positions-Timestamps müssen NAHE der realen Uhr liegen, sonst
        // clampt pred() den Heading-dt (max 1s) für beide Abfragen gleich.
        final base = DateTime.now();
        for (var i = 0; i <= 6; i++) {
          lat += 0.0002;
          smoother.update(
            position(
              latitude: lat,
              longitude: lng,
              timestamp: base.add(Duration(milliseconds: 90 * i)),
              heading: (i * 10).toDouble(),
              headingAccuracy: 5,
              speed: 15.0,
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 90));
        }

        // Abfragezeiten relativ zum LETZTEN Positions-Timestamp, beide < 1s
        // Heading-Clamp, damit der Unterschied = Extrapolation ist.
        final lastTs = base.add(const Duration(milliseconds: 90 * 6));
        final hNow = smoother
            .predict(lastTs.add(const Duration(milliseconds: 50)))
            .heading;
        final hAhead = smoother
            .predict(lastTs.add(const Duration(milliseconds: 450)))
            .heading;

        double fwd(double from, double to) {
          var d = (to - from) % 360.0;
          if (d < 0) d += 360.0;
          return d; // 0..360 im Uhrzeigersinn
        }

        // In Drehrichtung (im Uhrzeigersinn) voraus, aber nicht über die Kurve
        // hinaus (Deckel): zwischen 3° und 70°.
        final advance = fwd(hNow, hAhead);
        expect(
          advance,
          greaterThan(3.0),
          reason: 'Heading muss in Drehrichtung extrapoliert werden',
        );
        expect(
          advance,
          lessThan(70.0),
          reason: 'Extrapolation gedeckelt (kein Überdrehen)',
        );
      },
    );
  });
}
