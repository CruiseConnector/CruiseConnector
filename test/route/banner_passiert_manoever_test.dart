import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-28 (Fehler 9, kritisch): „Da steht schon die ganze Zeit ich muss
/// links abbiegen, obwohl ich schon links abgebogen bin, und sie verschwindet
/// nicht — oder es kommt dann nicht die naechste Anzeige."
///
/// Ursache: Der diskrete Routenindex rueckt erst vor, wenn 92 Prozent des
/// FOLGE-Segments gefahren sind. Auf einer langen geraden Strasse stand er
/// nach dem Abbiegen deshalb minutenlang AUF dem Manoeverpunkt, und die
/// Auswahl hielt das gefahrene Manoever als „Jetzt" aktiv. Durchgerechnet:
/// 620-m-Segment bei 47 km/h = 44 Sekunden Geisterbanner, bei 22 km/h sind
/// es 95 Sekunden.
///
/// Die Reparatur: Die stetige Fahrstrecke entlang der Route entscheidet, ob
/// ein Manoever gefahren ist — mit 20 m Hysterese gegen Zappeln.
RouteManeuver _m(
  int idx, {
  ManeuverType typ = ManeuverType.normal,
  String text = 'x',
  bool ankunft = false,
}) => RouteManeuver(
  latitude: 51.23,
  longitude: 6.77,
  routeIndex: idx,
  icon: ankunft ? Icons.flag : Icons.turn_left,
  announcement: text,
  instruction: text,
  maneuverType: typ,
);

void main() {
  // Route: Abbiegen bei Punkt 10 (bei Meter 500), naechstes Manoever bei
  // Punkt 40 (Meter 2000), Ziel bei Punkt 60 (Meter 3000).
  final man = <RouteManeuver>[
    _m(10, text: 'Links abbiegen auf Radetzkystrasse'),
    _m(40, text: 'Rechts abbiegen'),
    _m(60, ankunft: true, text: 'Ziel erreicht.'),
  ];
  // Kumulierte Meter: Punkt i liegt bei i * 50 m.
  final cum = List<double>.generate(61, (i) => i * 50.0);

  int? aktiv({required int index, double? stetig, double rest = 2500}) =>
      selectActiveGuidanceManeuverIndex(
        maneuvers: man,
        currentRouteIndex: index,
        remainingRouteDistanceMeters: rest,
        distanceToFinalTargetMeters: rest,
        startIndex: 0,
        passiertBisRouteMeter: stetig,
        cumulativeDistances: cum,
      );

  group('Nach dem Abbiegen wechselt das Banner, ohne auf den Index zu warten', () {
    test('vor dem Manoever bleibt es aktiv', () {
      // 30 m davor: Index 10 noch nicht erreicht, stetig 470 m.
      expect(aktiv(index: 9, stetig: 470), 0);
    });

    test('genau am Manoever bleibt es „jetzt"', () {
      // Die Kreisverkehr-Regel vom 26.08.: Gleichheit heisst jetzt.
      expect(aktiv(index: 10, stetig: 500), 0);
      // Innerhalb der Hysterese (bis 20 m dahinter) auch noch.
      expect(aktiv(index: 10, stetig: 519), 0);
    });

    test('BELEG UND FIX: 25 m nach dem Abbiegen kommt das naechste', () {
      // Der Index steht noch auf 10 (92-Prozent-Regel, langes Folgesegment),
      // aber die stetige Strecke ist schon 25 m weiter. Vorher zeigte das
      // Banner hier weiter „Jetzt · Links abbiegen".
      expect(aktiv(index: 10, stetig: 525), 1, reason: 'gefahren ist gefahren');
      // Und bleibt so, bis der Index irgendwann nachkommt.
      expect(aktiv(index: 10, stetig: 900), 1);
    });

    test('ohne stetige Strecke exakt das alte Verhalten', () {
      // Alte Aufrufer (Tests, Live-Activity) reichen nichts durch.
      expect(aktiv(index: 10, stetig: null), 0);
      expect(aktiv(index: 11, stetig: null), 1);
    });
  });

  group('Die Ausnahmen bleiben geschuetzt', () {
    test('Kreisverkehr wird beim Kreisen nicht weggeschaltet', () {
      final ring = <RouteManeuver>[
        _m(10, typ: ManeuverType.roundabout, text: 'Ausfahrt 2 nehmen'),
        _m(40, text: 'Rechts abbiegen'),
      ];
      final i = selectActiveGuidanceManeuverIndex(
        maneuvers: ring,
        currentRouteIndex: 10,
        remainingRouteDistanceMeters: 2500,
        distanceToFinalTargetMeters: 2500,
        startIndex: 0,
        // 80 m im Ring gefahren — die Ansage muss stehen bleiben.
        passiertBisRouteMeter: 580,
        cumulativeDistances: cum,
      );
      expect(i, 0, reason: 'im Ring braucht man die Ausfahrt-Ansage');
    });

    test('das echte Ziel wird nie durch die Hysterese uebersprungen', () {
      // Stetig weit hinter dem Ziel (GPS-Auslauf am Ende): Ankunft bleibt.
      final i = selectActiveGuidanceManeuverIndex(
        maneuvers: man,
        currentRouteIndex: 59,
        remainingRouteDistanceMeters: 20,
        distanceToFinalTargetMeters: 20,
        startIndex: 0,
        passiertBisRouteMeter: 3050,
        cumulativeDistances: cum,
      );
      expect(i, 2);
    });

    test('eine kaputte Indexlage stuerzt nicht ab', () {
      final schief = <RouteManeuver>[_m(999, text: 'ausserhalb')];
      final i = selectActiveGuidanceManeuverIndex(
        maneuvers: schief,
        currentRouteIndex: 0,
        remainingRouteDistanceMeters: 100,
        distanceToFinalTargetMeters: 100,
        startIndex: 0,
        passiertBisRouteMeter: 50,
        cumulativeDistances: cum,
      );
      expect(i, 0, reason: 'Index ausserhalb der Kumulierten: keine Wertung');
    });
  });
}
