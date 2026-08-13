import 'dart:io';

import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/driven_track_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-14 (vucko, P2): „Route wird verloren, wenn man die App verlaesst
/// oder die Route pausiert. Beim spaeteren Fortsetzen wird der bisherige
/// Fortschritt gar nicht ausgewertet. Unbedingt loesen."
///
/// Drei Bausteine, drei Testgruppen:
///  1. Der Rekorder traegt eine Vorleistung (Seed) — noetig, weil jedes
///     GPS-Sample einen blossen Zaehlerwert sofort ueberschreiben wuerde.
///  2. Der Schnappschuss kennt Pausenzeit (v2) und liest v1 tolerant.
///  3. Die Fahransicht spielt den Fortschritt in der richtigen Reihenfolge
///     ein und verliert ihn nicht durch die Anfahrts-Etappe.
void main() {
  group('1. Rekorder-Vorleistung', () {
    test('der Seed fliesst in die Distanz ein', () {
      final r = DrivenTrackRecorder();
      r.seedDistance(12500);
      expect(r.distanceMeters, 12500);

      // Neue Samples addieren sich OBENDRAUF.
      r.addSample(
        latitude: 47.0,
        longitude: 9.0,
        timestamp: DateTime(2026, 8, 14, 10, 0, 0),
      );
      r.addSample(
        latitude: 47.001, // ~111 m nach Norden
        longitude: 9.0,
        timestamp: DateTime(2026, 8, 14, 10, 0, 10),
      );
      expect(r.distanceMeters, greaterThan(12500));
      expect(r.distanceMeters, lessThan(12700));
    });

    test('resetTrackKeepingSeed behaelt die Vorleistung', () {
      final r = DrivenTrackRecorder();
      r.seedDistance(8000);
      r.addSample(
        latitude: 47.0,
        longitude: 9.0,
        timestamp: DateTime(2026, 8, 14, 10, 0, 0),
      );
      r.resetTrackKeepingSeed();
      expect(
        r.distanceMeters,
        8000,
        reason:
            'die Anfahrts-Etappe setzt den Track zurueck — ohne diese '
            'Variante wuerde sie die geretteten Kilometer gleich wieder '
            'loeschen',
      );
    });

    test('reset() loescht auch den Seed', () {
      final r = DrivenTrackRecorder();
      r.seedDistance(8000);
      r.reset();
      expect(r.distanceMeters, 0, reason: 'neue Fahrt beginnt wirklich bei 0');
    });

    test('der Schnappschuss enthaelt die Vorleistung', () {
      final r = DrivenTrackRecorder();
      r.seedDistance(5000);
      expect(
        r.snapshot().distanceMeters,
        5000,
        reason:
            'der Schnappschuss ist die Quelle fuer Persistenz und '
            'Abschlussrechnung — dort zaehlt die Gesamtstrecke',
      );
    });

    test('Unsinnswerte werden nicht zum Seed', () {
      final r = DrivenTrackRecorder();
      r.seedDistance(double.nan);
      expect(r.distanceMeters, 0);
      r.seedDistance(-500);
      expect(r.distanceMeters, 0);
    });
  });

  group('2. Schnappschuss-Schema v2', () {
    Map<String, dynamic> beispielV1() => {
      'version': 1,
      'saved_at': '2026-08-14T10:00:00.000',
      'started_at': '2026-08-14T09:00:00.000',
      'style': 'Kurvenjagd',
      'distance_km': 42.0,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [9.0, 47.0],
          [9.1, 47.1],
        ],
      },
      'is_round_trip': true,
      'driven_km': 17.3,
      'elapsed_seconds': 1800,
    };

    test('v1 wird TOLERANT gelesen, Pausenzeit faellt auf 0', () {
      final s = ActiveRideSnapshot.fromJson(beispielV1());
      expect(
        s,
        isNotNull,
        reason:
            'ein striktes Verwerfen wuerde beim App-Update genau die Fahrt '
            'wegwerfen, die diese Funktion retten soll',
      );
      expect(s!.pausedSeconds, 0);
      expect(s.drivenKm, 17.3);
    });

    test('v2 rundet die Pausenzeit durch den Roundtrip', () {
      final v2 = ActiveRideSnapshot(
        savedAt: DateTime(2026, 8, 14, 10),
        startedAt: DateTime(2026, 8, 14, 9),
        style: 'Sport Mode',
        distanceKm: 30,
        geometry: {
          'type': 'LineString',
          'coordinates': [
            [9.0, 47.0],
            [9.1, 47.1],
          ],
        },
        isRoundTrip: false,
        drivenKm: 12.5,
        elapsedSeconds: 2400,
        pausedSeconds: 300,
      );
      final wieder = ActiveRideSnapshot.fromJson(v2.toJson());
      expect(wieder!.pausedSeconds, 300);
      expect(wieder.elapsedSeconds, 2400);
    });

    test('zukuenftige Schemata werden verworfen', () {
      final json = beispielV1()..['version'] = 99;
      expect(ActiveRideSnapshot.fromJson(json), isNull);
    });
  });

  group('3. Verdrahtung in der Fahransicht', () {
    late String cruise;
    late String home;

    setUpAll(() {
      cruise = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
      home = File(
        'lib/presentation/pages/home_content_page.dart',
      ).readAsStringSync();
    });

    test('der Fortschritt wird VOR der Route uebergeben', () {
      final start = home.indexOf('void _resumeInterruptedRide(');
      final rumpf = home.substring(start, start + 900);
      final progress = rumpf.indexOf('pendingResumeProgress.value = ride');
      final route = rumpf.indexOf('pendingRoute.value = route');
      expect(progress, greaterThan(0));
      expect(
        progress,
        lessThan(route),
        reason: 'der Route-Listener feuert sofort — andersherum kaeme der '
            'Fortschritt zu spaet',
      );
    });

    test('eingespielt wird NACH dem Laden und VOR dem Bestaetigen', () {
      final start = cruise.indexOf(
        'Future<void> _uebernehmeAusstehendeRoute(',
      );
      final rumpf = cruise.substring(start, start + 3000);
      final laden = rumpf.indexOf('_loadSavedRoute(route)');
      final seed = rumpf.indexOf('seedDistance(');
      final rueckdatiert = rumpf.indexOf('_navigationStartTime = DateTime.now().subtract(');
      final bestaetigen = rumpf.indexOf('_confirmRoute(preserveCurrentProgress: true)');
      expect(laden, greaterThan(0));
      expect(seed, greaterThan(laden),
          reason: 'das Laden nullt alle Zaehler — der Seed muss danach kommen');
      expect(rueckdatiert, greaterThan(laden));
      expect(bestaetigen, greaterThan(seed));
    });

    test('die Startzeit wird RUECKDATIERT, nicht uebernommen', () {
      // Damit zaehlt die Luecke zwischen Abschuss und Fortsetzen von selbst
      // nicht als Fahrzeit.
      expect(
        cruise.contains(
          '_navigationStartTime = DateTime.now().subtract(\n'
          '        Duration(seconds: fortschritt.elapsedSeconds),\n'
          '      );',
        ),
        isTrue,
      );
    });

    test('die Anfahrts-Etappe loescht den Seed nicht', () {
      expect(
        cruise.contains('_drivenTrackRecorder.resetTrackKeepingSeed()'),
        isTrue,
        reason:
            'die groesste Stolperfalle des Plans: ein harter reset() beim '
            'ersten „Fahrt starten" wuerde die geretteten Kilometer loeschen',
      );
    });

    test('Weiter nach Pause startet das Tracking neu', () {
      // Der Wiedereintritts-Schutz vom 12.08. kehrte hier immer um — nach
      // Pause → Weiter startete das GPS nie wieder. Jetzt wird bei totem
      // Strom nur das Tracking samt Kamera nachgeholt.
      final start = cruise.indexOf('final fahrtLaeuftBereits =');
      final rumpf = cruise.substring(start, start + 1600);
      expect(rumpf.contains('_positionSubscription == null'), isTrue);
      expect(rumpf.contains('_startNavigationTracking();'), isTrue);
      // Auf den AUFRUF pruefen, nicht auf das Wort — der Kommentar im
      // Schutz erklaert ja gerade, was er verhindert.
      expect(
        rumpf.contains('await _prepareAccessLegForOffRouteStart()'),
        isFalse,
        reason: 'der Zweck des Schutzes bleibt: kein Routen-Neuaufbau',
      );
    });

    test('die Pausenzeit wird mitgesichert', () {
      expect(cruise.contains('pausedSeconds:'), isTrue);
      expect(
        cruise.contains('_totalPausedSeconds.round()'),
        isTrue,
        reason: 'sonst zaehlen Vor-Kill-Pausen beim Fortsetzen als Fahrzeit',
      );
    });
  });
}
