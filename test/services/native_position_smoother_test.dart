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

    // 2026-07-22 (vucko „nach Routen-Start 300-400m verkehrt herum"):
    // snapHeading() muss den kompletten Heading-Zustand HART setzen — auch die
    // Bewegungs-Komponente, sonst blendet der nächste Low-Speed-Fix den gerade
    // gesetzten korrekten Wert sofort wieder Richtung altem (falschem) Zustand.
    test('snapHeading() setzt Heading hart und predict() bleibt darauf', () {
      final smoother = NativePositionSmoother();
      final start = DateTime.utc(2026, 7, 22, 12);
      smoother.update(
        position(
          latitude: 47.4125,
          longitude: 9.7417,
          timestamp: start,
          heading: 180,
          speed: 10,
        ),
      );
      smoother.update(
        position(
          latitude: 47.4126,
          longitude: 9.7417,
          timestamp: start.add(const Duration(seconds: 1)),
          heading: 180,
          speed: 10,
        ),
      );

      smoother.snapHeading(42.0);

      expect(smoother.heading, closeTo(42.0, 0.001));
      expect(smoother.hasValidHeading, isTrue);
      // Keine Rest-Drehrate: predict() darf nicht vom Snap wegdriften.
      final predicted = smoother.predict(DateTime.now()).heading;
      expect(predicted, closeTo(42.0, 0.001));
    });

    test('Stillstands-Jitter (speed≈0) korrumpiert das Bewegungs-Heading '
        'nicht mehr (kein 180°-Flip an der Ampel)', () {
      final smoother = NativePositionSmoother(
        minHeadingDistanceMeters: 1.2,
        stationaryNoiseMeters: 1.2,
      );
      final start = DateTime.utc(2026, 7, 22, 12);
      // Fahrt nach Norden aufbauen (Heading ≈ 0°).
      var lat = 47.4125;
      for (var i = 0; i < 5; i++) {
        smoother.update(
          position(
            latitude: lat,
            longitude: 9.7417,
            timestamp: start.add(Duration(seconds: i)),
            heading: 0,
            speed: 12,
          ),
        );
        lat += 0.0001; // ~11m/s nordwärts
      }
      final headingBefore = smoother.heading;
      expect(
        headingBefore < 20 || headingBefore > 340,
        isTrue,
        reason: 'Aufbau-Fahrt zeigt nach Norden',
      );

      // Ampel-Stopp: OS meldet speed=0, Position jittert 3-5m nach SÜDEN —
      // vor dem Fix prägte genau das ein ~180°-falsches Bewegungs-Heading.
      var jitterLat = lat;
      for (var i = 0; i < 6; i++) {
        jitterLat -= 0.00004; // ~4,4m südwärts pro „Fix" (reines Rauschen)
        smoother.update(
          position(
            latitude: jitterLat,
            longitude: 9.7417,
            timestamp: start.add(Duration(seconds: 5 + i)),
            heading: 0,
            headingAccuracy: 90, // GPS-Heading im Stand unbrauchbar
            speed: 0, // OS: Stillstand
          ),
        );
      }

      // Heading darf durch den Stillstands-Jitter NICHT Richtung Süden (180°)
      // gekippt sein.
      final headingAfter = smoother.heading;
      final delta = (headingAfter - headingBefore).abs() % 360;
      final effectiveDelta = delta > 180 ? 360 - delta : delta;
      expect(
        effectiveDelta,
        lessThan(45.0),
        reason:
            'Stillstands-Rauschen darf die Richtung nicht umdrehen '
            '(vorher: $headingBefore°, nachher: $headingAfter°)',
      );
    });
  });
}
