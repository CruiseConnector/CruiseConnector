import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko, Testfahrt vom 25.08. mit Bildschirmaufnahme):
/// Drei Befunde aus 46 Minuten Video, jeder mit Uhrzeit belegt.
RouteManeuver _m(int idx, {IconData icon = Icons.turn_right, String text = 'x'}) =>
    RouteManeuver(
      latitude: 47.31,
      longitude: 9.68,
      routeIndex: idx,
      icon: icon,
      announcement: text,
      instruction: text,
      maneuverType: ManeuverType.normal,
    );

RouteManeuver _ankunft(int idx) => _m(idx, icon: Icons.flag, text: 'Ziel erreicht.');

void main() {
  group('22:22 bis 22:31 — das Banner darf nicht neun Minuten verschwinden', () {
    // Nach einem Reroute wird die Anfahrt-Teilroute an die Restroute genaeht.
    // Sie bringt ihr eigenes „Ziel erreicht." mit, das dadurch MITTEN in der
    // Route landet. Genau davor stand der Fahrer minutenlang ohne Ansage.
    final genaeht = <RouteManeuver>[
      _m(5, text: 'Links abbiegen'),
      _ankunft(12), // Naht der Anfahrt-Teilroute, NICHT das echte Ziel
      _m(40, text: 'Scharf links auf Stutz'),
      _m(90, text: 'Rechts abbiegen'),
      _ankunft(140), // das echte Ziel
    ];

    int? aktiv(int index, {double rest = 12000}) =>
        selectActiveGuidanceManeuverIndex(
          maneuvers: genaeht,
          currentRouteIndex: index,
          remainingRouteDistanceMeters: rest,
          distanceToFinalTargetMeters: rest,
          startIndex: 0,
        );

    test('die Naht-Ankunft wird uebersprungen statt das Banner abzuschalten', () {
      // Puck hinter dem ersten Abbieger, vor der Naht: frueher kam hier null.
      expect(aktiv(6), 2, reason: 'naechstes echtes Manoever, nicht null');
      expect(aktiv(12), 2);
      expect(aktiv(39), 2);
    });

    test('nach der Naht laeuft die Ansage normal weiter', () {
      expect(aktiv(41), 3, reason: 'Rechts abbiegen');
    });

    test('das ECHTE Ziel am Ende verhaelt sich unveraendert', () {
      // Weit weg: keine Ankunftsansage.
      expect(aktiv(91, rest: 12000), isNull);
      // In Zielnaehe: Ankunftsansage.
      expect(aktiv(91, rest: 30), 4);
    });

    test('ohne Naht-Ankunft bleibt alles wie bisher', () {
      final sauber = <RouteManeuver>[_m(5), _m(40), _ankunft(140)];
      int? a(int i, double rest) => selectActiveGuidanceManeuverIndex(
        maneuvers: sauber,
        currentRouteIndex: i,
        remainingRouteDistanceMeters: rest,
        distanceToFinalTargetMeters: rest,
        startIndex: 0,
      );
      expect(a(0, 9000), 0);
      expect(a(6, 9000), 1);
      expect(a(41, 9000), isNull, reason: 'Ziel noch weit: kein Banner');
      expect(a(41, 30), 2, reason: 'Ziel nah: Ankunft');
    });
  });

  group('22:20 — kein erzwungener Reroute, wenn der Fahrer auf der Route ist', () {
    bool feuert({
      bool lockReleased = false,
      bool onRoute = false,
      double accuracy = 8.0,
      int sekunden = 20,
      double gefahren = 200,
      double tempo = 9.0,
    }) => shouldForceRerouteOnFrozenProgress(
      sinceProgressChanged: Duration(seconds: sekunden),
      speedMps: tempo,
      approachingDestination: false,
      nearRouteEnd: false,
      drivenSinceProgressChangedM: gefahren,
      lockReleased: lockReleased,
      onRoute: onRoute,
      accuracyMeters: accuracy,
    );

    test('echter Haenger abseits der Route feuert weiterhin', () {
      expect(feuert(), isTrue);
    });

    test('im Korridor NIE — das ist ein Anzeigefehler, kein Routenfehler', () {
      expect(feuert(onRoute: true), isFalse);
    });

    test('freigegebene Anzeigesperre zaehlt nicht als eingefroren', () {
      expect(feuert(lockReleased: true), isFalse);
    });

    test('bei schlechtem Empfang nie erzwingen', () {
      expect(feuert(accuracy: 40), isFalse);
      expect(feuert(accuracy: 25), isTrue, reason: 'genau an der Grenze noch ja');
    });

    test('die alten Schranken gelten unveraendert', () {
      expect(feuert(sekunden: 10), isFalse, reason: 'zu kurz eingefroren');
      expect(feuert(gefahren: 40), isFalse, reason: 'zu wenig gefahren');
      expect(feuert(tempo: 2), isFalse, reason: 'steht praktisch');
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 20),
          speedMps: 9,
          approachingDestination: false,
          nearRouteEnd: false,
          drivenSinceProgressChangedM: 200,
          inRoundabout: true,
        ),
        isFalse,
        reason: 'Kreisverkehr-Schutz vom 15.08. bleibt',
      );
    });

    test('ohne Angaben verhaelt sich der Waechter wie vorher', () {
      // Alte Aufrufer ohne die neuen Angaben duerfen sich nicht aendern.
      expect(
        shouldForceRerouteOnFrozenProgress(
          sinceProgressChanged: const Duration(seconds: 20),
          speedMps: 9,
          approachingDestination: false,
          nearRouteEnd: false,
          drivenSinceProgressChangedM: 200,
        ),
        isTrue,
      );
    });
  });
}
