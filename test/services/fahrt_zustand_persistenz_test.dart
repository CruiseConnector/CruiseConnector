import 'dart:io';

import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/unterbrochene_fahrt_verbuchung.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (vucko, Aufgaben 2.1 bis 2.3 — als EINE Architekturaufgabe):
///
///  2.1 „Fortschritt geht nach App-Neustart oder Pause verloren."
///  2.2 „App-Wechsel waehrend der Fahrt erfordert manuellen Neustart der
///      Route." / „dass man halt noch manuell klicken muss, dass man die Route
///      erneut starten muss."
///  2.3 „Nach komplettem Schliessen und Wiederoeffnen sind die vorher
///      gesammelten XP und Fortschrittsdaten schon eingetragen."
///
/// GEMESSENER AUSGANGSSTAND (Quelltext vom 18.08.2026, vor dieser Aenderung):
///
///  * `_persistActiveRideSnapshot` begann mit
///    `if (widget.groupId != null || _tripModeEnabled) return;` — Gruppenfahrt
///    und Trip-Modus hatten GAR KEINEN Schnappschuss. Der Trip-Resume-Pfad
///    laedt nur die offenen Stopps und generiert die Route NEU; gefahrene
///    Kilometer, Fahrzeit und XP des abgebrochenen Teils holte niemand zurueck.
///  * Die freie Aufzeichnung fiel durch `route == null`, weil
///    `_startRecordingSession` ueber `_resetGeneratedRouteUiState()` sowohl
///    `_lastRouteResult` als auch `_sessionRouteResult` nullt. Eine
///    Aufzeichnung war nach einem Abschuss restlos weg.
///  * `_maxSpeedMps` stand in keinem Feld von `toJson`, geht aber als
///    `topSpeedKmh` in die Fahrt ein — nach dem Fortsetzen zaehlte nur noch
///    das Tempo des zweiten Teils.
///  * Es gab genau EINEN Aufrufer von `_resumeInterruptedRide`: den Knopf.
///    `_darfAutomatischWeiterfahren` lief also erst nach einem Tipp. Genau das
///    war der Rest, den Vucko von Hand machte.
///  * Zwei Kommentare behaupteten, XP und Kilometer des abgebrochenen Teils
///    seien beim Fortsetzen „bereits verbucht" und wuerden in
///    `_bereitsVerbuchteKm` gemerkt. Beides existierte nicht.
///
/// HARTE PROJEKTREGEL (CLAUDE.md): „Eine gefahrene Fahrt = GENAU EINE Zeile"
/// in `user_drive_sessions`. 2.3 wird deshalb ueber den ANGEZEIGTEN
/// Zwischenstand geloest, nicht ueber eine zweite Buchung.
void main() {
  Map<String, dynamic> linie([int punkte = 3]) => {
    'type': 'LineString',
    'coordinates': [
      for (var i = 0; i < punkte; i++) [9.70 + i * 0.01, 47.40 + i * 0.01],
    ],
  };

  ActiveRideSnapshot bau({
    FahrtArt art = FahrtArt.solo,
    String? groupId,
    String? tripId,
    double driven = 20,
    double planned = 40,
    double? remaining = 20,
    int elapsed = 1800,
    int paused = 0,
    bool wasPaused = false,
    double topSpeedKmh = 0,
    bool autobahnGemieden = false,
    Duration alter = const Duration(minutes: 2),
    int punkte = 3,
    bool verworfen = false,
  }) => ActiveRideSnapshot(
    savedAt: DateTime.now().subtract(alter),
    startedAt: DateTime.now().subtract(alter + Duration(seconds: elapsed)),
    style: 'Kurvenjagd',
    distanceKm: planned,
    geometry: linie(punkte),
    isRoundTrip: false,
    durationSeconds: 3600,
    drivenKm: driven,
    elapsedSeconds: elapsed,
    wasPaused: wasPaused,
    pausedSeconds: paused,
    rideId: 'fahrt_1',
    plannedDistanceKm: planned,
    remainingKm: remaining,
    userId: 'user-a',
    verworfen: verworfen,
    fahrtArt: art,
    groupId: groupId,
    tripId: tripId,
    topSpeedKmh: topSpeedKmh,
    autobahnGemieden: autobahnGemieden,
  );

  group('2.1 Der Schnappschuss kennt jede Fahrtart', () {
    test('Gruppenfahrt behaelt ihre Gruppe ueber den Prozesstod hinweg', () {
      final s = bau(art: FahrtArt.gruppe, groupId: 'gruppe-7');
      final zurueck = ActiveRideSnapshot.fromJson(s.toJson())!;
      expect(zurueck.fahrtArt, FahrtArt.gruppe);
      expect(
        zurueck.groupId,
        'gruppe-7',
        reason:
            'ohne die Gruppe waere der Rueckweg die Einzelfahrt — der Fahrer '
            'verloere genau das, weswegen er zurueckkommt',
      );
    });

    test('Trip behaelt seine Trip-Kennung', () {
      final zurueck = ActiveRideSnapshot.fromJson(
        bau(art: FahrtArt.trip, tripId: 'trip-3').toJson(),
      )!;
      expect(zurueck.fahrtArt, FahrtArt.trip);
      expect(zurueck.tripId, 'trip-3');
    });

    test('Aufzeichnung ohne Strecke ist lesbar, Route ohne Strecke nicht', () {
      // Die Aufzeichnung wird schon beim Start gesichert — da ist der Track
      // noch leer. Frueher fiel genau dieser Schnappschuss beim Lesen heraus.
      final frisch = ActiveRideSnapshot.fromJson(
        bau(art: FahrtArt.aufzeichnung, punkte: 0, driven: 0).toJson(),
      );
      expect(frisch, isNotNull);
      expect(frisch!.fahrtArt, FahrtArt.aufzeichnung);

      // Regressionsschutz: Eine geplante Route mit einem einzigen Punkt ist
      // weiterhin unbrauchbar und wird verworfen.
      expect(
        ActiveRideSnapshot.fromJson(bau(punkte: 1).toJson()),
        isNull,
        reason: 'die Toleranz gilt NUR fuer die Aufzeichnung',
      );
    });

    test('Aufzeichnung hat kein Soll, ihr Fortschritt ist immer voll', () {
      final s = bau(art: FahrtArt.aufzeichnung, driven: 8, planned: 8);
      expect(
        s.fortschritt,
        1.0,
        reason:
            'sonst wuerde die 20-%-Regel eine echte Aufzeichnung wegwerfen, '
            'obwohl jeder Kilometer gefahren ist',
      );
      expect(
        UnterbrocheneFahrtVerbuchung.posten(s, streakTage: 0),
        isNotNull,
      );
    });

    test('Hoechstgeschwindigkeit und „Autobahn aus" ueberleben', () {
      final zurueck = ActiveRideSnapshot.fromJson(
        bau(topSpeedKmh: 168.4, autobahnGemieden: true).toJson(),
      )!;
      expect(
        zurueck.topSpeedKmh,
        168.4,
        reason:
            'sie geht als top_speed_kmh in die Fahrt — ohne dieses Feld stand '
            'nach dem Fortsetzen nur noch das Tempo des zweiten Teils drin',
      );
      expect(zurueck.autobahnGemieden, isTrue);
    });

    test('v3-JSON wird tolerant gelesen (App-Update mitten in der Fahrt)', () {
      final v3 = {
        'version': 3,
        'saved_at': DateTime(2026, 8, 18, 10).toIso8601String(),
        'started_at': DateTime(2026, 8, 18, 9).toIso8601String(),
        'style': 'Entdecker',
        'distance_km': 40.0,
        'geometry': linie(),
        'is_round_trip': false,
        'driven_km': 12.0,
        'elapsed_seconds': 1200,
        'paused_seconds': 0,
      };
      final s = ActiveRideSnapshot.fromJson(v3);
      expect(
        s,
        isNotNull,
        reason:
            'ein striktes Verwerfen wuerde beim App-Update genau die Fahrt '
            'wegwerfen, die diese Funktion retten soll',
      );
      expect(s!.fahrtArt, FahrtArt.solo);
      expect(s.topSpeedKmh, 0);
      expect(s.autobahnGemieden, isFalse);
      expect(s.groupId, isNull);
    });

    test('unbekannte Fahrtart faellt auf die Einzelfahrt zurueck', () {
      expect(FahrtArt.vonCode('irgendwas'), FahrtArt.solo);
      expect(FahrtArt.vonCode(null), FahrtArt.solo);
      expect(FahrtArt.vonCode('gruppe'), FahrtArt.gruppe);
    });
  });

  group('2.2 Wann darf die Fahrt OHNE Tipp weiterlaufen', () {
    test('frisch abgerissene Einzelfahrt: ja', () {
      expect(bau().darfOhneTippFortsetzen, isTrue);
    });

    test('pausiert: nein — der Fahrer hat sich dagegen entschieden', () {
      expect(bau(wasPaused: true).darfOhneTippFortsetzen, isFalse);
    });

    test('aelter als die Frist: nein', () {
      expect(
        bau(alter: ActiveRideSnapshot.autoFortsetzenFrist +
                const Duration(minutes: 1))
            .darfOhneTippFortsetzen,
        isFalse,
        reason: 'wer am naechsten Morgen die App oeffnet, will keine Navigation',
      );
    });

    test('Gruppe, Trip und Aufzeichnung: nein, eigener Rueckweg', () {
      for (final art in [FahrtArt.gruppe, FahrtArt.trip, FahrtArt.aufzeichnung]) {
        expect(
          bau(art: art, groupId: 'g', tripId: 't').darfOhneTippFortsetzen,
          isFalse,
          reason: '$art kommt ueber Lobby/Trip-Karte bzw. bewusst zurueck',
        );
      }
    });

    test('nichts gefahren oder nichts mehr offen: nein', () {
      expect(bau(driven: 0.05).darfOhneTippFortsetzen, isFalse);
      expect(bau(remaining: 0.0).darfOhneTippFortsetzen, isFalse);
    });

    test('verworfen: nein', () {
      expect(bau(verworfen: true).darfOhneTippFortsetzen, isFalse);
    });
  });

  group('2.3 Zwischenstand statt zweiter Zeile', () {
    test('unter 20 %: keine Buchung, aber ein sichtbarer Zwischenstand', () {
      final s = bau(driven: 5, planned: 40, remaining: 35);
      expect(
        UnterbrocheneFahrtVerbuchung.posten(s, streakTage: 0),
        isNull,
        reason: 'gebucht wird wie beim vorzeitigen Beenden erst ab 20 %',
      );
      final z = UnterbrocheneFahrtVerbuchung.zwischenstand(s, streakTage: 0);
      expect(
        z.km,
        5.0,
        reason:
            'die 5 km sind echt gefahren — sie duerfen dem Fahrer beim '
            'Fortsetzen nicht als „alles weg" erscheinen',
      );
      expect(z.sekunden, greaterThan(0));
    });

    test('oberhalb der Schwelle rechnen beide gleich', () {
      final s = bau(driven: 20, planned: 40);
      final p = UnterbrocheneFahrtVerbuchung.posten(s, streakTage: 3)!;
      final z = UnterbrocheneFahrtVerbuchung.zwischenstand(s, streakTage: 3);
      expect(z.km, p.km);
      expect(z.sekunden, p.sekunden);
      expect(z.xp, p.xp);
    });

    test('der Zwischenstand rechnet mit derselben XP-Formel wie das Ziel', () {
      final s = bau(driven: 20, planned: 40);
      final z = UnterbrocheneFahrtVerbuchung.zwischenstand(s, streakTage: 2);
      expect(
        z.xp,
        GamificationService.calculateRouteXpBreakdown(
          distanceKm: 20,
          curves: 0,
          style: 'Kurvenjagd',
          streakDays: 2,
        ).totalXp,
      );
    });
  });

  group('Verdrahtung Fahransicht', () {
    late String cm;
    setUpAll(() {
      cm = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('kein Ausstieg mehr bei Gruppe oder Trip', () {
      expect(
        cm.contains('if (widget.groupId != null || _tripModeEnabled) return;'),
        isFalse,
        reason:
            'das war die Zeile, die Gruppenfahrt und Trip-Modus jeden '
            'Schnappschuss gekostet hat',
      );
    });

    test('die Fahrtart wird aus dem echten Zustand bestimmt', () {
      final i = cm.indexOf('FahrtArt get _aktuelleFahrtArt {');
      expect(i, greaterThan(0));
      final rumpf = cm.substring(i, i + 500);
      expect(rumpf.contains('widget.groupId != null'), isTrue);
      expect(rumpf.contains('_recordingActive || _isRecordingMode'), isTrue);
      expect(rumpf.contains('_tripModeEnabled || _activeTripId != null'), isTrue);
    });

    test('Aufzeichnung wird ohne Route gesichert, mit dem Track', () {
      final i = cm.indexOf('void _persistActiveRideSnapshot(');
      final rumpf = cm.substring(i, i + 5200);
      expect(rumpf.contains('final hatRoute ='), isTrue);
      expect(
        rumpf.contains('if (!hatRoute && fahrtArt != FahrtArt.aufzeichnung) return;'),
        isTrue,
      );
      expect(
        rumpf.contains('restCoords = _drivenTrackRecorder.snapshot().coordinates;'),
        isTrue,
        reason: 'ohne Route ist der gefahrene Track die ganze Wahrheit',
      );
    });

    test('Fahrtart, Gruppe, Trip, Top-Speed und Autobahn stehen drin', () {
      final i = cm.indexOf('void _persistActiveRideSnapshot(');
      final rumpf = cm.substring(i, i + 5200);
      expect(rumpf.contains('fahrtArt: fahrtArt,'), isTrue);
      expect(rumpf.contains('groupId: widget.groupId,'), isTrue);
      expect(rumpf.contains('tripId: _activeTripId,'), isTrue);
      expect(rumpf.contains('topSpeedKmh: _maxSpeedMps * 3.6,'), isTrue);
      expect(rumpf.contains('autobahnGemieden:'), isTrue);
    });

    test('beim Fahrtstart faellt EINE Entscheidung ueber den Rest', () {
      final i = cm.indexOf('ActiveRideSnapshotService.vorNeuerFahrtSichern(');
      final vorher = cm.substring(i - 400, i);
      expect(
        vorher.contains('if (widget.groupId == null && !_tripModeEnabled) {'),
        isFalse,
        reason:
            'die Vorab-Verbuchung lief nur fuer Solo-Fahrten — mit '
            'Schnappschuessen fuer alle Arten muss sie fuer alle laufen',
      );
      expect(
        cm.contains('_entscheideUeberLiegengebliebeneFahrt'),
        isTrue,
      );
      final j = cm.indexOf('bool _gehoertZurLaufendenFahrt(');
      final rumpf = cm.substring(j, j + 1200);
      expect(rumpf.contains('case FahrtArt.gruppe:'), isTrue);
      expect(rumpf.contains('alt.groupId == widget.groupId'), isTrue);
      expect(rumpf.contains('alt.tripId == _activeTripId'), isTrue);
      expect(
        rumpf.contains('_erwarteteWiederaufnahmeId'),
        isTrue,
        reason:
            'sonst verbucht der Start einer fortgesetzten Aufzeichnung genau '
            'die Fahrt, die fortgesetzt werden soll',
      );
    });

    test('uebernommen wird durch den Rekorder, mit rueckdatierter Startzeit', () {
      final i = cm.indexOf('void _uebernimmFortschrittAusSchnappschuss(');
      expect(i, greaterThan(0));
      final rumpf = cm.substring(i, i + 1600);
      expect(rumpf.contains('_drivenTrackRecorder.seedDistance('), isTrue);
      expect(
        rumpf.contains('_navigationStartTime = DateTime.now().subtract('),
        isTrue,
        reason: 'die Luecke zwischen Abschuss und Fortsetzen ist keine Fahrzeit',
      );
      expect(rumpf.contains('_aktiveFahrtId = alt.rideId ?? _aktiveFahrtId;'), isTrue);
      expect(rumpf.contains('_maxSpeedMps = math.max('), isTrue);
      expect(rumpf.contains('UnterbrocheneFahrtVerbuchung.zwischenstand('), isTrue);
    });

    test('vor dem Waechter wird aktiv ein Standort geholt', () {
      final i = cm.indexOf('Future<void> _uebernehmeAusstehendeRoute(');
      final rumpf = cm.substring(i, i + 4000);
      final fix = rumpf.indexOf('await _resolveCurrentPositionForNavigationStart();');
      final waechter = rumpf.indexOf('if (_darfAutomatischWeiterfahren(route)) {');
      expect(fix, greaterThan(0),
          reason: '„keine bekannte Position" war eine der zwei Stellen, an '
              'denen die Automatik ausstieg');
      expect(fix, lessThan(waechter));
    });

    test('zwei Abstandsgrenzen: streng ohne Tipp, grosszuegig nach dem Tipp', () {
      expect(cm.contains('_autoWeiterfahrtMaxAbstandM = 500.0'), isTrue);
      expect(cm.contains('_autoWeiterfahrtMaxAbstandNachTippM = 5000.0'), isTrue);
      final i = cm.indexOf('bool _darfAutomatischWeiterfahren(SavedRoute route) {');
      final rumpf = cm.substring(i, i + 1200);
      expect(
        rumpf.contains('_wiederaufnahmeOhneTipp\n        ? _autoWeiterfahrtMaxAbstandM\n        : _autoWeiterfahrtMaxAbstandNachTippM'),
        isTrue,
        reason:
            'ein Tipp auf „Fortsetzen" IST die Absicht weiterzufahren; der '
            'Selbstlauf muss streng bleiben',
      );
    });

    test('bei Fehlschlag bleibt die Vorschau und der Fahrer erfaehrt es', () {
      final i = cm.indexOf('Future<void> _uebernehmeAusstehendeRoute(');
      final rumpf = cm.substring(i, i + 5200);
      expect(
        rumpf.contains('zu weit \n'),
        isFalse,
      );
      expect(rumpf.contains('mit „Fahrt starten" geht es weiter.'), isTrue);
    });

    test('die Aufzeichnung hat einen eigenen Draht zurueck', () {
      expect(
        cm.contains(
          'CruiseModePage.pendingResumeProgress.addListener(_onPendingResumeProgress);',
        ),
        isTrue,
      );
      expect(
        cm.contains('CruiseModePage.pendingResumeProgress.removeListener('),
        isTrue,
        reason: 'ein Listener ohne Gegenstueck ist ein Leck',
      );
      final i = cm.indexOf('Future<void> _consumeAufzeichnungWiederaufnahme()');
      expect(i, greaterThan(0));
      final rumpf = cm.substring(i, i + 1800);
      expect(rumpf.contains('s.fahrtArt != FahrtArt.aufzeichnung'), isTrue);
      expect(rumpf.contains('_erwarteteWiederaufnahmeId = s.rideId;'), isTrue);
      expect(rumpf.contains('await _startRecordingSession();'), isTrue);
      expect(
        rumpf.contains('CruiseModePage.fahrtLaeuftImProzess.value = false;'),
        isTrue,
        reason: 'scheitert der Start, muss das Angebot auf Home zurueckkommen',
      );
    });

    test('die falschen Verbuchungs-Kommentare sind korrigiert', () {
      expect(
        cm.contains('_bereitsVerbuchteKm'),
        isFalse,
        reason: 'ein Feld dieses Namens hat es nie gegeben',
      );
      expect(
        cm.contains('sind zu diesem Zeitpunkt bereits verbucht'),
        isFalse,
        reason:
            'die Verbuchung laeuft ausschliesslich in den NICHT-Fortsetzen-'
            'Zweigen — wer fortsetzt, hat nichts gebucht',
      );
      expect(
        cm.contains('Eine gefahrene Fahrt = GENAU EINE\n  /// Zeile'),
        isTrue,
        reason: 'die Projektregel gehoert an die Stelle, die sie einhaelt',
      );
    });
  });

  group('Verdrahtung Startseite', () {
    late String home;
    setUpAll(() {
      home = File(
        'lib/presentation/pages/home_content_page.dart',
      ).readAsStringSync();
    });

    test('die frische Fahrt laeuft ohne Tipp weiter', () {
      expect(
        home.contains('await _resumeInterruptedRide(snapshot, ohneTipp: true);'),
        isTrue,
        reason:
            'bis heute war der Knopf der einzige Aufrufer — der Tipp war der '
            'Rest, den Vucko von Hand machte',
      );
      expect(
        home.contains('snapshot.darfOhneTippFortsetzen'),
        isTrue,
      );
      expect(
        home.contains('bool _autoFortsetzenVersucht = false;'),
        isTrue,
        reason:
            'ohne Ein-Schuss-Schutz schiebt der naechste Home-Refresh den '
            'Fahrer erneut in die Fahransicht, nachdem er zurueckgegangen ist',
      );
    });

    test('Gruppe und Trip werden NICHT als Einzelfahrt angeboten', () {
      final i = home.indexOf('Future<ActiveRideSnapshot?> _unterbrocheneFahrtLaden()');
      final rumpf = home.substring(i, i + 2200);
      expect(
        rumpf.contains(
          'if (roh.fahrtArt == FahrtArt.gruppe || roh.fahrtArt == FahrtArt.trip) {',
        ),
        isTrue,
        reason:
            'als Einzelfahrt geladen verloere der Fahrer seine Gruppe bzw. '
            'seinen Trip',
      );
    });

    test('beide Ladewege nutzen denselben Filter', () {
      expect(
        home.contains('resumableRide = await _unterbrocheneFahrtLaden();'),
        isTrue,
        reason:
            '_loadStats holte den Schnappschuss frueher direkt — damit waere '
            'eine Gruppenfahrt doch noch als Einzelfahrt durchgerutscht',
      );
    });

    test('die Aufzeichnung bekommt ihren eigenen Zweig', () {
      final i = home.indexOf('Future<void> _resumeInterruptedRide(');
      final rumpf = home.substring(i, i + 3400);
      expect(rumpf.contains('aktuell.fahrtArt == FahrtArt.aufzeichnung'), isTrue);
      expect(
        rumpf.contains('CruiseModePage.pendingResumeOhneTipp = ohneTipp;'),
        isTrue,
      );
    });

    test('die Karte beziffert den Zwischenstand (2.3)', () {
      expect(
        home.contains('UnterbrocheneFahrtVerbuchung.zwischenstand('),
        isTrue,
      );
      expect(home.contains("'Bisher \${zwischen.km.toStringAsFixed(1)} km, "), isTrue);
      expect(
        home.contains('alles zählt am Ende als eine Fahrt.'),
        isTrue,
        reason:
            'CLAUDE.md: eine gefahrene Fahrt = genau eine Zeile — das muss '
            'auch dastehen, sonst wirkt der Zwischenstand wie eine Buchung',
      );
      expect(home.contains("'AUFZEICHNUNG UNTERBROCHEN'"), isTrue);
    });

    test('keine Gedankenstriche in den neuen Nutzertexten', () {
      for (final t in [
        'Bisher \${zwischen.km.toStringAsFixed(1)} km',
        'alles zählt am Ende als eine Fahrt.',
        'Die Aufzeichnung läuft an deiner Position weiter.',
      ]) {
        expect(home.contains(t), isTrue, reason: 'Text fehlt: $t');
        expect(t.contains('—'), isFalse);
      }
    });
  });
}
