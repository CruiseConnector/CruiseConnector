import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/route_quality_validator.dart';

void main() {
  const validator = RouteQualityValidator();

  group('validateOverlap', () {
    test('Keine Überlappung bei gerader Linie', () {
      // Gerade Linie von Süd nach Nord (kein Backtracking)
      final coords = List.generate(
        100,
        (i) => [11.0, 48.0 + i * 0.001], // ~111m pro Schritt
      );
      final overlap = validator.validateOverlap(coords);
      expect(overlap, lessThan(5.0));
    });

    test('Hohe Überlappung bei Hin-und-Zurück', () {
      // Hin und exakt zurück = Backtracking
      // 200 Punkte pro Richtung, 0.0001° Abstand ≈ 11m pro Schritt
      // overlapProximity=40m, also müssen Punkte <40m auseinander sein
      final outbound = List.generate(200, (i) => [11.0, 48.0 + i * 0.0001]);
      final inbound = List.generate(
        200,
        (i) => [11.0, 48.0 + (199 - i) * 0.0001],
      );
      final coords = [...outbound, ...inbound];
      final overlap = validator.validateOverlap(coords);
      expect(overlap, greaterThan(20.0));
    });

    test('Nahe Kreuzung ohne Backtracking bleibt unter dem Grenzwert', () {
      final vertical = List.generate(120, (i) => [11.0, 48.0 + i * 0.0001]);
      final horizontal = List.generate(
        120,
        (i) => [10.994 + i * 0.0001, 48.006],
      );
      final coords = [...vertical, ...horizontal];

      final overlap = validator.validateOverlap(coords);

      expect(overlap, lessThan(12.0));
    });
  });

  group('buildRouteFingerprint', () {
    test('gleiche Route erzeugt denselben Fingerprint', () {
      final coordinates = List.generate(
        40,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );

      final first = RouteQualityValidator.buildRouteFingerprint(
        coordinates,
        distanceKm: 24.6,
      );
      final second = RouteQualityValidator.buildRouteFingerprint(
        coordinates,
        distanceKm: 24.6,
      );

      expect(first, equals(second));
    });

    test('deutlich andere Route erzeugt anderen Fingerprint', () {
      final firstRoute = List.generate(
        40,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );
      final secondRoute = List.generate(
        40,
        (i) => [11.02 + i * 0.00015, 48.01 - i * 0.00008],
      );

      final first = RouteQualityValidator.buildRouteFingerprint(
        firstRoute,
        distanceKm: 24.6,
      );
      final second = RouteQualityValidator.buildRouteFingerprint(
        secondRoute,
        distanceKm: 31.4,
      );

      expect(first, isNot(equals(second)));
    });
  });

  group('validateNoUturns', () {
    test('Keine U-Turns bei sanfter Kurve', () {
      // Sanfte Kurve: kein abrupter Richtungswechsel
      final coords = List.generate(
        50,
        (i) => [11.0 + i * 0.0005, 48.0 + i * 0.0005],
      );
      final uturns = validator.validateNoUturns(coords);
      expect(uturns, isEmpty);
    });

    test('U-Turn erkannt bei 180° Wende', () {
      // Gerade nach Norden, dann abrupt nach Süden
      final north = List.generate(20, (i) => [11.0, 48.0 + i * 0.0003]);
      final south = List.generate(20, (i) => [11.0, 48.0 + 0.006 - i * 0.0003]);
      final coords = [...north, ...south];
      final uturns = validator.validateNoUturns(coords);
      expect(uturns, isNotEmpty);
    });
  });

  group('validateLoopClosed', () {
    test('Geschlossener Loop erkannt', () {
      // Start und Ende am selben Punkt
      final coords = [
        [11.0, 48.0],
        [11.01, 48.01],
        [11.02, 48.0],
        [11.0, 48.0], // Ende = Start
      ];
      expect(validator.validateLoopClosed(coords), isTrue);
    });

    test('Offener Loop erkannt', () {
      final coords = [
        [11.0, 48.0],
        [11.01, 48.01],
        [12.0, 49.0], // Ende weit vom Start
      ];
      expect(validator.validateLoopClosed(coords), isFalse);
    });
  });

  group('validateDistanceTolerance', () {
    test('Innerhalb ±12% Toleranz', () {
      expect(validator.validateDistanceTolerance(50.0, 48.0), isTrue);
      expect(validator.validateDistanceTolerance(50.0, 55.0), isTrue);
    });

    test('Außerhalb Toleranz', () {
      expect(validator.validateDistanceTolerance(50.0, 40.0), isFalse);
      expect(validator.validateDistanceTolerance(50.0, 60.0), isFalse);
    });

    test(
      'Rundkurse bekommen realistischere Toleranzen je nach Zieldistanz',
      () {
        expect(
          validator.roundTripDistanceTolerance(50.0),
          closeTo(0.18, 0.001),
        );
        expect(
          validator.roundTripDistanceTolerance(75.0),
          closeTo(0.16, 0.001),
        );
        expect(
          validator.roundTripDistanceTolerance(150.0),
          closeTo(0.14, 0.001),
        );
      },
    );
  });

  group('validateQuality – Gesamtbewertung', () {
    test('Gerade Rundkurs-Route besteht', () {
      // Dreieck: Start → Nord → Ost → zurück zum Start
      final coords = <List<double>>[];
      // Leg 1: Start nach Norden
      for (var i = 0; i < 40; i++) {
        coords.add([11.0, 48.0 + i * 0.002]);
      }
      // Leg 2: Nach Osten
      for (var i = 0; i < 40; i++) {
        coords.add([11.0 + i * 0.002, 48.08]);
      }
      // Leg 3: Zurück zum Start
      for (var i = 0; i < 40; i++) {
        final t = i / 39;
        coords.add([11.08 * (1 - t) + 11.0 * t, 48.08 * (1 - t) + 48.0 * t]);
      }

      final result = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 48.0,
      );
      expect(result.overlapPercent, lessThan(15.0));
      expect(result.uturnPositions, isEmpty);
      expect(result.isLoopClosed, isTrue);
      expect(result.distanceInTolerance, isTrue);
    });

    test('A→B-Route braucht keinen Loop-Closure-Check', () {
      final coords = List.generate(
        80,
        (i) => [11.0 + i * 0.0003, 48.0 + i * 0.0002],
      );

      final result = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: false,
        actualDistanceKm: 22.0,
      );

      expect(result.isLoopClosed, isTrue);
      expect(result.passed, isTrue);
    });

    test(
      'Rundkurs toleriert brauchbare Distanzabweichung bei 50km realistischer',
      () {
        final coords = <List<double>>[];
        for (var i = 0; i < 45; i++) {
          coords.add([11.0, 48.0 + i * 0.0018]);
        }
        for (var i = 0; i < 45; i++) {
          coords.add([11.0 + i * 0.0016, 48.081]);
        }
        for (var i = 0; i < 45; i++) {
          final t = i / 44;
          coords.add([
            11.0704 * (1 - t) + 11.0 * t,
            48.081 * (1 - t) + 48.0 * t,
          ]);
        }

        final result = validator.validateQuality(
          coordinates: coords,
          isRoundTrip: true,
          targetDistanceKm: 50.0,
          actualDistanceKm: 57.8,
        );

        expect(result.distanceInTolerance, isTrue);
        expect(result.passed, isTrue);
      },
    );
  });

  group('Route Similarity', () {
    test('nahezu identische Routen werden als ähnlich erkannt', () {
      final base = List.generate(
        120,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );
      final slightlyShifted = List.generate(
        120,
        (i) => [11.0002 + i * 0.0002, 48.0001 + i * 0.0001],
      );

      final similarity = RouteQualityValidator.calculateRouteSimilarityPercent(
        base,
        slightlyShifted,
        sampleCount: 40,
        proximityMeters: 150,
      );

      expect(similarity, greaterThan(75));
      expect(
        RouteQualityValidator.isRouteTooSimilarToPrevious(
          base,
          [slightlyShifted],
          thresholdPercent: 75,
          sampleCount: 40,
          proximityMeters: 150,
        ),
        isTrue,
      );
    });

    test('deutlich andere Routen fallen unter Similarity-Threshold', () {
      final first = List.generate(
        120,
        (i) => [11.0 + i * 0.0002, 48.0 + i * 0.0001],
      );
      final second = List.generate(
        120,
        (i) => [11.04 + i * 0.0002, 48.03 - i * 0.0001],
      );

      final similarity = RouteQualityValidator.calculateRouteSimilarityPercent(
        first,
        second,
        sampleCount: 40,
        proximityMeters: 120,
      );

      expect(similarity, lessThan(35));
      expect(
        RouteQualityValidator.isRouteTooSimilarToPrevious(
          first,
          [second],
          thresholdPercent: 70,
          sampleCount: 40,
          proximityMeters: 120,
        ),
        isFalse,
      );
    });
  });

  group('classifyGeneratedRoute', () {
    test(
      'brauchbarer Rundkurs wird als akzeptabel statt schlecht klassifiziert',
      () {
        final coords = <List<double>>[];
        for (var i = 0; i < 24; i++) {
          coords.add([11.0, 48.0 + i * 0.0015]);
        }
        for (var i = 0; i < 24; i++) {
          coords.add([11.0 + i * 0.0015, 48.0345]);
        }
        for (var i = 0; i < 24; i++) {
          final t = i / 23;
          coords.add([
            11.0345 * (1 - t) + 11.0 * t,
            48.0345 * (1 - t) + 48.0 * t,
          ]);
        }

        final quality = validator.validateQuality(
          coordinates: coords,
          isRoundTrip: true,
          targetDistanceKm: 50.0,
          actualDistanceKm: 58.2,
        );
        final classification = validator.classifyGeneratedRoute(
          quality: quality,
          isRoundTrip: true,
          coordinateCount: coords.length,
          actualDistanceKm: 58.2,
          targetDistanceKm: 50.0,
        );

        expect(classification.isAcceptable, isTrue);
        expect(classification.tier, isNot(RouteQualityTier.poor));
      },
    );

    test('klar fehlerhafte Rundkurs-Geometrie bleibt schlecht', () {
      final coords = [
        [11.0, 48.0],
        [11.02, 48.02],
        [11.0, 48.0],
        [11.02, 48.02],
        [11.0, 48.0],
      ];

      final quality = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 12.0,
      );
      final classification = validator.classifyGeneratedRoute(
        quality: quality,
        isRoundTrip: true,
        coordinateCount: coords.length,
        actualDistanceKm: 12.0,
        targetDistanceKm: 50.0,
      );

      expect(classification.tier, RouteQualityTier.poor);
    });
  });

  group('Shape-Metriken (Stern-/Spinnen-Erkennung)', () {
    test('Sauberer Loop hat niedrigere shapePenalty als Stern', () {
      // Kreisförmiger Loop um Dornbirn (47.41, 9.74)
      final loopCoords = <List<double>>[];
      const center = [9.74, 47.41];
      const radius = 0.08; // ~8km
      for (var i = 0; i <= 36; i++) {
        final angle = (i / 36) * 2 * 3.14159;
        loopCoords.add([
          center[0] + radius * 1.2 * cos(angle),
          center[1] + radius * sin(angle),
        ]);
      }

      final loopResult = validator.validateQuality(
        coordinates: loopCoords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 50.0,
      );

      // Stern-Route
      final sternCoords = <List<double>>[];
      for (var arm = 0; arm < 4; arm++) {
        final angle = arm * 90.0 * 3.14159 / 180.0;
        for (var i = 0; i <= 8; i++) {
          final dist = i * 0.01;
          sternCoords.add([
            center[0] + dist * cos(angle),
            center[1] + dist * sin(angle),
          ]);
        }
        for (var i = 8; i >= 0; i--) {
          final dist = i * 0.01;
          sternCoords.add([
            center[0] + dist * cos(angle),
            center[1] + dist * sin(angle),
          ]);
        }
      }

      final sternResult = validator.validateQuality(
        coordinates: sternCoords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 50.0,
      );

      // Loop sollte deutlich bessere shapePenalty haben als Stern
      expect(loopResult.shapePenalty, lessThan(sternResult.shapePenalty));
      expect(loopResult.centerReentryCount, equals(0));
    });

    test('Stern-Route mit mehreren Armen hat hohe shapePenalty', () {
      // Stern mit 4 Armen vom Zentrum (Dornbirn)
      final coords = <List<double>>[];
      const center = [9.74, 47.41];

      // 4 Arme: raus und zurück zum Zentrum
      for (var arm = 0; arm < 4; arm++) {
        final angle = arm * 90.0 * 3.14159 / 180.0;
        // Raus
        for (var i = 0; i <= 8; i++) {
          final dist = i * 0.01;
          coords.add([
            center[0] + dist * cos(angle),
            center[1] + dist * sin(angle),
          ]);
        }
        // Zurück zum Zentrum
        for (var i = 8; i >= 0; i--) {
          final dist = i * 0.01;
          coords.add([
            center[0] + dist * cos(angle),
            center[1] + dist * sin(angle),
          ]);
        }
      }

      final result = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 50.0,
      );

      // Stern sollte hohe Penalty haben (>40) und Route sollte nicht bestehen
      expect(result.shapePenalty, greaterThan(40.0));
      expect(result.passed, isFalse); // Stern-Route soll abgelehnt werden
    });

    test('A→B Route mit vielen Corridor-Wechseln hat hohe shapePenalty', () {
      // Zickzack von Dornbirn nach Feldkirch
      final coords = <List<double>>[];
      const start = [9.74, 47.41]; // Dornbirn
      const end = [9.60, 47.24]; // Feldkirch

      for (var i = 0; i <= 20; i++) {
        final t = i / 20.0;
        final baseX = start[0] + (end[0] - start[0]) * t;
        final baseY = start[1] + (end[1] - start[1]) * t;
        // Starkes Zickzack links/rechts vom Korridor
        final offset = (i % 2 == 0 ? 0.03 : -0.03);
        coords.add([baseX + offset, baseY]);
      }

      final result = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: false,
        targetDistanceKm: 25.0,
        actualDistanceKm: 25.0,
      );

      // Zigzag sollte als microZigzag erkannt werden
      expect(result.microZigzagPercent, greaterThan(50.0));
    });

    test('Sport-Stil bestraft microZigzag stärker', () {
      // Route mit vielen kleinen Richtungswechseln
      final coords = <List<double>>[];
      for (var i = 0; i < 60; i++) {
        final zigzag = (i % 3 == 0 ? 0.002 : (i % 3 == 1 ? -0.002 : 0.0));
        coords.add([9.74 + i * 0.003 + zigzag, 47.41 + i * 0.001]);
      }
      // Zurück zum Start für Loop
      coords.add([9.74, 47.41]);

      final quality = validator.validateQuality(
        coordinates: coords,
        isRoundTrip: true,
        targetDistanceKm: 50.0,
        actualDistanceKm: 50.0,
      );

      final sportScore = validator.classifyGeneratedRoute(
        quality: quality,
        isRoundTrip: true,
        coordinateCount: coords.length,
        actualDistanceKm: 50.0,
        targetDistanceKm: 50.0,
        styleProfileKey: 'sport',
      ).score;

      final entdeckerScore = validator.classifyGeneratedRoute(
        quality: quality,
        isRoundTrip: true,
        coordinateCount: coords.length,
        actualDistanceKm: 50.0,
        targetDistanceKm: 50.0,
        styleProfileKey: 'entdecker',
      ).score;

      // Sport sollte Zigzag stärker bestrafen als Entdecker
      expect(sportScore, greaterThan(entdeckerScore));
    });
  });
}

double cos(double x) => x.isNaN ? 0 : _cos(x);
double sin(double x) => x.isNaN ? 0 : _sin(x);
double _cos(double x) {
  // Simple Taylor series approximation
  x = x % (2 * 3.14159);
  return 1 - x * x / 2 + x * x * x * x / 24;
}
double _sin(double x) {
  x = x % (2 * 3.14159);
  return x - x * x * x / 6 + x * x * x * x * x / 120;
}
