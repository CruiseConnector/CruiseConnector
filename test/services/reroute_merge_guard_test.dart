import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';

/// 2026-06-08 (vucko Task #47): sichert den Naht-Guard gegen die „Bat-Wing"-
/// Reroute-Geometrie ab — die zusammengesetzte Route (Connector + Original-Rest)
/// darf sich an der Naht nicht zurückfalten / selbst überschneiden.
void main() {
  // Hilfen: Punkte in [lng, lat]. Wir bauen in einer flachen lokalen Ebene
  // (lng≈x, lat≈y), die Heuristik arbeitet planar — das reicht für den Test.
  List<double> p(double lng, double lat) => [lng, lat];

  group('segmentsProperlyIntersect', () {
    test('sich kreuzende Segmente → true', () {
      expect(
        segmentsProperlyIntersect(p(0, 0), p(2, 2), p(0, 2), p(2, 0)),
        isTrue,
      );
    });
    test('parallele/getrennte Segmente → false', () {
      expect(
        segmentsProperlyIntersect(p(0, 0), p(2, 0), p(0, 1), p(2, 1)),
        isFalse,
      );
    });
    test('nur gemeinsamer Endpunkt (Naht) → false (kein proper cross)', () {
      expect(
        segmentsProperlyIntersect(p(0, 0), p(1, 1), p(1, 1), p(2, 0)),
        isFalse,
      );
    });
  });

  group('rerouteMergeFoldsBack', () {
    test('saubere Naht (Connector und Tail in gleicher Richtung) → false', () {
      // Connector fährt nach Osten und mündet sauber in den nach Osten
      // weiterlaufenden Original-Rest.
      final connector = [
        for (var i = 0; i < 10; i++) p(0.0 + i * 0.001, 47.5),
      ];
      final tail = [
        for (var i = 0; i < 30; i++) p(0.009 + i * 0.001, 47.5),
      ];
      expect(
        rerouteMergeFoldsBack(connector: connector, tail: tail),
        isFalse,
        reason: 'Geradlinige Anschlussfahrt darf nicht als Faltung gelten',
      );
    });

    test('zurückfaltende Naht (Tail läuft entgegengesetzt) → true', () {
      // Connector fährt nach Osten, Tail läuft danach nach WESTEN zurück
      // (klassischer Bat-Wing-Rückweg über dieselbe Spur).
      final connector = [
        for (var i = 0; i < 10; i++) p(0.0 + i * 0.001, 47.5),
      ];
      final tail = [
        for (var i = 0; i < 30; i++) p(0.009 - i * 0.001, 47.5001),
      ];
      expect(
        rerouteMergeFoldsBack(connector: connector, tail: tail),
        isTrue,
        reason: 'Gegenrichtungs-Tail muss als Rückfaltung erkannt werden',
      );
    });

    test('Connector kreuzt den Tail-Anfang (Schleife) → true', () {
      // Connector endet, indem es quer über den beginnenden Tail läuft.
      final connector = [
        p(0.000, 47.5000),
        p(0.002, 47.5000),
        p(0.004, 47.5010),
        p(0.003, 47.4995), // schlägt zurück nach unten/links → kreuzt Tail
      ];
      final tail = [
        p(0.0035, 47.5005),
        p(0.0015, 47.4998),
        p(-0.001, 47.4990),
      ];
      expect(
        rerouteMergeFoldsBack(connector: connector, tail: tail),
        isTrue,
      );
    });

    test('leere/zu kurze Eingaben → false (nicht bewertbar, nicht blocken)', () {
      expect(rerouteMergeFoldsBack(connector: [], tail: []), isFalse);
      expect(
        rerouteMergeFoldsBack(connector: [p(0, 0)], tail: [p(1, 1)]),
        isFalse,
      );
    });
  });
}
