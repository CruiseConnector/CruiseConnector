import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RouteManeuver _m(int idx, {IconData icon = Icons.turn_right}) => RouteManeuver(
  latitude: 47.0,
  longitude: 9.0,
  routeIndex: idx,
  icon: icon,
  announcement: 'x',
  instruction: 'x',
);

void main() {
  group('rotateManeuversForWrap (Rundkurs-Banner-Fix)', () {
    test('rotiert Indizes statt sie zu leeren + Ankunft ans Ende', () {
      final source = [
        _m(0), // depart
        _m(3),
        _m(7),
        _m(10, icon: Icons.flag), // arrival
      ];
      final out = rotateManeuversForWrap(source, 5, 12);

      // Vorher wurde hier const [] zurückgegeben → kein Banner. Jetzt non-empty.
      expect(out, isNotEmpty);

      // Nicht-Ankunfts-Manöver werden rotiert: 0→7, 3→10, 7→2; sortiert [2,7,10].
      final nonArrival = out
          .where((m) => !m.isArrival)
          .map((m) => m.routeIndex)
          .toList();
      expect(nonArrival, [2, 7, 10]);

      // Genau eine Ankunft, ans Ende gesetzt (N-1 = 11).
      final arrival = out.where((m) => m.isArrival).toList();
      expect(arrival, hasLength(1));
      expect(arrival.first.routeIndex, 11);

      // Aufsteigend sortiert.
      for (var i = 1; i < out.length; i++) {
        expect(out[i].routeIndex >= out[i - 1].routeIndex, isTrue);
      }
    });

    test('kein Wrap (clampedStart<=0) → unverändert', () {
      final source = [_m(2), _m(5)];
      expect(rotateManeuversForWrap(source, 0, 10), same(source));
    });

    test('leere Quelle → leer', () {
      expect(rotateManeuversForWrap(const [], 3, 10), isEmpty);
    });
  });

  group('maneuverPreAnnounceDistanceMeters (Autobahn-Voice-Timing)', () {
    test('skaliert mit Tempo — Autobahn deutlich früher als Ort', () {
      final city = maneuverPreAnnounceDistanceMeters(14); // ~50 km/h
      final hwy = maneuverPreAnnounceDistanceMeters(28); // ~100 km/h
      expect(hwy, greaterThan(city));
      expect(hwy, closeTo(784, 1)); // 28 * 28 s
      expect(city, closeTo(392, 1)); // 14 * 28 s
    });

    test('Untergrenze im Stand / sehr langsam', () {
      expect(maneuverPreAnnounceDistanceMeters(0), 250);
      expect(maneuverPreAnnounceDistanceMeters(8), 250); // 8*28=224 < 250
      expect(maneuverPreAnnounceDistanceMeters(-5), 250);
      expect(maneuverPreAnnounceDistanceMeters(double.nan), 250);
    });

    test('Obergrenze bei sehr hohem Tempo', () {
      expect(maneuverPreAnnounceDistanceMeters(60), 1200); // 60*28 > 1200
    });
  });

  group('graphhopperManeuverIsRoundabout (Kreisel-Klassifikation)', () {
    test('sign 6 ist immer Kreisel', () {
      expect(
        graphhopperManeuverIsRoundabout(
          sign: 6,
          hasExitNumber: false,
          textLooksRoundabout: false,
        ),
        isTrue,
      );
    });

    test('exit_number klassifiziert Kreisel auch ohne sign 6', () {
      expect(
        graphhopperManeuverIsRoundabout(
          sign: 0,
          hasExitNumber: true,
          textLooksRoundabout: false,
        ),
        isTrue,
      );
    });

    test('Schlagwort-Text klassifiziert Kreisel', () {
      expect(
        graphhopperManeuverIsRoundabout(
          sign: 2,
          hasExitNumber: false,
          textLooksRoundabout: true,
        ),
        isTrue,
      );
    });

    test('Ankunft (sign 4) nie Kreisel, auch mit exit_number', () {
      expect(
        graphhopperManeuverIsRoundabout(
          sign: 4,
          hasExitNumber: true,
          textLooksRoundabout: true,
        ),
        isFalse,
      );
    });

    test('normale Abbiegung ohne Signale ist kein Kreisel', () {
      expect(
        graphhopperManeuverIsRoundabout(
          sign: 2,
          hasExitNumber: false,
          textLooksRoundabout: false,
        ),
        isFalse,
      );
    });
  });

  group('sliceManeuversForRange (Banner-leer-Pfade)', () {
    test('behält Manöver im Bereich und mappt Indizes 0-basiert', () {
      final source = [_m(0), _m(4), _m(9), _m(14, icon: Icons.flag)];
      final out = sliceManeuversForRange(source, 4, 9);
      // Nur 4 und 9 liegen im Bereich → neue Indizes 0 und 5.
      expect(out.map((m) => m.routeIndex), [0, 5]);
    });

    test('Manöver außerhalb des Bereichs fallen weg', () {
      final source = [_m(0), _m(2), _m(20)];
      final out = sliceManeuversForRange(source, 5, 15);
      expect(out, isEmpty);
    });

    test('leere Quelle / ungültiger Bereich → leer', () {
      expect(sliceManeuversForRange(const [], 0, 5), isEmpty);
      expect(sliceManeuversForRange([_m(3)], 5, 5), isEmpty);
      expect(sliceManeuversForRange([_m(3)], 8, 2), isEmpty);
    });

    test('Bereichsgrenzen sind inklusiv', () {
      final source = [_m(5), _m(10)];
      final out = sliceManeuversForRange(source, 5, 10);
      expect(out.map((m) => m.routeIndex), [0, 5]);
    });
  });

  group('groupFollowerShouldDeferLocalReroute (Follower strandet nicht)', () {
    bool call({
      bool inGroup = true,
      bool hasSharedGroupRoute = true,
      bool hasFreshLeaderPeer = true,
      bool isLeadingGroupRoute = false,
      Duration offRouteFor = Duration.zero,
      double offRouteGapMeters = 0.0,
    }) => groupFollowerShouldDeferLocalReroute(
      inGroup: inGroup,
      hasSharedGroupRoute: hasSharedGroupRoute,
      hasFreshLeaderPeer: hasFreshLeaderPeer,
      isLeadingGroupRoute: isLeadingGroupRoute,
      offRouteFor: offRouteFor,
      offRouteGapMeters: offRouteGapMeters,
    );

    test('transient off-route mit Leader voraus → deferred', () {
      expect(
        call(offRouteFor: const Duration(seconds: 3), offRouteGapMeters: 60),
        isTrue,
      );
    });

    test('anhaltend off-route (>10s) → eigener Reroute', () {
      expect(call(offRouteFor: const Duration(seconds: 12)), isFalse);
    });

    test('weit off-route (>200m) → eigener Reroute', () {
      expect(call(offRouteGapMeters: 240), isFalse);
    });

    test('Basisfälle bleiben: solo / kein Plan / kein Peer / Leader → false', () {
      expect(call(inGroup: false), isFalse);
      expect(call(hasSharedGroupRoute: false), isFalse);
      expect(call(hasFreshLeaderPeer: false), isFalse);
      expect(call(isLeadingGroupRoute: true), isFalse);
    });
  });

  group('buildLocalReanchorRoute (Reroute-Notnagel ohne Netz)', () {
    final planning = [
      [9.0, 47.0],
      [9.1, 47.1],
      [9.2, 47.2],
      [9.3, 47.3],
      [9.4, 47.4],
    ];

    test('schneidet ab Vorwärts-Rejoin, GPS als Start, Manöver remapped', () {
      final m = [_m(0), _m(2), _m(4, icon: Icons.flag)];
      final out = buildLocalReanchorRoute(
        currentPosition: [8.9, 46.9],
        planningCoordinates: planning,
        planningManeuvers: m,
        forwardRejoinIndex: 2,
      );
      // coords = [pos, planning[2], planning[3], planning[4]] = 4 Punkte
      expect(out.coordinates.length, 4);
      expect(out.coordinates.first, [8.9, 46.9]);
      expect(out.coordinates[1], [9.2, 47.2]);
      // Manöver: routeIndex 2→1, 4→3; das bei 0 (vor rejoin) fällt weg.
      expect(out.maneuvers.map((x) => x.routeIndex).toList(), [1, 3]);
    });

    test('rejoin 0 → ganze Planungsroute nach GPS-Start', () {
      final out = buildLocalReanchorRoute(
        currentPosition: [8.9, 46.9],
        planningCoordinates: planning,
        planningManeuvers: const [],
        forwardRejoinIndex: 0,
      );
      expect(out.coordinates.length, planning.length + 1);
    });

    test('Planung < 2 → nur GPS-Punkt, keine Manöver', () {
      final out = buildLocalReanchorRoute(
        currentPosition: [8.9, 46.9],
        planningCoordinates: [
          [9.0, 47.0],
        ],
        planningManeuvers: [_m(0)],
        forwardRejoinIndex: 0,
      );
      expect(out.coordinates.length, 1);
      expect(out.maneuvers, isEmpty);
    });

    test('rejoin am Ende → kurzer gerader Anschluss (nur GPS + letzter Punkt)', () {
      final out = buildLocalReanchorRoute(
        currentPosition: [8.9, 46.9],
        planningCoordinates: planning,
        planningManeuvers: const [],
        forwardRejoinIndex: 4,
      );
      expect(out.coordinates.length, 2);
      expect(out.coordinates.last, [9.4, 47.4]);
    });
  });
}
