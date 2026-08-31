import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/domain/models/saved_route.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/presentation/pages/ride_detail_page.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';
import 'package:cruise_connect/presentation/widgets/social/route_attachment_card.dart';
import 'package:cruise_connect/presentation/widgets/social/route_verlauf_sketch.dart';

/// 2026-08-28 (Fehler 7 und 8): Das neue Teilen-Design ohne Karte.
///
/// Zusicherungen:
///  * Die Skizze rendert ohne Ausnahme bei LineString, MultiLineString und
///    leerer Geometrie.
///  * Die Hoechsttempo-Kachel erscheint NUR, wenn ein Wert existiert —
///    fehlt er, fehlt die Kachel (kein Strich).
///  * Fuer fremde Routen steht KEIN MapLibre-Widget im Baum, nur die
///    nachgezeichnete Strecke.
///  * In keinem Nutzertext stehen Binde- oder Gedankenstriche.
void main() {
  const accent = Color(0xFFFF4438);

  /// Leicht geschwungene Linie, ~5 km, Punktabstand ~100 m — lang genug,
  /// damit nach der Kappung mehr als der Mindestrest uebrig bleibt.
  List<List<double>> langeLinie() {
    const schritt = 0.1 / 75.93;
    return [
      for (var i = 0; i < 51; i++)
        [9.70 + i * schritt, 47.0 + 0.004 * math.sin(i / 6)],
    ];
  }

  SavedRoute route({
    Map<String, dynamic>? geometry,
    double? topSpeedKmh,
    String? userId,
  }) {
    return SavedRoute(
      id: 'r1',
      createdAt: DateTime(2026, 8, 28, 18, 30),
      style: 'Kurvenjagd',
      distanceKm: 26.7,
      durationSeconds: 1800,
      name: 'Bodensee Runde',
      geometry:
          geometry ??
          {'type': 'LineString', 'coordinates': langeLinie()},
      topSpeedKmh: topSpeedKmh,
      userId: userId,
    );
  }

  Widget rahmen(Widget kind) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      body: Center(
        child: SizedBox(width: 360, child: kind),
      ),
    ),
  );

  void keineStriche(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final s = t.data ?? t.textSpan?.toPlainText() ?? '';
      expect(s.contains('—'), isFalse, reason: 'Gedankenstrich in "$s"');
      expect(s.contains('–'), isFalse, reason: 'Halbgeviert in "$s"');
      expect(s.contains('--'), isFalse, reason: 'Doppelstrich in "$s"');
    }
  }

  group('RouteVerlaufSketch rendert ohne Ausnahme', () {
    testWidgets('LineString', (tester) async {
      final r = route();
      await tester.pumpWidget(
        rahmen(
          SizedBox(
            height: 140,
            child: RouteVerlaufSketch(punkte: r.flatCoordinates, accent: accent),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Lang genug: die Linie wird wirklich gezeichnet (kein Platzhalter).
      expect(
        find.descendant(
          of: find.byType(RouteVerlaufSketch),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('MultiLineString (GPS-Luecke)', (tester) async {
      final linie = langeLinie();
      final r = route(
        geometry: {
          'type': 'MultiLineString',
          'coordinates': [
            linie.sublist(0, 26),
            linie.sublist(28),
          ],
        },
      );
      await tester.pumpWidget(
        rahmen(
          SizedBox(
            height: 140,
            child: RouteVerlaufSketch(punkte: r.flatCoordinates, accent: accent),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('leere Geometrie zeigt den Platzhalter statt zu werfen', (
      tester,
    ) async {
      final r = route(geometry: const {});
      await tester.pumpWidget(
        rahmen(
          SizedBox(
            height: 140,
            child: RouteVerlaufSketch(punkte: r.flatCoordinates, accent: accent),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    });

    testWidgets('zu kurze Route (unter dem Mindestrest) wirft nicht', (
      tester,
    ) async {
      final r = route(
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [9.70, 47.0],
            [9.71, 47.0],
          ],
        },
      );
      await tester.pumpWidget(
        rahmen(
          SizedBox(
            height: 140,
            child: RouteVerlaufSketch(punkte: r.flatCoordinates, accent: accent),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    });
  });

  group('Eckdaten wie beim Exportieren', () {
    testWidgets('Hoechsttempo-Kachel NUR wenn ein Wert existiert', (
      tester,
    ) async {
      await tester.pumpWidget(
        rahmen(RouteAttachmentStats(route: route(topSpeedKmh: 142))),
      );
      // 2026-09-01: Die Kachel heisst jetzt „Spitze 142 km/h". Es gibt
      // seither auch eine Schnitt-Kachel, und zwei Kacheln mit blossem
      // „km/h" waeren nicht auseinanderzuhalten.
      expect(find.text('Spitze 142 km/h'), findsOneWidget);
      keineStriche(tester);

      await tester.pumpWidget(rahmen(RouteAttachmentStats(route: route())));
      await tester.pump();
      expect(find.textContaining('km/h'), findsNothing);
      keineStriche(tester);
    });

    testWidgets('Distanz, Dauer und Stil stehen als Chips da', (tester) async {
      await tester.pumpWidget(rahmen(RouteAttachmentStats(route: route())));
      expect(find.text('26,7 km'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('Kurvenjagd'), findsOneWidget);
      keineStriche(tester);
    });
  });

  group('Fremde Route in der Detailansicht', () {
    UserDriveSession session({double? topSpeedKmh}) => UserDriveSession(
      id: 's1',
      userId: 'fremder-nutzer',
      distanceKm: 12.4,
      durationSeconds: 1800,
      xpAwarded: 120,
      completedAtEnd: true,
      createdAt: DateTime(2026, 8, 28, 18, 30),
      routeStyle: 'Kurvenjagd',
      routeType: 'ROUND_TRIP',
      trackGeometry: langeLinie(),
      topSpeedKmh: topSpeedKmh,
    );

    testWidgets('kein MapLibre-Widget im Baum, dafuer die Skizze', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: RideDetailPage(
            session: session(),
            allowPhoto: false,
            ohneKarte: true,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CruiseMapLibreMap), findsNothing);
      expect(find.byType(RouteVerlaufSketch), findsOneWidget);
      // Ohne Hoechsttempo-Wert existiert die Kachel nicht.
      expect(find.text('Höchsttempo'), findsNothing);
      keineStriche(tester);
    });

    testWidgets('Hoechsttempo-Kachel erscheint mit Wert', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: RideDetailPage(
            session: session(topSpeedKmh: 142),
            allowPhoto: false,
            ohneKarte: true,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Höchsttempo'), findsOneWidget);
      expect(find.text('142 km/h'), findsOneWidget);
    });
  });

  group('Quelle: die Verdrahtung bleibt', () {
    test('fromSavedRoute schaltet fuer fremde Routen die Karte ab', () {
      final quelle = File(
        'lib/presentation/pages/ride_detail_page.dart',
      ).readAsStringSync();
      expect(quelle.contains('ohneKarte: !isOwn'), isTrue);
      expect(quelle.contains('kappeEndstuecke('), isTrue);
    });

    test('die Beitrags-Karte kennt keine Basemap', () {
      final quelle = File(
        'lib/presentation/widgets/social/route_attachment_card.dart',
      ).readAsStringSync();
      expect(quelle.contains('RouteVerlaufSketch('), isTrue);
      expect(quelle.contains('CruiseMapLibreMap'), isFalse);
      expect(quelle.contains('MapLibre'), isFalse);
    });
  });
}
