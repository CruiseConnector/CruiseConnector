import 'dart:math' as math;
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/route_quality_validator.dart';
import 'package:cruise_connect/data/services/route_service.dart';

geo.Position _start() => geo.Position(
  latitude: 47.5162,
  longitude: 9.7471,
  timestamp: DateTime.now(),
  accuracy: 5,
  altitude: 410,
  altitudeAccuracy: 8,
  heading: 0,
  headingAccuracy: 5,
  speed: 0,
  speedAccuracy: 1,
);

Map<String, dynamic> _closedLoopResponse() {
  final coords = List.generate(120, (i) {
    final t = (2 * math.pi * i) / 119;
    final radius =
        0.009 +
        math.sin(t * 3) * 0.0016 +
        math.cos(t * 4) * (0.0016 * 0.18) +
        math.sin(t * 3) * (0.0016 * 0.12);
    return [
      9.7471 + math.cos(t) * radius,
      47.5162 + math.sin(t) * radius * 0.55,
    ];
  });
  coords[0] = [9.7471, 47.5162];
  coords[coords.length - 1] = [...coords.first];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': 52000.0,
      'duration': 4300.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[8],
              },
              'distance': 800.0,
              'name': 'Teststraße',
            },
          ],
        },
      ],
    },
  };
}

class _CountingInvoker implements RouteEdgeInvoker {
  _CountingInvoker(this.response);

  final Map<String, dynamic> response;
  int callCount = 0;

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return response;
  }
}

class _VaryingCountingInvoker implements RouteEdgeInvoker {
  int callCount = 0;

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final shift = callCount * 0.0032;
    return _closedLoopResponseShifted(shift);
  }
}

class _FlakyCountingInvoker implements RouteEdgeInvoker {
  _FlakyCountingInvoker(this.response, {this.failuresBeforeSuccess = 4});

  final Map<String, dynamic> response;
  final int failuresBeforeSuccess;
  int callCount = 0;

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    callCount += 1;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (callCount <= failuresBeforeSuccess) {
      throw TimeoutException('simulated timeout');
    }
    return response;
  }
}

Map<String, dynamic> _closedLoopResponseShifted(double lngShift) {
  final coords = List.generate(120, (i) {
    final t = (2 * math.pi * i) / 119;
    final radius =
        0.009 +
        math.sin(t * 3) * 0.0016 +
        math.cos(t * 4) * (0.0016 * 0.18) +
        math.sin(t * 3) * (0.0016 * 0.12);
    return [
      9.7471 + lngShift + math.cos(t) * radius,
      47.5162 + math.sin(t) * radius * 0.55,
    ];
  });
  coords[0] = [9.7471 + lngShift, 47.5162];
  coords[coords.length - 1] = [...coords.first];

  return {
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': 52000.0,
      'duration': 4300.0,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {
                'type': 'turn',
                'modifier': 'left',
                'location': coords[8],
              },
              'distance': 800.0,
              'name': 'Teststraße',
            },
          ],
        },
      ],
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingInvoker invoker;
  late RouteService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RouteService.resetForTests();
    invoker = _CountingInvoker(_closedLoopResponse());
    service = RouteService(invoker: invoker);
  });

  test('single-flight nutzt pro Szenario nur einen aktiven Request', () async {
    final futures = await Future.wait([
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      ),
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
      ),
    ]);

    expect(futures, hasLength(2));
    expect(futures.first.distanceKm, closeTo(futures.last.distanceKm!, 0.01));
    // Single-flight dedupliziert die zwei concurrent calls zu einem
    // generateRoundTrip-Lauf. Dieser Lauf macht intern bis zu 2 Edge-Calls
    // (maxAttempts=2 in route_service.dart), wenn der erste Kandidat nicht
    // ideal ist. Ohne Single-Flight wären es 4 Edge-Calls (2 × 2).
    expect(invoker.callCount, lessThanOrEqualTo(2));
  });

  test(
    'explizites Neu-Suchen startet frisch und löst keine Hintergrundroute aus',
    () async {
      final varyingInvoker = _VaryingCountingInvoker();
      service = RouteService(invoker: varyingInvoker);

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      );

      expect(first.coordinates, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      expect(varyingInvoker.callCount, 1);

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      );

      expect(second.coordinates, isNotEmpty);
      expect(varyingInvoker.callCount, 2);
    },
  );

  test(
    'sichtbar andere Route darf nach Seen-Historie erneut geliefert werden',
    () async {
      final varyingInvoker = _VaryingCountingInvoker();
      service = RouteService(invoker: varyingInvoker);

      final first = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      );

      final second = await service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      );

      expect(first.coordinates, isNotEmpty);
      expect(second.coordinates, isNotEmpty);
      expect(second.distanceKm, closeTo(first.distanceKm!, 0.5));
      expect(varyingInvoker.callCount, greaterThanOrEqualTo(2));
      expect(
        RouteQualityValidator.buildRouteFingerprint(
          first.coordinates,
          distanceKm: first.distanceKm,
        ),
        isNot(
          equals(
            RouteQualityValidator.buildRouteFingerprint(
              second.coordinates,
              distanceKm: second.distanceKm,
            ),
          ),
        ),
      );
    },
  );

  test('nach einem Fehler kann direkt erneut frisch gesucht werden', () async {
    final flakyInvoker = _FlakyCountingInvoker(
      _closedLoopResponse(),
      failuresBeforeSuccess: 3,
    );
    service = RouteService(invoker: flakyInvoker);

    await expectLater(
      service.generateRoundTrip(
        startPosition: _start(),
        targetDistanceKm: 50,
        mode: 'Sport Mode',
        planningType: 'Zufall',
        forceFreshVariant: true,
      ),
      throwsA(isA<RouteServiceException>()),
    );

    final recovered = await service.generateRoundTrip(
      startPosition: _start(),
      targetDistanceKm: 50,
      mode: 'Sport Mode',
      planningType: 'Zufall',
      forceFreshVariant: true,
    );

    expect(recovered.coordinates, isNotEmpty);
    expect(flakyInvoker.callCount, greaterThanOrEqualTo(4));
  });
}
