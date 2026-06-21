import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';
import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

void main() {
  group('Navigation Guidance Utils', () {
    test('headingDeltaDegrees liefert minimale Winkeldifferenz', () {
      expect(headingDeltaDegrees(10, 350), closeTo(20, 0.001));
      expect(headingDeltaDegrees(45, 225), closeTo(180, 0.001));
    });

    test('isUTurnHeadingChange erkennt starke Gegenrichtung', () {
      expect(isUTurnHeadingChange(5, 185), isTrue);
      expect(isUTurnHeadingChange(15, 95), isFalse);
    });

    test(
      'selectForwardRejoinIndex bevorzugt vorwaerts ausgerichteten Abschnitt',
      () {
        final route = <List<double>>[];

        // Segment A: nach Norden
        for (var i = 0; i <= 120; i++) {
          route.add([13.0, 47.0 + i * 0.0001]);
        }
        // Segment B: nach Sueden (Gegenrichtung)
        for (var i = 1; i <= 100; i++) {
          route.add([13.0, 47.012 - i * 0.0001]);
        }
        // Segment C: wieder nach Norden
        for (var i = 1; i <= 100; i++) {
          route.add([13.0, 47.002 + i * 0.0001]);
        }

        final idx = selectForwardRejoinIndex(
          coordinates: route,
          nearestIndex: 130,
          currentHeadingDegrees: 0, // Norden
          minLookAheadPoints: 20,
          maxLookAheadPoints: 220,
          maxAlignmentDeltaDegrees: 60,
        );

        // Sollte nicht im gegengerichteten Segment B landen.
        expect(idx, greaterThanOrEqualTo(220));
      },
    );

    test('isUTurnJoin erkennt gegensinnigen Join', () {
      final reroute = [
        [13.0000, 47.0000],
        [13.0010, 47.0000], // Osten
      ];
      final originalOpposite = [
        [13.0020, 47.0000],
        [13.0010, 47.0000], // Westen
        [13.0000, 47.0000],
      ];
      final originalAligned = [
        [13.0020, 47.0000],
        [13.0030, 47.0000], // Osten
        [13.0040, 47.0000],
      ];

      expect(
        isUTurnJoin(
          rerouteCoordinates: reroute,
          originalCoordinates: originalOpposite,
          rejoinIndex: 0,
        ),
        isTrue,
      );
      expect(
        isUTurnJoin(
          rerouteCoordinates: reroute,
          originalCoordinates: originalAligned,
          rejoinIndex: 0,
        ),
        isFalse,
      );
    });
  });

  group('groupReroutePublisherIsLeader', () {
    test('alleiniger Fahrer darf Gruppenroute veröffentlichen', () {
      expect(
        groupReroutePublisherIsLeader(
          myProgressMeters: 1200,
          peerProgressMeters: const [],
        ),
        isTrue,
      );
    });

    test('vorderer Fahrer darf veröffentlichen', () {
      expect(
        groupReroutePublisherIsLeader(
          myProgressMeters: 2200,
          peerProgressMeters: const [900, 1800],
        ),
        isTrue,
      );
    });

    test('hinterer Fahrer darf die Gruppenroute nicht überschreiben', () {
      expect(
        groupReroutePublisherIsLeader(
          myProgressMeters: 1400,
          peerProgressMeters: const [1550, 2300],
        ),
        isFalse,
      );
    });

    test('Toleranz verhindert Ping-Pong bei fast gleicher Position', () {
      expect(
        groupReroutePublisherIsLeader(
          myProgressMeters: 1950,
          peerProgressMeters: const [2010],
          leadToleranceMeters: 75,
        ),
        isTrue,
      );
    });
  });

  group('groupFollowerShouldDeferLocalReroute (Feldkirch-Hang-Fix)', () {
    test('Solo-Fahrer reroutet IMMER normal (nie deferren)', () {
      expect(
        groupFollowerShouldDeferLocalReroute(
          inGroup: false,
          hasSharedGroupRoute: false,
          hasFreshLeaderPeer: false,
          isLeadingGroupRoute: true,
        ),
        isFalse,
      );
    });

    test('Gruppen-LEADER reroutet normal (publiziert für die Gruppe)', () {
      expect(
        groupFollowerShouldDeferLocalReroute(
          inGroup: true,
          hasSharedGroupRoute: true,
          hasFreshLeaderPeer: true,
          isLeadingGroupRoute: true,
        ),
        isFalse,
      );
    });

    test('Allein in der Gruppe (kein frischer Peer) → normal rerouten', () {
      expect(
        groupFollowerShouldDeferLocalReroute(
          inGroup: true,
          hasSharedGroupRoute: true,
          hasFreshLeaderPeer: false,
          isLeadingGroupRoute: false,
        ),
        isFalse,
      );
    });

    test('Ohne geteilte Gruppenroute → normal rerouten', () {
      expect(
        groupFollowerShouldDeferLocalReroute(
          inGroup: true,
          hasSharedGroupRoute: false,
          hasFreshLeaderPeer: true,
          isLeadingGroupRoute: false,
        ),
        isFalse,
      );
    });

    test('Nicht-Leader-Follower mit Leader voraus → DEFERREN (kein '
        'Eigen-Reroute, der die Leader-Updates fightet)', () {
      expect(
        groupFollowerShouldDeferLocalReroute(
          inGroup: true,
          hasSharedGroupRoute: true,
          hasFreshLeaderPeer: true,
          isLeadingGroupRoute: false,
        ),
        isTrue,
      );
    });
  });

  group('groupRouteAccessLegAllowed', () {
    test('erlaubt lokale Zubringer nur fuer Rundkurs-Gruppenrouten', () {
      expect(groupRouteAccessLegAllowed(isRoundTrip: true), isTrue);
      expect(groupRouteAccessLegAllowed(isRoundTrip: false), isFalse);
    });
  });

  group('reroutePreservesPlannedRemainingDistance', () {
    test('verhindert massives Kürzen langer Rundkurs-Reststrecken', () {
      expect(
        reroutePreservesPlannedRemainingDistance(
          beforeMeters: 25000,
          afterMeters: 3000,
        ),
        isFalse,
      );
    });

    test('erlaubt moderat kürzere Rejoin-Strecken', () {
      expect(
        reroutePreservesPlannedRemainingDistance(
          beforeMeters: 25000,
          afterMeters: 19000,
        ),
        isTrue,
      );
    });

    test('erlaubt längere Anschlussrouten', () {
      expect(
        reroutePreservesPlannedRemainingDistance(
          beforeMeters: 25000,
          afterMeters: 31000,
        ),
        isTrue,
      );
    });

    test('greift nahe am Ziel nicht hart ein', () {
      expect(
        reroutePreservesPlannedRemainingDistance(
          beforeMeters: 2200,
          afterMeters: 900,
        ),
        isTrue,
      );
    });
  });

  group('findNearestInWindow', () {
    final coords = List.generate(30, (i) => [13.0 + i * 0.0001, 47.0]);

    test('behaelt aktuellen Index wenn Match ausserhalb maxJump liegt', () {
      final match = findNearestInWindow(
        position: _position(latitude: 48.0, longitude: 14.0),
        coordinates: coords,
        currentIndex: 5,
        windowSize: 20,
        maxJumpMeters: 50,
      );

      expect(match.index, equals(5));
      expect(match.distanceMeters, greaterThan(50));
    });

    test('springt vorwaerts wenn Match innerhalb maxJump liegt', () {
      final target = coords[12];
      final match = findNearestInWindow(
        position: _position(latitude: target[1], longitude: target[0]),
        coordinates: coords,
        currentIndex: 5,
        windowSize: 20,
        maxJumpMeters: 50,
      );

      expect(match.index, equals(12));
      expect(match.distanceMeters, lessThan(1));
    });
  });

  group('distanceToCoordinateMeters', () {
    test('liefert fuer identische Koordinaten nahezu 0 Meter', () {
      final position = _position(latitude: 48.137, longitude: 11.575);

      final distance = distanceToCoordinateMeters(
        position: position,
        coordinate: [11.575, 48.137],
      );

      expect(distance, closeTo(0, 0.001));
    });

    test('liefert fuer einen Punkt noerdlich davon etwa 1 km', () {
      final position = _position(latitude: 48.137, longitude: 11.575);

      final distance = distanceToCoordinateMeters(
        position: position,
        coordinate: [11.575, 48.14599],
      );

      expect(distance, closeTo(1000, 30));
    });
  });

  group('route progress anti-teleport helpers', () {
    test(
      'Segment-Match springt diskret erst nahe Segmentende zum nächsten Vertex',
      () {
        const matchHalfway = RouteWindowMatch(
          index: 11,
          distanceMeters: 3,
          segmentIndex: 10,
          segmentFraction: 0.55,
        );
        const matchNearEnd = RouteWindowMatch(
          index: 11,
          distanceMeters: 3,
          segmentIndex: 10,
          segmentFraction: 0.94,
        );

        expect(
          stableRouteIndexForMatch(match: matchHalfway, currentIndex: 9),
          10,
        );
        expect(
          stableRouteIndexForMatch(match: matchNearEnd, currentIndex: 9),
          11,
        );
      },
    );

    test(
      'Routenmeter nutzen Segment-Fraktion statt vorausliegenden Vertex',
      () {
        const match = RouteWindowMatch(
          index: 2,
          distanceMeters: 0,
          segmentIndex: 1,
          segmentFraction: 0.25,
        );

        expect(
          routeDistanceForMatchMeters(
            cumulativeDistances: const [0, 100, 300],
            match: match,
          ),
          150,
        );
      },
    );

    test(
      'unphysischer Zukunfts-Fortschritt wird blockiert, echte Zeit holt auf',
      () {
        expect(
          isPlausibleRouteAdvance(
            advanceMeters: 180,
            elapsedSeconds: 1,
            speedMps: 12,
            accuracyMeters: 8,
          ),
          isFalse,
        );
        expect(
          isPlausibleRouteAdvance(
            advanceMeters: 180,
            elapsedSeconds: 6,
            speedMps: 12,
            accuracyMeters: 8,
          ),
          isTrue,
        );
      },
    );
  });

  group('isApproachingDestination', () {
    test('erkennt eine klare Zielannaeherung', () {
      expect(isApproachingDestination([1200, 1040, 930, 810, 700]), isTrue);
    });

    test(
      'erkennt keine stabile Zielannaeherung ohne genuegende Verbesserung',
      () {
        expect(
          isApproachingDestination([1200, 1198, 1194, 1191, 1189]),
          isFalse,
        );
      },
    );

    test('braucht mindestens drei Samples', () {
      expect(isApproachingDestination([1200, 1100]), isFalse);
    });
  });

  group('buildRerouteTelemetry', () {
    test('liefert saubere Erfolgstelemetrie fuer echten Rejoin', () {
      final meta = buildRerouteTelemetry(
        rerouteReason: 'off_route',
        rerouteMode: 'rejoin',
        remainingDistanceBeforeMeters: 12840,
        remainingDistanceAfterMeters: 10420,
        etaBeforeSeconds: 930,
        etaAfterSeconds: 780,
        rerouteDistanceMeters: 1850,
        rejoinPointDistanceMeters: 620,
      );

      expect(meta['reroute_triggered'], isTrue);
      expect(meta['reroute_failed'], isFalse);
      expect(meta['reroute_reason'], 'off_route');
      expect(meta['reroute_mode'], 'rejoin');
      expect(meta['reroute_distance_km'], 1.85);
      expect(meta['rejoin_point_distance_km'], 0.62);
      expect(meta['remaining_distance_before'], 12.84);
      expect(meta['remaining_distance_after'], 10.42);
      expect(meta['eta_before'], 930.0);
      expect(meta['eta_after'], 780.0);
    });

    test('markiert fehlgeschlagenen Straßen-Reroute explizit', () {
      final meta = buildRerouteTelemetry(
        rerouteReason: 'no_candidate',
        rerouteMode: 'partial_rebuild',
        remainingDistanceBeforeMeters: 8400,
        remainingDistanceAfterMeters: 8400,
        etaBeforeSeconds: 640,
        etaAfterSeconds: 640,
        rerouteFailed: true,
      );

      expect(meta['reroute_triggered'], isTrue);
      expect(meta['reroute_failed'], isTrue);
      expect(meta['reroute_reason'], 'no_candidate');
      expect(meta['reroute_mode'], 'partial_rebuild');
      expect(meta['reroute_distance_km'], isNull);
      expect(meta['rejoin_point_distance_km'], isNull);
    });
  });
}

geo.Position _position({required double latitude, required double longitude}) {
  return geo.Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: DateTime.now(),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
