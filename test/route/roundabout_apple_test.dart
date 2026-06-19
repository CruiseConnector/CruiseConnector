// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-19 (vucko Kreisverkehr 100% wie Apple — Geräte-Screenshots + Deep-
/// Research (18 Quellen adversarial) + OSRM-Bodenwahrheit): Die App vertraut
/// jetzt GraphHoppers topologie-abgeleiteter `exit_number` als EINZIGER Wahrheit
/// für die Ausfahrtszahl (wie Apple/Google ihrer Engine vertrauen). Die alte
/// 4-Arm-90°-Geometrie-Schätzung überschrieb die korrekte Zahl und erzeugte die
/// Screenshot-Fehler (z. B. „3. Ausfahrt" bei gerader Durchfahrt). Der Symbol-
/// PFEIL kommt separat aus dem echten Routen-Drehwinkel und kann der roten Linie
/// nie widersprechen.
void main() {
  late RouteService service;
  setUp(() => service = RouteService());

  // Meter-Helper um einen Vorarlberg-Punkt (Rechtsverkehr).
  const baseLat = 47.34, baseLng = 9.66;
  final mPerDegLng = 111320.0 * math.cos(baseLat * math.pi / 180.0);
  List<double> pt(double eastM, double northM) => [
        baseLng + eastM / mPerDegLng,
        baseLat + northM / 110540.0,
      ];

  Map<String, dynamic> ghResponse(
    int? exitNumber,
    String text,
    List<int> interval,
  ) => {
        'route': {
          'instructions': [
            {
              'sign': 6,
              if (exitNumber != null) 'exit_number': exitNumber,
              'text': text,
              'interval': interval,
            },
          ],
        },
      };

  group('GraphHopper exit_number ist die EINZIGE Wahrheit (Apple-Ansatz)', () {
    test('SCREENSHOT-1-REGRESSION: GH Exit 3 + gerade Durchfahrt → bleibt 3', () {
      // Route fährt gerade durch den Kreisel (Süd→Nord). Früher machte die
      // Geometrie daraus „2. Ausfahrt" — genau der Screenshot-Fehler.
      final coords = <List<double>>[
        pt(0, -40), pt(0, -30), pt(0, -20), pt(0, -10),
        pt(0, 0), // idx 4 = Einfahrt
        pt(3, 8), // idx 5 = im Ring
        pt(0, 16), // idx 6 = Austritt (weiter geradeaus Nord)
        pt(0, 30), pt(0, 44),
      ];
      final m = service.extractManeuvers(
        ghResponse(3, 'Im Kreisverkehr die dritte Ausfahrt nehmen', [4, 6]),
        coords,
      );
      expect(m, hasLength(1));
      expect(m.first.maneuverType, ManeuverType.roundabout);
      expect(m.first.roundaboutExitNumber, 3, reason: 'GH-Nummer NICHT überschreiben');
      expect(m.first.instruction, contains('dritte'));
    });

    test('OSRM-Bodenwahrheit „Im Buch": Exit 1 + Rechtskurve → bleibt 1', () {
      // OSRM lieferte hier exit=1, Kurs 22°→90° (klare Rechtskurve).
      final coords = <List<double>>[
        pt(0, -40), pt(0, -30), pt(0, -20), pt(0, -10),
        pt(0, 0), // idx 4 = Einfahrt (Kurs Nord)
        pt(8, 5), // idx 5
        pt(18, 6), // idx 6 = Austritt (Kurs Ost)
        pt(32, 6), pt(46, 6),
      ];
      final m = service.extractManeuvers(
        ghResponse(1, 'Im Kreisverkehr die erste Ausfahrt nehmen', [4, 6]),
        coords,
      );
      expect(m.first.roundaboutExitNumber, 1);
      expect(m.first.roundaboutTurnAngleRad, isNotNull);
      expect(m.first.roundaboutTurnAngleRad! > 0, isTrue,
          reason: 'Rechtskurve → positiver Drehwinkel');
    });

    test('Großer mehrarmiger Kreisel: GH Exit 5 bleibt 5', () {
      final coords = <List<double>>[
        pt(0, -40), pt(0, -30), pt(0, -20), pt(0, -10),
        pt(0, 0), pt(2, 8), pt(0, 16), pt(0, 30), pt(0, 44),
      ];
      final m = service.extractManeuvers(
        ghResponse(5, 'Im Kreisverkehr die fünfte Ausfahrt nehmen', [4, 6]),
        coords,
      );
      expect(m.first.roundaboutExitNumber, 5);
    });

    test('GH ohne exit_number → Geometrie-Fallback (nicht null bei klarer Kurve)',
        () {
      final coords = <List<double>>[
        pt(0, -40), pt(0, -30), pt(0, -20), pt(0, -10),
        pt(0, 0), pt(8, 5), pt(18, 6), pt(32, 6), pt(46, 6),
      ];
      final m = service.extractManeuvers(
        ghResponse(null, 'Im Kreisverkehr', [4, 6]),
        coords,
      );
      // Rechtskurve → Geometrie-Fallback liefert 1.
      expect(m.first.roundaboutExitNumber, 1);
    });
  });

  group('correctedRoundaboutExitNumber (pur)', () {
    test('Provider gesetzt → unverändert durchgereicht', () {
      expect(
        correctedRoundaboutExitNumber(providerExitNumber: 3, geomTurnRad: 0.0),
        3,
      );
      expect(
        correctedRoundaboutExitNumber(
            providerExitNumber: 2, geomTurnRad: -math.pi / 2),
        2,
      );
      expect(
        correctedRoundaboutExitNumber(providerExitNumber: 7, geomTurnRad: null),
        7,
      );
    });
    test('Provider null → Geometrie-Fallback', () {
      expect(
        correctedRoundaboutExitNumber(
            providerExitNumber: null, geomTurnRad: 90 * math.pi / 180),
        1,
      );
      expect(
        correctedRoundaboutExitNumber(
            providerExitNumber: null, geomTurnRad: -90 * math.pi / 180),
        3,
      );
      expect(
        correctedRoundaboutExitNumber(
            providerExitNumber: null, geomTurnRad: null),
        isNull,
      );
    });
  });

  group('RoundaboutSymbol rendert für JEDE Form ohne Crash', () {
    RouteManeuver ra({
      int? exit,
      double? turnRad,
      double? entry,
      double? exitB,
      List<double>? arms,
      bool arrival = false,
    }) => RouteManeuver(
          latitude: 47.34,
          longitude: 9.66,
          routeIndex: 4,
          icon: Icons.roundabout_right,
          announcement: 'Im Kreisverkehr',
          instruction: 'Im Kreisverkehr',
          maneuverType: ManeuverType.roundabout,
          roundaboutExitNumber: exit,
          roundaboutTurnAngleRad: turnRad,
          roundaboutEntryBearing: entry,
          roundaboutExitBearing: exitB,
          roundaboutArmBearings: arms,
          roundaboutIsArrival: arrival,
        );

    Future<void> pumpSymbol(WidgetTester t, RouteManeuver m) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: RoundaboutSymbol(maneuver: m))),
      ));
      expect(find.byType(RoundaboutSymbol), findsOneWidget);
      expect(t.takeException(), isNull);
    }

    testWidgets('echte OSM-Arme (3-armig, asymmetrisch)', (t) async {
      await pumpSymbol(
          t, ra(exit: 2, entry: 180, exitB: 70, arms: [180, 70, 300]));
    });
    testWidgets('KEINE Arme → synthetischer Kreisel (Pfeil aus Geometrie)',
        (t) async {
      await pumpSymbol(t, ra(exit: 3, turnRad: 0.0)); // gerade
    });
    testWidgets('Exit 3 + gerade (Screenshot-1-Fall) — Pfeil folgt Geometrie',
        (t) async {
      await pumpSymbol(t, ra(exit: 3, turnRad: 0.05));
    });
    testWidgets('Linkskurve', (t) async {
      await pumpSymbol(t, ra(exit: 3, turnRad: -math.pi / 2));
    });
    testWidgets('Rechtskurve', (t) async {
      await pumpSymbol(t, ra(exit: 1, turnRad: math.pi / 2));
    });
    testWidgets('Ankunft am Kreisel', (t) async {
      await pumpSymbol(t, ra(exit: 2, turnRad: 0.0, arrival: true));
    });
    testWidgets('komplett leer (nur Nummer) → kein Crash', (t) async {
      await pumpSymbol(t, ra(exit: 1));
    });
  });
}
