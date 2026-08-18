// ignore_for_file: avoid_print
import 'dart:math' as math;

import 'package:cruise_connect/data/services/route_service.dart';
import 'package:cruise_connect/data/services/route_style_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-18 (vucko, Aufgaben 1.3 und 1.4)
///
/// Vucko am 16.08.: „Kleiner Umweg ist noch nicht so gut, mittlerer Umweg
/// zeigt schon viel staerkere Verbesserungen an, und grosser Umweg auch."
///
/// GEMESSENE URSACHEN
/// (a) Die Annahmefenster ueberlappten. Stufe 1 nahm 1,60x bis 2,70x
///     Luftlinie, Stufe 2 nahm 2,35x bis 3,90x. Bei 10 km Luftlinie war jede
///     Route zwischen 23,5 und 30,0 km fuer BEIDE Stufen gueltig - klein und
///     mittel konnten dieselbe Route liefern.
/// (b) Stufe 1 mass gegen die Luftlinie statt gegen die direkte
///     STRASSENSTRECKE. Eine Strassenroute ist typisch das 1,2- bis 1,4-fache
///     der Luftlinie; eine Route an der Untergrenze 1,60x Luftlinie lag damit
///     nur 15 bis 30 Prozent ueber der Direktfahrt und war praktisch kein
///     Umweg. Bei Stufe 2 (2,35x) und 3 (3,10x) war der Abstand gross genug,
///     genau deshalb „zeigen die schon viel staerkere Verbesserungen".
///
/// Diese Datei rechnet die Fenster ueber 5, 10, 20, 40 und 80 km Luftlinie
/// nach und prueft die beiden Loecher aus Aufgabe 1.4 am laufenden Dienst.
const _probeAirlineKm = <double>[5.0, 10.0, 20.0, 40.0, 80.0];

const _dornbirnLat = 47.4125;
const _dornbirnLng = 9.7414;
const _feldkirchLat = 47.2413;
const _feldkirchLng = 9.5986;

geo.Position _dornbirn() => geo.Position(
  latitude: _dornbirnLat,
  longitude: _dornbirnLng,
  timestamp: DateTime.now(),
  accuracy: 5.0,
  altitude: 430.0,
  altitudeAccuracy: 10.0,
  heading: 0.0,
  headingAccuracy: 5.0,
  speed: 0.0,
  speedAccuracy: 1.0,
);

double _airlineDornbirnFeldkirchKm() =>
    geo.Geolocator.distanceBetween(
      _dornbirnLat,
      _dornbirnLng,
      _feldkirchLat,
      _feldkirchLng,
    ) /
    1000.0;

/// Sanfte Bogen-Geometrie von Start zu Ziel. Kein Hin und Zurueck.
List<List<double>> _sauberesKorridorProfil({int punkte = 160}) {
  const dx = _feldkirchLng - _dornbirnLng;
  const dy = _feldkirchLat - _dornbirnLat;
  final laenge = math.sqrt(dx * dx + dy * dy);
  final perpX = -dy / laenge;
  final perpY = dx / laenge;
  return List.generate(punkte, (i) {
    final t = i / (punkte - 1);
    final bogen = math.sin(t * math.pi) * 0.035;
    return [
      _dornbirnLng + dx * t + perpX * bogen,
      _dornbirnLat + dy * t + perpY * bogen,
    ];
  });
}

/// Faehrt ein Stueck, biegt seitlich ab und kommt auf DERSELBEN Linie
/// zurueck, danach weiter ans Ziel. Genau die Hin-und-zurueck-Geometrie,
/// gegen die Stufe 0 bisher gar kein Tor hatte. Bewusst KEIN Ueberfahren des
/// Ziels (das schneidet der Ueberschuss-Schnitt sauber weg) und bewusst ein
/// SCHMALER Stachel: er kostet kaum Kilometer, faehrt aber dieselbe Strasse
/// hin und zurueck.
List<List<double>> _hinUndZurueckProfil() {
  const dx = _feldkirchLng - _dornbirnLng;
  const dy = _feldkirchLat - _dornbirnLat;
  final laenge = math.sqrt(dx * dx + dy * dy);
  final perpX = -dy / laenge;
  final perpY = dx / laenge;
  final coords = <List<double>>[];

  List<double> aufLinie(double t) => [
    _dornbirnLng + dx * t,
    _dornbirnLat + dy * t,
  ];

  const abzweig = 0.35;
  const stachelGrad = 0.012;
  const stachelPunkte = 100;
  for (var i = 0; i < 15; i++) {
    coords.add(aufLinie((i / 14) * abzweig));
  }
  final basis = aufLinie(abzweig);
  for (var i = 1; i <= stachelPunkte; i++) {
    final u = (i / stachelPunkte) * stachelGrad;
    coords.add([basis[0] + perpX * u, basis[1] + perpY * u]);
  }
  for (var i = stachelPunkte - 1; i >= 0; i--) {
    final u = (i / stachelPunkte) * stachelGrad;
    coords.add([basis[0] + perpX * u, basis[1] + perpY * u]);
  }
  for (var i = 1; i <= 25; i++) {
    coords.add(aufLinie(abzweig + (i / 25) * (1 - abzweig)));
  }
  return coords;
}

Map<String, dynamic> _antwort({
  required double distanzKm,
  required List<List<double>> coords,
  Map<String, dynamic> meta = const {},
}) {
  return {
    if (meta.isNotEmpty) 'meta': meta,
    'route': {
      'geometry': {'type': 'LineString', 'coordinates': coords},
      'distance': distanzKm * 1000,
      'duration': distanzKm * 72,
      'legs': [
        {
          'steps': [
            {
              'maneuver': {'type': 'depart', 'location': coords.first},
              'distance': distanzKm * 1000,
              'name': 'Startstrasse',
            },
            {
              'maneuver': {'type': 'arrive', 'location': coords.last},
              'distance': 0.0,
              'name': '',
            },
          ],
        },
      ],
    },
  };
}

class _FesteAntwort implements RouteEdgeInvoker {
  _FesteAntwort(this.antwort, {this.direktAntwort});

  /// Antwort auf jede Umwegs-Anfrage.
  final Map<String, dynamic> antwort;

  /// Antwort auf den Direkt-Rueckfall (`detour_level` 0). Fehlt sie, kommt
  /// ueberall dieselbe Antwort.
  final Map<String, dynamic>? direktAntwort;

  final List<Map<String, dynamic>> anfragen = [];

  @override
  Future<dynamic> invoke(Map<String, dynamic> body) async {
    anfragen.add(Map<String, dynamic>.from(body));
    final stufe = body['detour_level'];
    final istDirektAnfrage = stufe == null || stufe == 0;
    if (istDirektAnfrage && direktAntwort != null) return direktAntwort!;
    return antwort;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Aufgabe 1.3 - Umwegsfenster rechnerisch', () {
    test(
      'Fenster von klein, mittel und gross ueberschneiden sich nicht und '
      'lassen keine Luecke',
      () {
        final config = RouteStyleConfig.forMode('Sport Mode');
        for (final airline in _probeAirlineKm) {
          final min1 = config.minimumPointToPointDistanceKm(
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 1,
          );
          final max1 = config.maximumPointToPointDistanceKm(
            targetKm: airline * 2,
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 1,
          );
          final min2 = config.minimumPointToPointDistanceKm(
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 2,
          );
          final max2 = config.maximumPointToPointDistanceKm(
            targetKm: airline * 3,
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 2,
          );
          final min3 = config.minimumPointToPointDistanceKm(
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 3,
          );
          final max3 = config.maximumPointToPointDistanceKm(
            targetKm: airline * 4,
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 3,
          );

          final grund = 'Luftlinie ${airline.toStringAsFixed(0)} km: '
              'klein ${min1.toStringAsFixed(1)}-${max1.toStringAsFixed(1)}, '
              'mittel ${min2.toStringAsFixed(1)}-${max2.toStringAsFixed(1)}, '
              'gross ${min3.toStringAsFixed(1)}-${max3.toStringAsFixed(1)}';

          // Keine Ueberlappung und keine Luecke: die Obergrenze der einen
          // Stufe IST die Untergrenze der naechsten.
          expect(max1, closeTo(min2, 0.001), reason: grund);
          expect(max2, closeTo(min3, 0.001), reason: grund);
          // Streng steigend, sonst waere ein Fenster leer.
          expect(min1, lessThan(max1), reason: grund);
          expect(min2, lessThan(max2), reason: grund);
          expect(min3, lessThan(max3), reason: grund);
        }
      },
    );

    test('jede gelieferte Laenge gehoert zu genau einer Stufe', () {
      final config = RouteStyleConfig.forMode('Sport Mode');
      for (final airline in _probeAirlineKm) {
        double min(int v) => config.minimumPointToPointDistanceKm(
          directDistanceKm: airline,
          scenic: true,
          detourVariant: v,
        );
        double max(int v) => config.maximumPointToPointDistanceKm(
          targetKm: airline * (v + 1),
          directDistanceKm: airline,
          scenic: true,
          detourVariant: v,
        );
        // Je Stufe die Mitte des Fensters pruefen: sie darf nur von dieser
        // einen Stufe angenommen werden.
        for (final stufe in const [1, 2, 3]) {
          final mitte = (min(stufe) + max(stufe)) / 2;
          for (final andere in const [1, 2, 3]) {
            final passt = mitte >= min(andere) && mitte <= max(andere);
            expect(
              passt,
              andere == stufe,
              reason:
                  'Luftlinie ${airline.toStringAsFixed(0)} km: '
                  '${mitte.toStringAsFixed(1)} km ist Mitte von Stufe $stufe, '
                  'wurde aber von Stufe $andere '
                  '${passt ? 'ebenfalls angenommen' : 'abgelehnt'}',
            );
          }
        }
      }
    });

    test(
      'kleiner Umweg misst gegen die Strassenstrecke, nicht gegen die '
      'Luftlinie',
      () {
        final config = RouteStyleConfig.forMode('Sport Mode');
        for (final airline in _probeAirlineKm) {
          final strasse = RouteStyleConfig.pointToPointRoadReferenceKm(
            directDistanceKm: airline,
          );
          // Die Schaetzung bleibt im gemessenen Band 1,2 bis 1,4.
          expect(strasse / airline, inInclusiveRange(1.20, 1.40));

          final min1 = config.minimumPointToPointDistanceKm(
            directDistanceKm: airline,
            scenic: true,
            detourVariant: 1,
          );
          // Vor der Aenderung lag die Untergrenze bei 1,60x Luftlinie, also
          // bei 10, 20 und 40 km Luftlinie nur rund 1,21x bis 1,28x der
          // Strassenstrecke - „kein Umweg". Jetzt mindestens 1,30x.
          expect(
            min1 / strasse,
            greaterThanOrEqualTo(1.30),
            reason:
                'Luftlinie ${airline.toStringAsFixed(0)} km: Untergrenze '
                '${min1.toStringAsFixed(1)} km gegen Strassenstrecke '
                '${strasse.toStringAsFixed(1)} km',
          );
        }
      },
    );

    test('die Zielgroesse jeder Stufe liegt in ihrem eigenen Fenster', () {
      final config = RouteStyleConfig.forMode('Sport Mode');
      for (final airline in _probeAirlineKm) {
        for (final stufe in const [1, 2, 3]) {
          final ziel = RouteStyleConfig.pointToPointDetourTargetKm(
            directDistanceKm: airline,
            detourVariant: stufe,
          );
          final geklemmt = config.clampPointToPointTargetKm(
            ziel,
            directDistanceKm: airline,
            scenic: true,
            detourVariant: stufe,
          );
          expect(
            geklemmt,
            closeTo(ziel, 0.001),
            reason:
                'Luftlinie ${airline.toStringAsFixed(0)} km, Stufe $stufe: '
                'Ziel ${ziel.toStringAsFixed(1)} km wurde auf '
                '${geklemmt.toStringAsFixed(1)} km geklemmt',
          );
        }
        // Und der kleine Umweg zielt auf rund das Anderthalbfache der
        // direkten Strassenstrecke.
        final strasse = RouteStyleConfig.pointToPointRoadReferenceKm(
          directDistanceKm: airline,
        );
        final zielKlein = RouteStyleConfig.pointToPointDetourTargetKm(
          directDistanceKm: airline,
          detourVariant: 1,
        );
        expect(zielKlein / strasse, greaterThanOrEqualTo(1.50));
      }
    });

    test('eine gemessene Strassenstrecke schlaegt die Schaetzung', () {
      // Arlberg-Fall: die echte Strasse ist doppelt so lang wie die Luftlinie.
      const airline = 100.0;
      final geschaetzt = RouteStyleConfig.pointToPointRoadReferenceKm(
        directDistanceKm: airline,
      );
      final gemessen = RouteStyleConfig.pointToPointRoadReferenceKm(
        directDistanceKm: airline,
        measuredDirectRoadDistanceKm: 200.0,
      );
      expect(geschaetzt, closeTo(120.0, 0.001));
      expect(gemessen, closeTo(200.0, 0.001));
      // Unplausible Messwerte werden verworfen, sonst verschiebt eine kaputte
      // Geometrie alle Fenster.
      expect(
        RouteStyleConfig.pointToPointRoadReferenceKm(
          directDistanceKm: airline,
          measuredDirectRoadDistanceKm: 40.0,
        ),
        closeTo(geschaetzt, 0.001),
      );
      expect(
        RouteStyleConfig.pointToPointRoadReferenceKm(
          directDistanceKm: airline,
          measuredDirectRoadDistanceKm: 900.0,
        ),
        closeTo(geschaetzt, 0.001),
      );
    });
  });

  group('Aufgabe 1.4 - Tore fuer A nach B', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      RouteService.resetForTests();
      RouteService.disableBackgroundPreparation = true;
    });

    test(
      'A nach B ohne Umweg lehnt eine Hin-und-zurueck-Geometrie ab',
      () async {
        final airline = _airlineDornbirnFeldkirchKm();
        final invoker = _FesteAntwort(
          _antwort(
            distanzKm: airline * 1.20,
            coords: _hinUndZurueckProfil(),
            meta: const {'delivered_detour_level': 0},
          ),
        );
        final service = RouteService(invoker: invoker);

        await expectLater(
          service.generatePointToPoint(
            startPosition: _dornbirn(),
            destinationLat: _feldkirchLat,
            destinationLng: _feldkirchLng,
            mode: 'Sport Mode',
            routeVariant: 0,
          ),
          throwsA(isA<RouteServiceException>()),
          reason:
              'Stufe 0 hatte gar kein Ueberlappungstor: es reichten genug '
              'Punkte und ein erreichtes Ziel',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Herabstufung auf direkt springt nicht mehr am Umweg-Tor vorbei',
      () async {
        final airline = _airlineDornbirnFeldkirchKm();
        // Die Umwegs-Anfragen liefern eine Route vom Doppelten der Luftlinie,
        // melden sie aber als „delivered_detour_level 0". Vorher machte genau
        // das isDirectPointToPoint wahr, forceDirectAcceptable griff und alle
        // Tore wurden uebersprungen - der Nutzer bekam sie als „mittleren
        // Umweg" praesentiert. Der Direkt-Rueckfall liefert die ehrliche
        // Direktroute.
        final invoker = _FesteAntwort(
          _antwort(
            distanzKm: airline * 2.0,
            coords: _sauberesKorridorProfil(),
            meta: const {'delivered_detour_level': 0},
          ),
          direktAntwort: _antwort(
            distanzKm: airline * 1.20,
            coords: _sauberesKorridorProfil(),
            meta: const {'delivered_detour_level': 0},
          ),
        );
        final service = RouteService(invoker: invoker);

        final route = await service.generatePointToPoint(
          startPosition: _dornbirn(),
          destinationLat: _feldkirchLat,
          destinationLng: _feldkirchLng,
          mode: 'Sport Mode',
          scenic: true,
          routeVariant: 2,
        );

        final strasse = RouteStyleConfig.pointToPointRoadReferenceKm(
          directDistanceKm: airline,
        );
        final untergrenzeKleinerUmweg =
            RouteStyleConfig.pointToPointDetourBoundaryKm(
              roadReferenceKm: strasse,
              boundaryIndex: 0,
            );
        expect(route.distanceKm, isNotNull);
        expect(
          route.distanceKm!,
          lessThanOrEqualTo(untergrenzeKleinerUmweg),
          reason:
              'die als direkt gemeldete Route mit '
              '${(airline * 2.0).toStringAsFixed(1)} km wurde wieder '
              'durchgewunken, obwohl ein mittlerer Umweg angefordert war',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '„Direkte Route nehmen" liefert eine saubere Direktroute weiterhin',
      () async {
        final airline = _airlineDornbirnFeldkirchKm();
        final invoker = _FesteAntwort(
          _antwort(
            distanzKm: airline * 1.20,
            coords: _sauberesKorridorProfil(),
            meta: const {'delivered_detour_level': 0},
          ),
        );
        final service = RouteService(invoker: invoker);

        final route = await service.generatePointToPoint(
          startPosition: _dornbirn(),
          destinationLat: _feldkirchLat,
          destinationLng: _feldkirchLng,
          mode: 'Standard',
          routeVariant: 0,
          forceAcceptDirect: true,
        );
        expect(route.distanceKm, isNotNull);
        expect(route.distanceKm!, greaterThan(airline));
        // Und die gemessene Strassenstrecke ist jetzt bekannt: kuenftige
        // Umwegsfenster derselben Verbindung rechnen damit statt mit der
        // Schaetzung aus der Luftlinie.
        expect(
          RouteService.measuredDirectRoadDistanceKmForTest(
            startLat: _dornbirnLat,
            startLng: _dornbirnLng,
            destLat: _feldkirchLat,
            destLng: _feldkirchLng,
          ),
          closeTo(route.distanceKm!, 0.01),
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
