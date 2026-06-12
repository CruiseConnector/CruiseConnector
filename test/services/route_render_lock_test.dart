import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_render_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseLat = 47.4125;
  const baseLng = 9.7417;

  List<double> pointAt(double meters, {double lateralMeters = 0.0}) {
    final lngMetersPerDegree = 111320.0 * math.cos(baseLat * math.pi / 180.0);
    return [
      baseLng + meters / lngMetersPerDegree,
      baseLat + lateralMeters / 110540.0,
    ];
  }

  List<List<double>> variableDensityRoute() {
    final coords = <List<double>>[];
    for (var m = 0.0; m <= 360.0; m += 2.0) {
      coords.add(pointAt(m));
    }
    for (final m in [620.0, 900.0, 1180.0, 1500.0]) {
      coords.add(pointAt(m));
    }
    return coords;
  }

  test('projects through dense geometry by meters, not segment count', () {
    final route = variableDensityRoute();
    final lock = RouteRenderLock();

    final start = pointAt(0);
    final first = lock.project(
      coordinates: route,
      latitude: start[1],
      longitude: start[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 25.0,
    );
    expect(first, isNotNull);

    final next = pointAt(260, lateralMeters: 3);
    final projected = lock.project(
      coordinates: route,
      latitude: next[1],
      longitude: next[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 25.0,
    );

    expect(projected, isNotNull);
    expect(projected!.distanceM, closeTo(260, 2.0));
    expect(projected.lateralMeters, lessThan(4.5));
  });

  test('keeps render progress monotonic when GPS jitters backwards', () {
    final route = variableDensityRoute();
    final lock = RouteRenderLock();

    for (final meters in [0.0, 35.0, 70.0, 110.0, 145.0]) {
      final p = pointAt(meters, lateralMeters: 2.0);
      final projected = lock.project(
        coordinates: route,
        latitude: p[1],
        longitude: p[0],
        routeConfirmed: true,
        currentRouteIndex: 0,
        speedMps: 18.0,
      );
      expect(projected, isNotNull);
    }
    final before = lock.distanceM;

    final jitterBack = pointAt(before - 8.0, lateralMeters: -2.5);
    final projected = lock.project(
      coordinates: route,
      latitude: jitterBack[1],
      longitude: jitterBack[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 18.0,
    );

    expect(projected, isNotNull);
    // Monotonie heisst: nie rueckwaerts. Der Glide darf zum (eingefrorenen)
    // Ziel weiterlaufen, deshalb >= statt exakt.
    expect(projected!.distanceM, greaterThanOrEqualTo(before - 0.01));
    expect(lock.distanceM, greaterThanOrEqualTo(before - 0.01));
  });

  test('rejects off-route outliers without moving the lock', () {
    final route = variableDensityRoute();
    final lock = RouteRenderLock();

    final onRoute = pointAt(120, lateralMeters: 1.0);
    final initial = lock.project(
      coordinates: route,
      latitude: onRoute[1],
      longitude: onRoute[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 15.0,
    );
    expect(initial, isNotNull);
    final before = lock.distanceM;

    final outlier = pointAt(150, lateralMeters: 70.0);
    final rejected = lock.project(
      coordinates: route,
      latitude: outlier[1],
      longitude: outlier[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 15.0,
    );

    expect(rejected, isNull);
    expect(lock.distanceM, closeTo(before, 0.01));
  });

  test('keeps a short visual hold for one rejected GPS outlier', () {
    final route = variableDensityRoute();
    final lock = RouteRenderLock();
    final now = DateTime.utc(2026, 6, 11, 12);

    final onRoute = pointAt(120, lateralMeters: 1.0);
    final initial = lock.project(
      coordinates: route,
      latitude: onRoute[1],
      longitude: onRoute[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 15.0,
    );
    expect(initial, isNotNull);
    final before = lock.distanceM;

    final outlier = pointAt(150, lateralMeters: 70.0);
    final rejected = lock.project(
      coordinates: route,
      latitude: outlier[1],
      longitude: outlier[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 15.0,
    );

    expect(rejected, isNull);
    expect(lock.distanceM, closeTo(before, 0.01));
    expect(
      shouldHoldRouteRenderLock(
        now: now.add(const Duration(milliseconds: 900)),
        lastAcceptedAt: now,
        offRouteSince: null,
        routeConfirmed: true,
        overviewActive: false,
        hasLock: lock.distanceM >= 0,
      ),
      isTrue,
    );
    final held = lock.pointAtDistance(lock.distanceM);
    expect(held, isNotNull);
    expect(held![0], closeTo(initial!.point[0], 0.00002));
    expect(held[1], closeTo(initial.point[1], 0.00002));
  });

  test('visual hold expires so real off-route driving is not hidden', () {
    final now = DateTime.utc(2026, 6, 11, 12);

    expect(
      shouldHoldRouteRenderLock(
        now: now.add(const Duration(milliseconds: 1600)),
        lastAcceptedAt: now,
        offRouteSince: null,
        routeConfirmed: true,
        overviewActive: false,
        hasLock: true,
      ),
      isFalse,
    );
    expect(
      shouldHoldRouteRenderLock(
        now: now.add(const Duration(milliseconds: 1600)),
        lastAcceptedAt: now.add(const Duration(milliseconds: 500)),
        offRouteSince: now,
        routeConfirmed: true,
        overviewActive: false,
        hasLock: true,
      ),
      isFalse,
    );
  });

  test('visual hold is gated by active route state', () {
    final now = DateTime.utc(2026, 6, 11, 12);
    final lastAccepted = now.subtract(const Duration(milliseconds: 500));
    final recentOffRoute = now.subtract(const Duration(milliseconds: 400));

    expect(
      shouldHoldRouteRenderLock(
        now: now,
        lastAcceptedAt: lastAccepted,
        offRouteSince: recentOffRoute,
        routeConfirmed: true,
        overviewActive: false,
        hasLock: true,
      ),
      isTrue,
    );
    expect(
      shouldHoldRouteRenderLock(
        now: now,
        lastAcceptedAt: lastAccepted,
        offRouteSince: recentOffRoute,
        routeConfirmed: false,
        overviewActive: false,
        hasLock: true,
      ),
      isFalse,
    );
    expect(
      shouldHoldRouteRenderLock(
        now: now,
        lastAcceptedAt: lastAccepted,
        offRouteSince: recentOffRoute,
        routeConfirmed: true,
        overviewActive: true,
        hasLock: true,
      ),
      isFalse,
    );
    expect(
      shouldHoldRouteRenderLock(
        now: now,
        lastAcceptedAt: lastAccepted,
        offRouteSince: recentOffRoute,
        routeConfirmed: true,
        overviewActive: false,
        hasLock: false,
      ),
      isFalse,
    );
  });

  test('caps implausible visual jumps onto a nearby future hairpin leg', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 100.0; m += 10.0) pointAt(m),
      pointAt(100, lateralMeters: 12.0),
      for (var m = 90.0; m >= 0.0; m -= 10.0) pointAt(m, lateralMeters: 12.0),
    ];
    final lock = RouteRenderLock();
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final firstPoint = pointAt(40);
    final first = lock.project(
      coordinates: route,
      latitude: firstPoint[1],
      longitude: firstPoint[0],
      routeConfirmed: true,
      currentRouteIndex: 4,
      speedMps: 20.0,
      timestamp: startTime,
    );
    expect(first, isNotNull);

    final ambiguousGps = pointAt(45, lateralMeters: 10.0);
    final projected = lock.project(
      coordinates: route,
      latitude: ambiguousGps[1],
      longitude: ambiguousGps[0],
      routeConfirmed: true,
      currentRouteIndex: 4,
      speedMps: 20.0,
      timestamp: startTime.add(const Duration(milliseconds: 16)),
    );

    expect(projected, isNotNull);
    expect(
      projected!.distanceM,
      lessThan(55.0),
      reason: 'nearby return leg must not make the puck teleport forward',
    );
    expect(projected.distanceM, greaterThanOrEqualTo(first!.distanceM));
  });

  test('current route reanchor cannot teleport the render lock forward', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 1200.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final initialPoint = pointAt(100);
    final initial = lock.project(
      coordinates: route,
      latitude: initialPoint[1],
      longitude: initialPoint[0],
      routeConfirmed: true,
      currentRouteIndex: 10,
      speedMps: 20.0,
      timestamp: startTime,
    );
    expect(initial, isNotNull);
    expect(initial!.distanceM, closeTo(100, 1.0));

    final farPoint = pointAt(900);
    final reanchored = lock.project(
      coordinates: route,
      latitude: farPoint[1],
      longitude: farPoint[0],
      routeConfirmed: true,
      currentRouteIndex: 90,
      speedMps: 20.0,
      timestamp: startTime.add(const Duration(milliseconds: 16)),
    );

    expect(reanchored, isNotNull);
    expect(
      reanchored!.distanceM,
      lessThan(110.0),
      reason: 'route-index reanchor may move search window, not the puck',
    );
    expect(reanchored.distanceM, greaterThan(initial.distanceM));
  });

  test('false far reanchor keeps searching near the current render lock', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 1200.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final initial = lock.project(
      coordinates: route,
      latitude: pointAt(100)[1],
      longitude: pointAt(100)[0],
      routeConfirmed: true,
      currentRouteIndex: 10,
      speedMps: 18.0,
      timestamp: startTime,
    );
    expect(initial, isNotNull);

    final stillHere = lock.project(
      coordinates: route,
      latitude: pointAt(112)[1],
      longitude: pointAt(112)[0],
      routeConfirmed: true,
      currentRouteIndex: 90,
      speedMps: 18.0,
      timestamp: startTime.add(const Duration(milliseconds: 500)),
    );

    expect(stillHere, isNotNull);
    expect(
      stillHere!.distanceM,
      closeTo(112, 3.0),
      reason: 'bad route-index reanchors must not make render projection fail',
    );
  });

  test('current route reanchor catches up smoothly over subsequent frames', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 500.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();
    const speedMps = 70 / 3.6;
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final initial = lock.project(
      coordinates: route,
      latitude: pointAt(40)[1],
      longitude: pointAt(40)[0],
      routeConfirmed: true,
      currentRouteIndex: 4,
      speedMps: speedMps,
      timestamp: startTime,
    );
    expect(initial, isNotNull);

    var projection = initial!;
    for (var frame = 1; frame <= 30; frame++) {
      final now = startTime.add(Duration(milliseconds: frame * 16));
      final gpsPoint = pointAt(120);
      projection = lock.project(
        coordinates: route,
        latitude: gpsPoint[1],
        longitude: gpsPoint[0],
        routeConfirmed: true,
        currentRouteIndex: 12,
        speedMps: speedMps,
        timestamp: now,
      )!;
    }

    expect(
      projection.distanceM,
      closeTo(120, 3.0),
      reason: 'valid reanchors should catch up within about half a second',
    );
  });

  test('catches up after a short 70 km/h GPS gap without visible lag', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 500.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();
    const speedMps = 70 / 3.6;
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final first = lock.project(
      coordinates: route,
      latitude: pointAt(0)[1],
      longitude: pointAt(0)[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: speedMps,
      timestamp: startTime,
    );
    expect(first, isNotNull);

    const expectedDistance = speedMps * 3.0;
    final afterGapPoint = pointAt(expectedDistance);
    final afterGap = lock.project(
      coordinates: route,
      latitude: afterGapPoint[1],
      longitude: afterGapPoint[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: speedMps,
      timestamp: startTime.add(const Duration(seconds: 3)),
    );

    expect(afterGap, isNotNull);
    expect(
      afterGap!.distanceM,
      closeTo(expectedDistance, 2.0),
      reason: 'short GPS gaps should not leave the puck visibly behind',
    );
  });

  test('interpolates point at distance on long sparse segments', () {
    final route = variableDensityRoute();
    final lock = RouteRenderLock()..ensureRoute(route);

    final point = lock.pointAtDistance(760);

    expect(point, isNotNull);
    expect(point![0], closeTo(pointAt(760)[0], 0.00002));
    expect(point[1], closeTo(pointAt(760)[1], 0.00002));
  });

  test('same route list instance with new geometry resets the render lock', () {
    final route = <List<double>>[
      for (var m = 0.0; m <= 500.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();

    final before = lock.project(
      coordinates: route,
      latitude: pointAt(250)[1],
      longitude: pointAt(250)[0],
      routeConfirmed: true,
      currentRouteIndex: 25,
      speedMps: 18.0,
    );
    expect(before, isNotNull);
    expect(before!.distanceM, closeTo(250, 1.0));

    route
      ..clear()
      ..addAll([for (var m = 1000.0; m <= 1500.0; m += 10.0) pointAt(m)]);

    final after = lock.project(
      coordinates: route,
      latitude: pointAt(1000)[1],
      longitude: pointAt(1000)[0],
      routeConfirmed: true,
      currentRouteIndex: 0,
      speedMps: 18.0,
    );

    expect(after, isNotNull);
    expect(
      after!.distanceM,
      lessThan(2.0),
      reason: 'in-place reroute/restore must not keep stale render progress',
    );
  });

  test('1 Hz stop-and-go fixes at 50 km/h render as smooth monotonic motion', () {
    // Geraete-Video 2026-06-12: 1Hz-GPS + 60fps-Kamera-Frames. Zwischen den
    // Fixen bewegt sich das Projektions-ZIEL kaum (Predict schreibt den
    // letzten Fix nur leicht fort), beim naechsten Fix springt es ~10m vor —
    // das ist das "rast kurz, steht dann"-Muster vom Geraet. Der Glide muss
    // daraus STRENG monotone, gleichmaessige Bewegung machen: kein Frame
    // rueckwaerts/stehend, und kein Frame-Schritt groesser als das 2,5-fache
    // des Median-Schritts (= kein Rast-und-Steh mehr).
    final route = <List<double>>[
      for (var m = 0.0; m <= 200.0; m += 10.0) pointAt(m),
    ];
    final lock = RouteRenderLock();
    const speedMps = 50 / 3.6;
    final startTime = DateTime.utc(2026, 6, 11, 12);

    final steps = <double>[];
    double? lastRender;
    for (var frame = 0; frame <= 312; frame++) {
      final tMs = frame * 16;
      final tSec = tMs / 1000.0;
      final fixSec = tSec.floorToDouble();
      final fixDist = speedMps * fixSec;
      // Predict-artig leicht fortgeschrieben: gleicher Fix-Punkt + 30% der
      // seither real gefahrenen Strecke (unter-praediziert wie echte
      // Kalman-Prediction ohne frische Messung).
      final inputDist = fixDist + speedMps * (tSec - fixSec) * 0.3;
      final p = pointAt(inputDist);
      final projected = lock.project(
        coordinates: route,
        latitude: p[1],
        longitude: p[0],
        routeConfirmed: true,
        currentRouteIndex: (fixDist / 10.0).floor(),
        speedMps: speedMps,
        timestamp: startTime.add(Duration(milliseconds: tMs)),
      );
      expect(projected, isNotNull);
      final render = projected!.distanceM;
      if (lastRender != null) {
        steps.add(render - lastRender);
      }
      lastRender = render;
    }

    expect(steps.length, 312);
    // Streng monoton: jeder einzelne Frame bewegt den Puck vorwaerts.
    for (final step in steps) {
      expect(step, greaterThan(0.0), reason: 'kein Frame darf stehen bleiben');
    }
    final sorted = [...steps]..sort();
    final median = sorted[sorted.length ~/ 2];
    expect(
      sorted.last,
      lessThanOrEqualTo(median * 2.5),
      reason: 'kein Rast-und-Steh: Schrittweite bleibt gleichmaessig '
          '(max ${sorted.last.toStringAsFixed(3)}m vs '
          'median ${median.toStringAsFixed(3)}m)',
    );
  });

  test(
    'trim cadence keeps route head locked to the puck at 70 km/h and 1 Hz GPS',
    () {
      final route = variableDensityRoute();
      final lock = RouteRenderLock();
      const speedMps = 70 / 3.6;
      const trimPushGateM = 4.0;
      final startTime = DateTime.utc(2026, 6, 11, 12);
      var lastTrimDistM = -1.0;

      for (var frame = 0; frame <= 60; frame++) {
        final elapsed = frame / 60.0;
        final dist = speedMps * elapsed;
        final p = pointAt(dist, lateralMeters: math.sin(frame / 7.0) * 2.0);
        final projected = lock.project(
          coordinates: route,
          latitude: p[1],
          longitude: p[0],
          routeConfirmed: true,
          currentRouteIndex: 0,
          speedMps: speedMps,
          timestamp: startTime.add(
            Duration(milliseconds: (elapsed * 1000).round()),
          ),
        );
        expect(projected, isNotNull);

        final lockDist = projected!.distanceM;
        if (lastTrimDistM < 0 || lockDist - lastTrimDistM > trimPushGateM) {
          lastTrimDistM = lockDist;
        }
        final routeHeadDist = lastTrimDistM;

        expect(
          routeHeadDist,
          lessThanOrEqualTo(lockDist + 1e-6),
          reason: 'red route head must never be ahead of the puck',
        );
        expect(
          lockDist - routeHeadDist,
          lessThanOrEqualTo(trimPushGateM + 1e-6),
          reason: 'route head lag stays within the GeoJSON push cadence',
        );
      }
    },
  );
}
