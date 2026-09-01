// 2026-09-01 (A1): Wie viele Serveraufrufe kostet EIN Tipp?
//
// Die Wartezeit des Nutzers ist im Wesentlichen die Summe der Serveraufrufe,
// weil sie strikt nacheinander laufen — im ganzen Block gibt es kein
// Future.wait und kein unawaited. Diese Zahl ist deshalb das ehrlichste Mass
// fuer "dauert zu lange", und sie laesst sich exakt zaehlen.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;

import 'package:cruise_connect/data/services/route_service.dart';

class _ZaehlenderInvoker implements RouteEdgeInvoker {
  int aufrufe = 0;
  final Map<String, dynamic> antwort;
  _ZaehlenderInvoker(this.antwort);

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    aufrufe++;
    return antwort;
  }
}

geo.Position _start() => geo.Position(
  latitude: 47.2413, longitude: 9.5986, timestamp: DateTime.now(),
  accuracy: 5.0, altitude: 460.0, altitudeAccuracy: 10.0,
  heading: 0.0, headingAccuracy: 5.0, speed: 0.0, speedAccuracy: 1.0,
);

List<List<double>> _mitWende() {
  final p = <List<double>>[];
  for (var i = 0; i <= 140; i++) {
    final t = i / 140;
    p.add([9.5986 + (9.7471 - 9.5986) * t * 0.55,
           47.2413 + (47.5031 - 47.2413) * t * 0.55]);
  }
  final ab = p.last;
  final stich = <List<double>>[];
  for (var i = 1; i <= 40; i++) {
    stich.add([ab[0] + 0.0009 * i, ab[1] + 0.00035 * i]);
  }
  p.addAll(stich);
  p.addAll(stich.reversed.skip(1));
  for (var i = 1; i <= 140; i++) {
    final t = i / 140;
    p.add([ab[0] + (9.7471 - ab[0]) * t, ab[1] + (47.5031 - ab[1]) * t]);
  }
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ein Tipp mit Umweg kostet eine zaehlbare Menge Serveraufrufe', () async {
    final coords = _mitWende();
    final invoker = _ZaehlenderInvoker({
      'meta': {'engine': 'graphhopper-8', 'detour_level': 2},
      'route': {
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'distance': 62000.0,
        'duration': 3720.0,
        'legs': [
          {'steps': [
            {'maneuver': {'type': 'arrive', 'location': coords.last},
             'distance': 0.0, 'name': ''},
          ]},
        ],
      },
    });
    final service = RouteService(invoker: invoker);
    try {
      await service.generatePointToPoint(
        startPosition: _start(), destinationLat: 47.5031, destinationLng: 9.7471,
        mode: 'Kurvenjagd', scenic: true, routeVariant: 2,
      );
    } on RouteServiceException {
      // Zaehlen zaehlt auch im Fehlerfall.
    }
    // ignore: avoid_print
    print('SERVERAUFRUFE JE TIPP: ${invoker.aufrufe}');
    expect(invoker.aufrufe, lessThanOrEqualTo(7),
        reason: 'Mehr als sieben waere ein Rueckschritt.');
  });
}
