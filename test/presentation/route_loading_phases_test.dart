import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/pages/cruise/route_loading_phases.dart';

/// Pinnt die behavior-preserving Extraktion aus cruise_mode_page._routeLoadingStatusText:
/// gleiche Prioritätsreihenfolge (Gruppe > bestehende > Wegpunkte > A→B > Rundkurs)
/// und gleiches Clamping wie der ursprüngliche Getter.
void main() {
  group('RouteLoadingPhases.phrasesFor priority order', () {
    test('group wins over everything', () {
      expect(
        RouteLoadingPhases.phrasesFor(
          isGroup: true,
          isPreparingExisting: true,
          isWaypoint: true,
          isRoundTrip: true,
        ),
        same(RouteLoadingPhases.group),
      );
    });

    test('existing route wins when not group', () {
      expect(
        RouteLoadingPhases.phrasesFor(
          isGroup: false,
          isPreparingExisting: true,
          isWaypoint: true,
          isRoundTrip: false,
        ),
        same(RouteLoadingPhases.existingRoute),
      );
    });

    test('waypoint wins when not group/existing', () {
      expect(
        RouteLoadingPhases.phrasesFor(
          isGroup: false,
          isPreparingExisting: false,
          isWaypoint: true,
          isRoundTrip: true,
        ),
        same(RouteLoadingPhases.waypoint),
      );
    });

    test('point-to-point when not round-trip and no higher mode', () {
      expect(
        RouteLoadingPhases.phrasesFor(
          isGroup: false,
          isPreparingExisting: false,
          isWaypoint: false,
          isRoundTrip: false,
        ),
        same(RouteLoadingPhases.pointToPoint),
      );
    });

    test('round-trip is the default', () {
      expect(
        RouteLoadingPhases.phrasesFor(
          isGroup: false,
          isPreparingExisting: false,
          isWaypoint: false,
          isRoundTrip: true,
        ),
        same(RouteLoadingPhases.roundTrip),
      );
    });
  });

  group('RouteLoadingPhases.statusText clamping', () {
    test('negative index clamps to first phrase', () {
      expect(
        RouteLoadingPhases.statusText(
          isGroup: false,
          isPreparingExisting: false,
          isWaypoint: false,
          isRoundTrip: true,
          phaseIndex: -5,
        ),
        RouteLoadingPhases.roundTrip.first,
      );
    });

    test('overflow index clamps to last phrase', () {
      expect(
        RouteLoadingPhases.statusText(
          isGroup: true,
          isPreparingExisting: false,
          isWaypoint: false,
          isRoundTrip: false,
          phaseIndex: 999,
        ),
        RouteLoadingPhases.group.last,
      );
    });

    test('in-range index returns exact phrase', () {
      expect(
        RouteLoadingPhases.statusText(
          isGroup: false,
          isPreparingExisting: false,
          isWaypoint: false,
          isRoundTrip: true,
          phaseIndex: 2,
        ),
        RouteLoadingPhases.roundTrip[2],
      );
    });
  });

  test('phaseCount matches the active list length', () {
    expect(
      RouteLoadingPhases.phaseCount(
        isGroup: true,
        isPreparingExisting: false,
        isWaypoint: false,
        isRoundTrip: false,
      ),
      RouteLoadingPhases.group.length,
    );
    expect(
      RouteLoadingPhases.phaseCount(
        isGroup: false,
        isPreparingExisting: false,
        isWaypoint: false,
        isRoundTrip: true,
      ),
      RouteLoadingPhases.roundTrip.length,
    );
  });
}
