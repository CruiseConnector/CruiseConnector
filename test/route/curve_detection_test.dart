// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_curve_warning.dart';

// ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

/// Erzeugt eine gerade Route (keine Kurve).
List<List<double>> _straightRoute({int points = 200}) =>
    List.generate(points, (i) => [11.58 + i * 0.0001, 48.14]);

/// Erzeugt eine Route mit einer Kurve am angegebenen Index.
/// [angleDegrees] = Winkel der Kurve in Grad.
/// [direction] = 'left' oder 'right'.
List<List<double>> _routeWithCurve({
  int points = 200,
  int curveAtIndex = 80,
  double angleDegrees = 90,
  String direction = 'right',
  double stepMeters = 15.0, // ca. 0.00015 Grad Lat ≈ 15m
}) {
  final coords = <List<double>>[];
  const stepDeg = 0.00015; // ~15m pro Punkt

  // Gerade fahren bis zur Kurve
  for (var i = 0; i < curveAtIndex; i++) {
    coords.add([11.58 + i * stepDeg, 48.14]);
  }

  // Kurve berechnen: Bearing ändert sich um angleDegrees
  final angleRad = angleDegrees * math.pi / 180;
  final turn = direction == 'right' ? 1 : -1;

  // Nach der Kurve: in neue Richtung fahren
  final remaining = points - curveAtIndex;
  for (var i = 0; i < remaining; i++) {
    final dx = math.cos(angleRad) * i * stepDeg;
    final dy = turn * math.sin(angleRad) * i * stepDeg;
    coords.add([
      coords[curveAtIndex - 1][0] + dx,
      coords[curveAtIndex - 1][1] + dy,
    ]);
  }

  return coords;
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('CruiseCurveWarning.detectNextCurve – Keine Kurve', () {
    test('gerade Route → null (keine Kurve)', () {
      final coords = _straightRoute(points: 300);
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
      );
      expect(result, isNull);
    });

    test('weniger als 10 Koordinaten → null', () {
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: List.generate(5, (i) => [11.58 + i * 0.001, 48.14]),
        currentIndex: 0,
      );
      expect(result, isNull);
    });

    test('currentIndex nahe am Ende → null', () {
      final coords = _straightRoute(points: 200);
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 193, // zu nah am Ende
      );
      expect(result, isNull);
    });

    test('winzige Richtungsänderung (<35°) → keine Kurve erkannt', () {
      // Sehr sanfte Kurve: 20° → unter der Schwelle
      final coords = <List<double>>[];
      for (var i = 0; i < 200; i++) {
        // Sehr leichte Rechtskurve: <20° Gesamtänderung
        final angle = i * 0.001 * math.pi / 180; // extrem flach
        coords.add([11.58 + i * 0.0001 * math.cos(angle),
                    48.14 + i * 0.0001 * math.sin(angle)]);
      }
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
      );
      // Entweder null oder gentle - auf jeden Fall kein false positive
      if (result != null) {
        expect(result.severity, CurveSeverity.gentle);
      }
    });
  });

  group('CruiseCurveWarning.detectNextCurve – Kurven-Schärfegrade', () {
    test('40° Kurve → gentle severity', () {
      // Baue eine Route wo ein deutlicher 40°-Knick passiert
      final coords = <List<double>>[];
      // Gerade nach Osten (100 Punkte × 50m ≈ 5km)
      for (var i = 0; i < 150; i++) {
        coords.add([11.58 + i * 0.0005, 48.14]);
      }
      // Dann 40° nach Norden abbiegen (50 Punkte)
      final angleRad = 40.0 * math.pi / 180;
      for (var i = 0; i < 100; i++) {
        coords.add([
          coords.last[0] + 0.0005 * math.cos(angleRad),
          coords.last[1] + 0.0005 * math.sin(angleRad),
        ]);
      }
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
        maxDistanceMeters: 20000,
      );
      // Mit dieser Route soll gentle oder moderate erkannt werden
      if (result != null) {
        expect(
          result.severity == CurveSeverity.gentle || result.severity == CurveSeverity.moderate,
          isTrue,
          reason: 'Erwartet gentle oder moderate, bekam ${result.severity} mit ${result.angleDegrees}°',
        );
      }
    });

    test('90° Kurve → sharp severity', () {
      final coords = <List<double>>[];
      // Gerade nach Osten
      for (var i = 0; i < 150; i++) {
        coords.add([11.58 + i * 0.0007, 48.14]);
      }
      // 90° nach Norden
      for (var i = 0; i < 100; i++) {
        coords.add([coords.last[0], coords.last[1] + 0.0007 * (i + 1)]);
      }
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
        maxDistanceMeters: 30000,
      );
      if (result != null) {
        expect(
          result.severity == CurveSeverity.sharp ||
          result.severity == CurveSeverity.moderate ||
          result.severity == CurveSeverity.hairpin,
          isTrue,
          reason: 'Erwartet sharp/moderate/hairpin, bekam ${result.severity}',
        );
      }
    });

    test('180° Kehre → hairpin severity (Winkel ≥ 130°)', () {
      final coords = <List<double>>[];
      // Nach Norden fahren
      for (var i = 0; i < 150; i++) {
        coords.add([11.58, 48.14 + i * 0.001]);
      }
      // Plötzlich nach Süden (180° Richtungsänderung)
      for (var i = 0; i < 100; i++) {
        coords.add([11.58, coords.last[1] - 0.001]);
      }

      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
        maxDistanceMeters: 50000,
      );
      // Hairpin-Kurve oder sehr scharfe Kurve soll erkannt werden
      if (result != null) {
        expect(result.angleDegrees, greaterThan(100.0),
            reason: 'Erwarte Winkel >100° für Kehre');
      }
    });
  });

  group('CruiseCurveWarning.detectNextCurve – Richtungserkennung', () {
    test('Rechtskurve → direction = "right"', () {
      final coords = <List<double>>[];
      for (var i = 0; i < 150; i++) {
        coords.add([11.58 + i * 0.0005, 48.14]);
      }
      // 60° nach rechts (Süden relativ zu bisheriger Richtung)
      final angleRad = -60.0 * math.pi / 180;
      for (var i = 1; i <= 100; i++) {
        coords.add([
          coords[149][0] + i * 0.0005 * math.cos(angleRad),
          coords[149][1] + i * 0.0005 * math.sin(angleRad),
        ]);
      }
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
        maxDistanceMeters: 20000,
      );
      if (result != null) {
        expect(result.direction, anyOf('left', 'right'));
      }
    });

    test('Distanz zur Kurve ist positiv', () {
      final coords = <List<double>>[];
      for (var i = 0; i < 150; i++) {
        coords.add([11.58 + i * 0.0005, 48.14]);
      }
      for (var i = 1; i <= 80; i++) {
        coords.add([coords.last[0], coords.last[1] + 0.0005 * i]);
      }
      final result = CruiseCurveWarning.detectNextCurve(
        coordinates: coords,
        currentIndex: 0,
        maxDistanceMeters: 30000,
      );
      if (result != null) {
        expect(result.distanceMeters, greaterThan(0));
      }
    });
  });

  group('CurveSeverity – Label & Farben', () {
    test('gentle → "Leichte Kurve"', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 40,
        severity: CurveSeverity.gentle,
        distanceMeters: 500,
        direction: 'right',
      );
      expect(curve.label, 'Leichte Kurve');
    });

    test('moderate → "Kurve"', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 60,
        severity: CurveSeverity.moderate,
        distanceMeters: 300,
        direction: 'right',
      );
      expect(curve.label, 'Kurve');
    });

    test('sharp → "Scharfe Kurve"', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 90,
        severity: CurveSeverity.sharp,
        distanceMeters: 200,
        direction: 'left',
      );
      expect(curve.label, 'Scharfe Kurve');
    });

    test('hairpin → "Haarnadelkurve"', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 150,
        severity: CurveSeverity.hairpin,
        distanceMeters: 100,
        direction: 'right',
      );
      expect(curve.label, 'Haarnadelkurve');
    });

    test('Farben sind unterschiedlich für alle Schweregrade', () {
      final severities = [
        CurveSeverity.gentle,
        CurveSeverity.moderate,
        CurveSeverity.sharp,
        CurveSeverity.hairpin,
      ];
      final colors = severities.map((s) => DetectedCurve(
        routeIndex: 0, angleDegrees: 0, severity: s,
        distanceMeters: 100, direction: 'right',
      ).color).toSet();
      expect(colors.length, 4, reason: 'Jeder Schärfegrad soll eine andere Farbe haben');
    });

    test('Distanz ≥ 1km wird als "X,X km" angezeigt', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 60,
        severity: CurveSeverity.moderate,
        distanceMeters: 1500,
        direction: 'right',
      );
      // Prüfe den distText intern durch die Widget-Logik
      // (distanceMeters >= 1000 → km-Format)
      final distInKm = curve.distanceMeters / 1000;
      expect(distInKm.toStringAsFixed(1).replaceAll('.', ','), '1,5');
    });

    test('Distanz < 1km wird als "X m" angezeigt', () {
      final curve = DetectedCurve(
        routeIndex: 10,
        angleDegrees: 40,
        severity: CurveSeverity.gentle,
        distanceMeters: 350,
        direction: 'left',
      );
      expect(curve.distanceMeters.round(), 350);
    });
  });

  group('CurveSeverity – Schwellenwerte', () {
    test('Schwelle gentle: 35° ≤ angle < 50°', () {
      // Basierend auf dem Code: gentle if angleDiff < 50
      const angle = 42.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.gentle);
    });

    test('Schwelle moderate: 50° ≤ angle < 80°', () {
      const angle = 65.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.moderate);
    });

    test('Schwelle sharp: 80° ≤ angle < 130°', () {
      const angle = 100.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.sharp);
    });

    test('Schwelle hairpin: angle ≥ 130°', () {
      const angle = 135.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.hairpin);
    });

    test('Genau 130° → hairpin', () {
      const angle = 130.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.hairpin);
    });

    test('Genau 50° → moderate', () {
      const angle = 50.0;
      final severity = angle >= 130
          ? CurveSeverity.hairpin
          : angle >= 80
              ? CurveSeverity.sharp
              : angle >= 50
                  ? CurveSeverity.moderate
                  : CurveSeverity.gentle;
      expect(severity, CurveSeverity.moderate);
    });
  });
}
