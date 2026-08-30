import 'dart:async';
import 'dart:io';

import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/unterbrochene_fahrt_verbuchung.dart';
import 'package:cruise_connect/presentation/widgets/cruise/drive_control_panel.dart';
import 'package:cruise_connect/presentation/widgets/cruise/pip_baum_umschalter.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgaben 1 + 2):
///  T1 „Wenn man waehrend der Fahrt die App wechselt, muss man beim
///     Zurueckgehen manuell klicken, dass die Route erneut startet."
///  T2 „Nach einem kompletten Shutdown sollen die vorherigen XP und Daten
///     schon eingetragen sein, nur der Rest kommt dazu."
///
/// URSACHEN:
///  * Android-PiP tauschte den ganzen Scaffold aus (AnimatedSwitcher) —
///    die Fahrtsteuerung (lokaler State) stand danach auf „Fahrt starten".
///  * Der Schnappschuss der toten Fahrt wurde nur beim Fortsetzen ausgewertet
///    — wer verwarf, eine neue Fahrt startete oder 48 h wartete, verlor die
///    gefahrenen km/XP; das Fortsetzen endete in der Vorschau.
///  * Home-Karte „4 km Route · 33 km gefahren": distanceKm war nach einem
///    Reroute die Rest-Route.
void main() {
  group('T1: PiP reisst den Baum nicht mehr ab', () {
    testWidgets('Vollansicht bleibt gemountet, State ueberlebt PiP an/aus', (
      tester,
    ) async {
      final status = StreamController<PiPStatus>.broadcast();
      addTearDown(status.close);
      await tester.pumpWidget(
        MaterialApp(
          home: PipBaumUmschalter(
            statusStream: status.stream,
            vollansicht: const _Zaehler(key: ValueKey('voll')),
            pipAnsicht: (_) => const Text('PIP', key: ValueKey('pip')),
          ),
        ),
      );
      // Zaehler hochdrehen = lokaler Widget-State.
      await tester.tap(find.byKey(const ValueKey('voll')));
      await tester.pump();
      expect(find.text('n=1'), findsOneWidget);
      final stateVorher = tester.state<_ZaehlerState>(find.byType(_Zaehler));

      status.add(PiPStatus.enabled);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pip')), findsOneWidget);
      // Vollansicht ist noch im Baum (Offstage), nicht sichtbar.
      expect(find.byType(_Zaehler, skipOffstage: false), findsOneWidget);
      expect(find.text('n=1'), findsNothing);

      status.add(PiPStatus.disabled);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pip')), findsNothing);
      expect(find.text('n=1'), findsOneWidget);
      // DERSELBE State — kein Neuaufbau.
      expect(
        identical(stateVorher, tester.state<_ZaehlerState>(find.byType(_Zaehler))),
        isTrue,
      );
    });

    test('die Seite nutzt den neuen Umschalter, nicht mehr PiPSwitcher', () {
      final cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      expect(cm.contains('PipBaumUmschalter('), isTrue);
      expect(RegExp(r'\bPiPSwitcher\(').hasMatch(cm), isFalse);
    });
  });

  group('T1: Fahrtsteuerung zeigt den Zustand der Fahrt-Session', () {
    testWidgets('driveState von aussen ueberlebt einen Neuaufbau', (tester) async {
      Widget panel(Key key) => MaterialApp(
            home: Scaffold(
              body: DriveControlPanel(key: key, driveState: DriveState.started),
            ),
          );
      await tester.pumpWidget(panel(const ValueKey('a')));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Fahrt starten'), findsNothing);
      // Neuer Key = komplett neues Widget/State (wie nach PiP frueher).
      await tester.pumpWidget(panel(const ValueKey('b')));
      await tester.pumpAndSettle();
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Fahrt starten'), findsNothing);
    });

    testWidgets('ohne driveState wie bisher (eigener Zustand)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DriveControlPanel())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fahrt starten'), findsOneWidget);
    });

    test('Verdrahtung: Zustand kommt aus der Fahrt-Session', () {
      final cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      expect(cm.contains('driveState: _fahrtzustandFuerPanel'), isTrue);
      final g = cm.indexOf('DriveState get _fahrtzustandFuerPanel');
      expect(g, greaterThan(0));
      final rumpf = cm.substring(g, g + 700);
      expect(rumpf.contains('_navigationStartTime != null'), isTrue);
      expect(rumpf.contains('_soloRideStarted || widget.groupId != null'), isTrue);
      expect(rumpf.contains('_pauseStartedAt != null ? DriveState.paused'), isTrue);
      expect(rumpf.contains('_recordingActive'), isTrue);
    });
  });

  group('T2: Schnappschuss v3', () {
    ActiveRideSnapshot beispiel({bool verworfen = false}) => ActiveRideSnapshot(
          savedAt: DateTime(2026, 8, 15, 18, 20),
          startedAt: DateTime(2026, 8, 15, 17, 30),
          style: 'Kurvenjagd',
          distanceKm: 4.0, // Rest-Route (alt) — bewusst irrefuehrend
          geometry: const {
            'type': 'LineString',
            'coordinates': [
              [9.7, 47.4],
              [9.71, 47.41],
            ],
          },
          isRoundTrip: true,
          drivenKm: 33.0,
          elapsedSeconds: 3000,
          pausedSeconds: 600,
          rideId: 'fahrt_1',
          plannedDistanceKm: 37.0,
          remainingKm: 4.0,
          remainingDurationSeconds: 420,
          userId: 'user-a',
          verworfen: verworfen,
        );

    test('Anzeige: geplant 37 km, Rest 4 km — nicht mehr „4 km Route"', () {
      final s = beispiel();
      expect(s.anzeigeGeplantKm, 37.0);
      expect(s.anzeigeRestKm, 4.0);
      expect(s.fahrSekunden, 2400);
      expect(s.fortschritt, closeTo(33 / 37, 1e-9));
    });

    test('JSON-Roundtrip haelt alle v3-Felder', () {
      final s = beispiel(verworfen: true);
      final zurueck = ActiveRideSnapshot.fromJson(s.toJson())!;
      expect(zurueck.rideId, 'fahrt_1');
      expect(zurueck.plannedDistanceKm, 37.0);
      expect(zurueck.remainingKm, 4.0);
      expect(zurueck.remainingDurationSeconds, 420);
      expect(zurueck.userId, 'user-a');
      expect(zurueck.verworfen, isTrue);
    });

    test('v2-JSON (ohne neue Felder) wird tolerant gelesen', () {
      final v2 = {
        'version': 2,
        'saved_at': '2026-08-15T18:20:00.000',
        'started_at': '2026-08-15T17:30:00.000',
        'style': 'Entdecker',
        'distance_km': 4.0,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [9.7, 47.4],
            [9.71, 47.41],
          ],
        },
        'is_round_trip': false,
        'driven_km': 33.0,
        'elapsed_seconds': 3000,
        'paused_seconds': 0,
      };
      final s = ActiveRideSnapshot.fromJson(v2)!;
      expect(s.rideId, isNull);
      expect(s.userId, isNull);
      expect(s.verworfen, isFalse);
      // Rueckfall der Anzeige: alte Rechnung.
      expect(s.anzeigeGeplantKm, 4.0);
      expect(s.anzeigeRestKm, 0.0);
    });

    test('Zukunfts-Version wird verworfen', () {
      final s = beispiel();
      final json = s.toJson()..['version'] = 99;
      expect(ActiveRideSnapshot.fromJson(json), isNull);
    });
  });

  group('T2: Verbuchung einer NICHT fortgesetzten Fahrt', () {
    ActiveRideSnapshot s({
      double driven = 33,
      double planned = 37,
      int elapsed = 3000,
      int paused = 600,
      double? geplantSek = 2700,
    }) =>
        ActiveRideSnapshot(
          savedAt: DateTime(2026, 8, 15, 18, 20),
          startedAt: DateTime(2026, 8, 15, 17, 30),
          style: 'Kurvenjagd',
          distanceKm: planned,
          geometry: const {
            'type': 'LineString',
            'coordinates': [
              [9.7, 47.4],
              [9.71, 47.41],
            ],
          },
          isRoundTrip: true,
          durationSeconds: geplantSek,
          drivenKm: driven,
          elapsedSeconds: elapsed,
          pausedSeconds: paused,
          rideId: 'fahrt_1',
          plannedDistanceKm: planned,
        );

    test('33 von 37 km: km, plausible Fahrzeit und XP wie am Fahrt-Ende', () {
      final p = UnterbrocheneFahrtVerbuchung.posten(s(), streakTage: 1)!;
      expect(p.km, 33.0);
      expect(p.sekunden, 2400); // 33 km in 40 min = 49,5 km/h → plausibel
      expect(
        p.xp,
        GamificationService.calculateRouteXpBreakdown(
          distanceKm: 33.0,
          curves: 0,
          style: 'Kurvenjagd',
          streakDays: 1,
        ).totalXp,
      );
    });

    test('unter 20 % der Strecke: NICHTS buchen (wie vorzeitiges Beenden)', () {
      expect(
        UnterbrocheneFahrtVerbuchung.posten(s(driven: 5, planned: 40), streakTage: 1),
        isNull,
      );
    });

    test('unter 50 m: nichts zu buchen', () {
      expect(UnterbrocheneFahrtVerbuchung.posten(s(driven: 0.03), streakTage: 1), isNull);
    });

    test('unplausible Fahrzeit (Stunde gestanden ohne Pause) → anteilige Plandauer', () {
      // 33 km in 3 h „Fahrzeit" = 11 km/h?? nein: 26 km in 9 h = 2,9 km/h → unplausibel.
      final sek = UnterbrocheneFahrtVerbuchung.plausibleSekunden(
        s(driven: 26, planned: 37, elapsed: 9 * 3600, paused: 0, geplantSek: 2700),
      );
      expect(sek, (2700 * 26 / 37).round());
      // Ohne Plandauer: 50-km/h-Schaetzung.
      expect(
        UnterbrocheneFahrtVerbuchung.plausibleSekunden(
          s(driven: 26, planned: 37, elapsed: 9 * 3600, paused: 0, geplantSek: null),
        ),
        (26 / 50 * 3600).round(),
      );
    });

    test('Streak-Multiplikator wirkt wie beim normalen Abschluss', () {
      final p1 = UnterbrocheneFahrtVerbuchung.posten(s(), streakTage: 1)!;
      final p5 = UnterbrocheneFahrtVerbuchung.posten(s(), streakTage: 5)!;
      expect(p5.xp, greaterThan(p1.xp));
    });

    test('Idempotenz-Fingerprint haengt an der Fahrt-Kennung', () {
      expect(UnterbrocheneFahrtVerbuchung.fingerprint(s()), 'unterbrochen:fahrt_1');
    });
  });

  group('T2: Verdrahtung', () {
    late String cm;
    late String home;
    late String snap;
    setUpAll(() {
      cm = File('lib/presentation/pages/cruise_mode_page.dart').readAsStringSync();
      home = File('lib/presentation/pages/home_content_page.dart').readAsStringSync();
      snap = File('lib/data/services/active_ride_snapshot_service.dart').readAsStringSync();
    });

    test('Schnappschuss sichert die REST-Strecke ab dem aktuellen Punkt + Fahrer', () {
      final i = cm.indexOf('void _persistActiveRideSnapshot(');
      final rumpf = cm.substring(i, i + 4600);
      expect(rumpf.contains('_fullRouteCoordinates.length >= 2'), isTrue);
      expect(rumpf.contains('alle.sublist(ab)'), isTrue);
      expect(rumpf.contains('geometry: restGeometry'), isTrue);
      expect(rumpf.contains('plannedDistanceKm: _geplanteFahrtKm'), isTrue);
      expect(rumpf.contains('remainingDurationSeconds:'), isTrue);
      expect(rumpf.contains('userId: Supabase.instance.client.auth.currentUser?.id'), isTrue);
      expect(rumpf.contains('isRoundTrip: _isRoundTrip || _wiederaufnahmeIstRundkurs'), isTrue);
    });

    test('Wiederaufnahme: vorwaerts anschliessen (Vorschau UND Start), Auto-Weiterfahrt', () {
      expect(cm.contains("nieKuerzen: route.routeSource != 'resume'"), isTrue);
      expect(cm.contains('final geladen = _isExistingRouteSession && !_istWiederaufnahme;'), isTrue);
      // 2026-08-31: Der Ausdruck ist gewachsen — seit heute schliessen
      // AUCH geladene offene Routen vorwaerts an (Vucko: „man nicht extra
      // zu einem Startpunkt fahren muss"). Die Zusicherung fuer die
      // Wiederaufnahme bleibt dieselbe: sie schliesst vorwaerts an.
      expect(
        cm.contains(
          'joinNearestForward: _istWiederaufnahme || (geladen && !geschlossen),',
        ),
        isTrue,
      );
      final i = cm.indexOf('Future<void> _uebernehmeAusstehendeRoute(');
      final rumpf = cm.substring(i, i + 5000);
      expect(rumpf.contains('_istWiederaufnahme = true;'), isTrue);
      expect(rumpf.contains('_wiederaufnahmeIstRundkurs = fortschritt.isRoundTrip;'), isTrue);
      expect(rumpf.contains('_darfAutomatischWeiterfahren(route)'), isTrue);
      expect(rumpf.contains('await _startNavigationFlow();'), isTrue);
      // Toast nur bei echtem Tracking; Fehlschlag gibt das Home-Angebot frei.
      expect(rumpf.contains('_positionSubscription != null'), isTrue);
      expect(rumpf.contains('CruiseModePage.fahrtLaeuftImProzess.value = false;'), isTrue);
      expect(cm.contains('_autoWeiterfahrtMaxAbstandM = 500.0'), isTrue);
    });

    test('Fortschritt einer Wiederaufnahme zaehlt gegen die geplante Laenge', () {
      final i = cm.indexOf('double _calculateCompletionProgressFraction(');
      expect(cm.substring(i, i + 1200).contains('_abschlussGeplanteWiederaufnahmeM ??'), isTrue);
      final j = cm.indexOf('void _onRouteEarlyStopped() {');
      expect(cm.substring(j, j + 800).contains('_abschlussGeplanteWiederaufnahmeM'), isTrue);
      // Eingefroren fuer den Hintergrund-Abschluss.
      expect(cm.contains('geplanteKm: _istWiederaufnahme ? _geplanteFahrtKm : null'), isTrue);
    });

    test('Rundkurs bleibt bei Buchung/Speichern ein Rundkurs', () {
      expect(cm.contains('(_isRoundTrip || _wiederaufnahmeIstRundkurs);'), isTrue);
      expect(cm.contains('istRundkurs: _isRoundTrip || _wiederaufnahmeIstRundkurs,'), isTrue);
    });

    test('Start-Fenster: kein Doppelstart, Aufzeichnung laeuft nach Pause weiter', () {
      expect(cm.contains('if (_fahrtStartLaeuft) return DriveState.started;'), isTrue);
      final i = cm.indexOf('onStart: () async {');
      final rumpf = cm.substring(i, i + 1400);
      expect(rumpf.contains('if (_fahrtStartLaeuft) return;'), isTrue);
      expect(rumpf.contains('_fahrtStartLaeuft = true;'), isTrue);
      expect(rumpf.contains('_recordingActive && _positionSubscription == null'), isTrue);
      expect(rumpf.contains('finally {'), isTrue);
    });

    test('Nichts geht verloren: Verwerfen, Ablauf, fremdes Konto, neue Fahrt', () {
      // Home: verworfene/abgelaufene/fremde Schnappschuesse werden verbucht
      // statt angeboten; „Verwerfen" bucht ebenfalls.
      expect(home.contains('ActiveRideSnapshotService.loadRoh()'), isTrue);
      expect(home.contains('roh.verworfen || fremd || ActiveRideSnapshotService.istAbgelaufen(roh)'), isTrue);
      expect(home.contains('UnterbrocheneFahrtVerbuchung.verbucheUndLoesche('), isTrue);
      final d = home.indexOf('void _dismissInterruptedRide() {');
      expect(home.substring(d, d + 400).contains('_fahrtImHintergrundAbschliessen(ride)'), isTrue);
      // Neue Fahrt: alter Schnappschuss wird VOR dem Ueberschreiben verbucht.
      expect(cm.contains('ActiveRideSnapshotService.vorNeuerFahrtSichern('), isTrue);
      expect(snap.contains('if (_sperre != null) return;'), isTrue);
      expect(snap.contains('if (sperre != null) await sperre;'), isTrue);
      // Session-Datum = Fahrtdatum, Fingerprint idempotent.
      final v = File('lib/data/services/unterbrochene_fahrt_verbuchung.dart').readAsStringSync();
      expect(v.contains('createdAt: s.savedAt'), isTrue);
      expect(v.contains('routeFingerprint: fp'), isTrue);
      expect(v.contains(".eq('route_fingerprint', fp)"), isTrue);
    });

    test('Home: laufende Fahrt im Prozess ist kein Fortsetzen-Angebot; Karte sofort', () {
      expect(home.contains('CruiseModePage.fahrtLaeuftImProzess.value'), isTrue);
      final i = home.indexOf('Future<void> _ladeUnterbrocheneFahrtSofort()');
      // 2026-08-18: Fenster grosszuegiger — die Methode entscheidet seit der
      // Auto-Fortsetzung (Aufgabe 2.2) erst, ob sie die Fahrt selbst startet.
      final rumpf = home.substring(i, i + 1200);
      expect(rumpf.contains('_unterbrocheneFahrtLaden()'), isTrue);
      expect(rumpf.contains('setState(() => _resumableRide = snapshot)'), isTrue);
      expect(home.contains('await ActiveRideSnapshotService.load() ?? ride'), isTrue);
      expect(home.contains('ride.anzeigeGeplantKm'), isTrue);
      expect(home.contains('ride.anzeigeRestKm'), isTrue);
      // Resume-Route: Distanz/Dauer passen zur REST-Geometrie.
      expect(home.contains('distanceKm: restKm > 0 ? restKm : aktuell.anzeigeGeplantKm'), isTrue);
      expect(home.contains('durationSeconds: restSek,'), isTrue);
      expect(cm.contains('CruiseModePage.fahrtLaeuftImProzess.value = true;'), isTrue);
      expect(
        RegExp(r'CruiseModePage\.fahrtLaeuftImProzess\.value = false;')
            .allMatches(cm)
            .length,
        greaterThanOrEqualTo(3),
      );
    });
  });
}

class _Zaehler extends StatefulWidget {
  const _Zaehler({super.key});
  @override
  State<_Zaehler> createState() => _ZaehlerState();
}

class _ZaehlerState extends State<_Zaehler> {
  int n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => setState(() => n++),
        child: Text('n=$n'),
      );
}
