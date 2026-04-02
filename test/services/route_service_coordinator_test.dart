import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

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
    expect(invoker.callCount, 1);
  });
}
