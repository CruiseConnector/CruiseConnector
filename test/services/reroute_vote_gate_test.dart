import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-15 (vucko N1, Geräte-Fahrt 23min): Kaltstart-Phantom-Reroutes.
/// Der sichtbare Puck ist route-locked (klebt auf der Linie); die Off-Route-
/// Prüfung lief aber auf ROHEM GPS, das am Fahrtbeginn seitlich ausreißt
/// (Multipath/Schlucht/Access-Leg-Versatz) → grundlose „Neue Strecke übernommen".
/// [rerouteVoteAllowed] ist das Mapbox-/Apple-Gating dagegen.
void main() {
  // A→B-Korridor (Basis 300m). 2× = 600m.
  const corridor = 300.0;

  group('rerouteVoteAllowed — Kaltstart-Gating', () {
    test('Unqualifizierter Fix (>100m Accuracy) votet NIE — auch eingerastet', () {
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 150,
          routeLockedOn: true,
          offRouteDistanceMeters: 1000,
          corridorMeters: corridor,
        ),
        isFalse,
        reason: 'Mapbox isQualified: Accuracy >100m fällt komplett aus der Wertung',
      );
    });

    test('Ungültige Accuracy (≤0) votet NIE', () {
      for (final acc in [0.0, -1.0]) {
        expect(
          rerouteVoteAllowed(
            accuracyMeters: acc,
            routeLockedOn: true,
            offRouteDistanceMeters: 1000,
            corridorMeters: corridor,
          ),
          isFalse,
          reason: 'Accuracy $acc ist ungültig',
        );
      }
    });

    test('PHANTOM: Kaltstart + moderate Abweichung (<2× Korridor) → kein Reroute',
        () {
      // Genau der Geräte-Fall: noch nicht eingerastet, GPS reißt 350m aus
      // (>Korridor, aber kein eindeutiges Verfahren). Der gesnappte Puck wirkt
      // dead-on → der Nutzer sieht keinen Grund. Muss unterdrückt werden.
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 20,
          routeLockedOn: false,
          offRouteDistanceMeters: 350,
          corridorMeters: corridor,
        ),
        isFalse,
      );
    });

    test('Kaltstart + großes Verfahren (>2× Korridor) + gute Accuracy → Reroute',
        () {
      // Wirklich falsch gestartet (700m daneben, sauberes GPS) — muss feuern.
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 20,
          routeLockedOn: false,
          offRouteDistanceMeters: 700,
          corridorMeters: corridor,
        ),
        isTrue,
      );
    });

    test('Kaltstart + großes Verfahren aber SCHLECHTE Accuracy (60m) → noch warten',
        () {
      // 60m Accuracy ist qualifiziert (≤100m), aber nicht „gut" (≤35m). Vor dem
      // Einrasten ist das eher Multipath als echtes Verfahren → unterdrücken.
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 60,
          routeLockedOn: false,
          offRouteDistanceMeters: 700,
          corridorMeters: corridor,
        ),
        isFalse,
      );
    });

    test('Eingerastet: normale (schnelle) Off-Route-Logik gilt voll', () {
      // Mid-Drive-Verfahren, das früher zu spät kam (L2/J1) — darf NICHT
      // unterdrückt werden, sobald der Puck einmal eingerastet war.
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 12,
          routeLockedOn: true,
          offRouteDistanceMeters: 400, // >Korridor, <2× — genuine
          corridorMeters: corridor,
        ),
        isTrue,
      );
    });

    test('Eingerastet + moderate Accuracy (60m) + Verfahren → Reroute', () {
      expect(
        rerouteVoteAllowed(
          accuracyMeters: 60,
          routeLockedOn: true,
          offRouteDistanceMeters: 700,
          corridorMeters: corridor,
        ),
        isTrue,
      );
    });
  });
}
