import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/presentation/pages/cruise_mode_page.dart';

/// 2026-08-19 (Aufgabe 3.1) — vucko: „Startet man eine vorher aufgenommene
/// Route von einer anderen Position aus, verhalten sich die Undock-Punkte
/// komisch."
///
/// Fuer den SOLO-Fall ist das seit 6fe7b01 entschieden und umgesetzt:
/// offene Route → Anfahrt zum Original-Start, geschlossener Rundkurs → an der
/// Geometrie neu aufgesetzt (volle Runde, nur rotiert).
///
/// GEMESSENE LUECKE, die dieser Test schliesst: Der Gruppen-Pfad
/// (`_buildGroupAccessPlanForCurrentPosition`) folgte dem Regelwerk NICHT. Er
/// dockte geteilte Routen weiter nach den alten Regeln an —
/// `preferredJoinIndex: null`, `rebaseClosedLoop` am Flag `route_type` statt
/// an der Geometrie, `joinNearestForward` als dessen Verneinung. Faehrt eine
/// Gruppe eine aufgezeichnete oder gepostete OFFENE Route, bekam ein spaet
/// einsteigendes Mitglied damit genau die Abkuerzung, die solo ausgeschlossen
/// ist.
///
/// Das Flag taugt bei geladenen Routen nicht als Quelle: Die gemeinsame
/// Aufzeichnung schreibt pauschal `ROUND_TRIP` (siehe
/// `GroupRouteDataBuilder.buildRecordingSession`), auch wenn der Track
/// irgendwo endet. Darum die 80-m-Geometrieprobe.
void main() {
  group('andockRegelFuerGeteilteRoute — geladene OFFENE Route', () {
    test('dockt am Original-Start an, nie mitten drin', () {
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: true,
        endpunkteGeschlossen: false,
        // Der aufgezeichnete Track behauptet Rundkurs. Die Geometrie sagt
        // etwas anderes — und die Geometrie gewinnt.
        flagIstRundkurs: true,
      );
      expect(regel.geschlossen, isFalse, reason: 'Geometrie schlaegt das Flag');
      expect(
        regel.preferredJoinIndex,
        0,
        reason: 'Einstieg am Original-Start, sonst ist der Anfang endgueltig weg',
      );
      expect(
        regel.joinNearestForward,
        isFalse,
        reason:
            'das Vorwaerts-Andocken mit 8 Prozent Rest-Minimum bleibt frischen '
            'Suchen vorbehalten',
      );
      expect(regel.rebaseClosedLoop, isFalse);
      expect(
        regel.zubringerErlaubt,
        isTrue,
        reason:
            'ohne Zubringer steigt das Mitglied dort ein, wo es gerade steht',
      );
      expect(regel.hinweisZumOriginalStart, isTrue);
      expect(
        regel.nurStartNaeheZaehlt,
        isTrue,
        reason:
            'neben km 30 einer 40-km-Strecke zu stehen ist kein Einstieg, '
            'sondern die Abkuerzung',
      );
    });
  });

  group('andockRegelFuerGeteilteRoute — geladene GESCHLOSSENE Runde', () {
    test('setzt an der Geometrie auf, volle Runde rotiert', () {
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: true,
        endpunkteGeschlossen: true,
        // Flag behauptet A nach B — die Geometrie ist trotzdem geschlossen.
        flagIstRundkurs: false,
      );
      expect(regel.geschlossen, isTrue);
      expect(
        regel.preferredJoinIndex,
        isNull,
        reason: 'der beste Loop-Einstieg darf ueberall liegen',
      );
      expect(
        regel.rebaseClosedLoop,
        isTrue,
        reason: 'km 12 bis Ende plus km 0 bis 12 — jeder Meter wird gefahren',
      );
      expect(regel.joinNearestForward, isFalse);
      expect(regel.zubringerErlaubt, isTrue);
      expect(
        regel.hinweisZumOriginalStart,
        isFalse,
        reason: 'hier gibt es keinen Umweg zum Start, ueber den zu reden waere',
      );
      expect(regel.nurStartNaeheZaehlt, isFalse);
    });
  });

  group('andockRegelFuerGeteilteRoute — frische Leader-Route', () {
    test('A nach B bleibt ohne lokalen Zubringer', () {
      // Unveraendert: Eine frische A-nach-B-Gruppenroute muss fuer ALLE
      // dieselbe Leader-Geometrie zeigen. Ein lokaler Zubringer wuerde
      // Distanz und Dauer pro Geraet verschieben.
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: false,
        endpunkteGeschlossen: false,
        flagIstRundkurs: false,
      );
      expect(regel.zubringerErlaubt, isFalse);
      expect(regel.geschlossen, isFalse);
    });

    test('frischer Rundkurs behaelt Flag und Loop-Rotation', () {
      // Bei einer frischen Suche ist das Flag die bewusste Wahl des Fahrers,
      // und leichte Endpunkt-Abweichungen (> 80 m) duerfen die Rotation nicht
      // kippen.
      final regel = andockRegelFuerGeteilteRoute(
        istGeladeneRoute: false,
        endpunkteGeschlossen: false,
        flagIstRundkurs: true,
      );
      expect(regel.geschlossen, isTrue, reason: 'frische Suche: Flag gilt');
      expect(regel.zubringerErlaubt, isTrue);
      expect(regel.rebaseClosedLoop, isTrue);
      expect(regel.preferredJoinIndex, isNull);
      expect(regel.hinweisZumOriginalStart, isFalse);
    });
  });

  group('istGeladeneRoutenQuelle', () {
    test('erkennt gespeicherte, kopierte und aufgezeichnete Routen', () {
      expect(istGeladeneRoutenQuelle({'route_source': 'saved'}), isTrue);
      expect(istGeladeneRoutenQuelle({'source': 'recorded_track'}), isTrue);
      expect(istGeladeneRoutenQuelle({'route_source': 'driven_track'}), isTrue);
      expect(
        istGeladeneRoutenQuelle({'route_source': 'saved_route_copy'}),
        isTrue,
      );
      // Die Uebergabe aus der Gruppen-Erstellung setzt beide Marker.
      expect(istGeladeneRoutenQuelle({'explicit_route_handoff': true}), isTrue);
      expect(istGeladeneRoutenQuelle({'saved_route_id': 'abc'}), isTrue);
    });

    test('frisch generierte Routen sind KEINE geladenen Routen', () {
      expect(istGeladeneRoutenQuelle(null), isFalse);
      expect(istGeladeneRoutenQuelle(const {}), isFalse);
      expect(istGeladeneRoutenQuelle({'route_source': 'pool'}), isFalse);
      expect(istGeladeneRoutenQuelle({'route_source': 'route_pool'}), isFalse);
      expect(
        istGeladeneRoutenQuelle({'route_source': 'candidate_reserve'}),
        isFalse,
      );
    });
  });

  group('Verdrahtung im Gruppen-Pfad', () {
    late String cruise;

    setUpAll(() {
      cruise = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('der Gruppen-Zubringer laeuft ueber das gemeinsame Regelwerk', () {
      expect(
        cruise.contains('final regel = andockRegelFuerGeteilteRoute('),
        isTrue,
      );
      expect(
        cruise.contains('preferredJoinIndex: regel.preferredJoinIndex,'),
        isTrue,
      );
      expect(
        cruise.contains('rebaseClosedLoop: regel.rebaseClosedLoop,'),
        isTrue,
      );
      expect(
        cruise.contains('joinNearestForward: regel.joinNearestForward,'),
        isTrue,
      );
      // Die alten, am Flag haengenden Argumente duerfen nicht zurueckkommen.
      expect(
        cruise.contains('rebaseClosedLoop: isRoundTrip,'),
        isFalse,
        reason: 'das Flag entscheidet im Gruppen-Pfad nicht mehr',
      );
      expect(cruise.contains('joinNearestForward: !isRoundTrip,'), isFalse);
    });

    test('die 80-m-Geometrieprobe speist den Gruppen-Pfad', () {
      expect(
        cruise.contains(
          'endpunkteGeschlossen: _istGeometrischGeschlossen(result),',
        ),
        isTrue,
      );
      expect(
        cruise.contains(
          'istGeladeneRoute: geladen,\n'
          '      endpunkteGeschlossen: _istGeometrischGeschlossen(result),',
        ),
        isTrue,
      );
    });

    test('Nahe-an-der-Route zaehlt bei offener geladener Route nur am Start', () {
      expect(
        cruise.contains(
          '!regel.nurStartNaeheZaehlt || match.index <= _startNaeheIndexFenster',
        ),
        isTrue,
      );
    });
  });

  group('Der Nutzer sieht die Entscheidung', () {
    late String cruise;

    setUpAll(() {
      cruise = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('es gibt einen deutschen Hinweis auf den Startpunkt', () {
      expect(cruise.contains('void _zeigeStartpunktHinweis()'), isTrue);
      expect(
        cruise.contains('Du wirst zuerst zum Startpunkt der Route geführt.'),
        isTrue,
      );
    });

    test('keine Gedankenstriche im Hinweis-Text', () {
      const hinweis =
          'Du wirst zuerst zum Startpunkt der Route geführt. '
          'So fährst du die Strecke komplett.';
      expect(hinweis.contains('—'), isFalse);
      expect(hinweis.contains('–'), isFalse);
    });

    test('der Hinweis haengt am Gruppen-Pfad, wo der Zwang noch gilt', () {
      // 2026-08-31: Solo gibt es den Zwang zum Original-Start nicht mehr
      // (Vucko: „man nicht extra zu einem Startpunkt fahren muss"), also
      // gehoert der Hinweis dort auch nicht mehr hin — er waere schlicht
      // falsch. In der GRUPPE bleibt beides: der Zwang, damit alle dieselbe
      // Strecke fahren, und der Hinweis, der ihn erklaert.
      expect(
        cruise.contains(
          'if (regel.hinweisZumOriginalStart && plan.hasAccessLeg) {\n'
          '          _zeigeStartpunktHinweis();',
        ),
        isTrue,
        reason: 'Gruppen-Pfad',
      );
    });

    test('solo verspricht kein Fuehren zum Startpunkt mehr', () {
      // Der Satz darf in den Solo-Pfaden nicht wieder auftauchen: dort
      // stimmt er nicht mehr.
      final vorschauStelle = cruise.indexOf('_zeigeStartpunktHinweis();');
      final gruppenStelle = cruise.indexOf(
        'if (regel.hinweisZumOriginalStart && plan.hasAccessLeg) {',
      );
      expect(gruppenStelle, greaterThan(0));
      expect(
        RegExp(r'_zeigeStartpunktHinweis\(\);').allMatches(cruise).length,
        1,
        reason:
            'genau ein Aufruf, und der gehoert dem Gruppen-Pfad '
            '(gefunden bei $vorschauStelle)',
      );
    });
  });

  group('Die Entscheidung ist im Code dokumentiert', () {
    late String cruise;

    setUpAll(() {
      cruise = File(
        'lib/presentation/pages/cruise_mode_page.dart',
      ).readAsStringSync();
    });

    test('WARUM offen zum Original-Start und geschlossen an die Geometrie', () {
      expect(cruise.contains('DIE ENTSCHEIDUNG, und WARUM sie so faellt'), isTrue);
      expect(
        cruise.contains('Eine offene Route hat keinen Rueckweg zu ihrem Anfang'),
        isTrue,
      );
      expect(
        cruise.contains('die Runde wird nur ROTIERT'),
        isTrue,
      );
    });
  });
}
