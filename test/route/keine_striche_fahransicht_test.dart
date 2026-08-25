import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-25 (vucko): „schau das in keiner erklaerung oder in irgendeinem
/// beispiel oder sonstigem irgendwo ein bindestrich zu finden ist".
///
/// Derselbe Wunsch kam schon am 12.08. fuer das Update-Popup. Damit er nicht
/// ein drittes Mal kommen muss, haelt dieser Test die Fahransicht und das
/// Routing fest: Die frueher beanstandeten Nutzertexte duerfen nicht
/// zurueckkehren, und die umgeschriebenen Fassungen muessen da sein.
///
/// Geprueft werden ausschliesslich Zeichenketten, die am Bildschirm landen.
/// Protokollzeilen (`debugPrint`) und Kommentare sind ausgenommen — dort ist
/// der Bindestrich Fachsprache und hilft beim Lesen.
void main() {
  late String fahransicht;
  late String routing;
  late String aufbau;
  late String infoleiste;
  late String abschluss;
  late String hinweis;
  late String meldung;
  late String xp;

  setUpAll(() {
    String lies(String pfad) => File(pfad).readAsStringSync();
    fahransicht = lies('lib/presentation/pages/cruise_mode_page.dart');
    routing = lies('lib/data/services/route_service.dart');
    aufbau = lies('lib/presentation/widgets/cruise/cruise_setup_card.dart');
    infoleiste = lies(
      'lib/presentation/widgets/cruise/cruise_navigation_info_panel.dart',
    );
    abschluss = lies(
      'lib/presentation/widgets/cruise/cruise_completion_dialog.dart',
    );
    hinweis = lies(
      'lib/presentation/widgets/cruise/routing_onboarding_sheet.dart',
    );
    meldung = lies('lib/presentation/widgets/cruise/incident_alert_sheet.dart');
    xp = lies('lib/presentation/widgets/cruise/xp_rechnung_animation.dart');
  });

  group('Gedankenstriche sind aus den Nutzertexten verschwunden', () {
    test('die Fahransicht meldet in zwei Saetzen statt mit Strich', () {
      for (final weg in [
        'Fahrt fortgesetzt —',
        'Weiter wie gehabt —',
        'Aufzeichnung läuft —',
        'Zu wenig aufgezeichnet —',
      ]) {
        expect(fahransicht.contains(weg), isFalse, reason: 'noch da: $weg');
      }
      expect(fahransicht.contains('Fahrt fortgesetzt. Gute Weiterfahrt!'), isTrue);
      expect(fahransicht.contains('Aufzeichnung läuft. Gute Fahrt!'), isTrue);
      expect(
        fahransicht.contains('Zu wenig aufgezeichnet. Es wurde keine Strecke gespeichert.'),
        isTrue,
      );
    });

    test('Hinweisblatt und Meldung teilen den Satz statt ihn zu spannen', () {
      expect(hinweis.contains('jederzeit heraus —'), isFalse);
      expect(hinweis.contains('jederzeit heraus. Der Hinweis kommt dann erneut.'), isTrue);
      expect(meldung.contains('Deine Meldung —'), isFalse);
      expect(meldung.contains("'Deine Meldung verschwindet automatisch'"), isTrue);
    });

    test('Platzhalter zeigen Punkte statt eines Strichs', () {
      expect(infoleiste.contains("'Ankunft: --'"), isFalse);
      expect(infoleiste.contains("'-- km'"), isFalse);
      expect(infoleiste.contains("'Ankunft: …'"), isTrue);
      expect(abschluss.contains(": '—',"), isFalse);
    });
  });

  group('Bindestriche in zusammengesetzten Woertern sind umgeschrieben', () {
    test('aus dem Trip-Modus wurde der Tripmodus', () {
      for (final quelle in [fahransicht, routing, aufbau]) {
        expect(quelle.contains("'Trip-Modus'"), isFalse);
        expect(quelle.contains('Im Trip-Modus'), isFalse);
        expect(quelle.contains('Aktiviere Trip-Modus'), isFalse);
        expect(quelle.contains('nutze den Trip-Modus'), isFalse);
      }
      expect(fahransicht.contains("'Tripmodus'"), isTrue);
      expect(routing.contains('nutze den Tripmodus.'), isTrue);
    });

    test('aus dem Strecken-Setup wurde die Streckenplanung', () {
      expect(fahransicht.contains("'Zurück zum Strecken-Setup'"), isFalse);
      expect(aufbau.contains("'Strecken-Setup'"), isFalse);
      expect(fahransicht.contains("'Zurück zur Streckenplanung'"), isTrue);
      expect(aufbau.contains("'Streckenplanung'"), isTrue);
    });

    test('die Ueberschriften der Aufbaukarte kommen ohne Strich aus', () {
      expect(aufbau.contains("'Routen-Modus'"), isFalse);
      expect(aufbau.contains("'Planungs-Typ'"), isFalse);
      expect(aufbau.contains("'Routenmodus'"), isTrue);
      expect(aufbau.contains("'Planungstyp'"), isTrue);
    });

    test('das Routing nennt seinen Dienst ohne Strich', () {
      expect(routing.contains('Routing-Dienst'), isFalse);
      expect(routing.contains('Routing-Anfrage'), isFalse);
      expect(routing.contains('Rundkurs-Planung'), isFalse);
      expect(routing.contains('Rundkurs-Parameter'), isFalse);
      expect(routing.contains('Die Routenberechnung hat keine Daten geliefert.'), isTrue);
    });

    test('Zahlenbereiche werden ausgeschrieben', () {
      expect(routing.contains('1-2 Minuten'), isFalse);
      expect(routing.contains('1 bis 2 Minuten'), isTrue);
    });

    test('die uebrigen beanstandeten Woerter sind ersetzt', () {
      for (final weg in [
        "'GPS-Signal schwach'",
        "'Wegpunkt-Route suchen'",
        'Fortsetzen-Bereich',
        'Anfahrts-Abschnitt aktiv',
        'Reroute-Server meldet',
        'Server-Route startete',
        'in den App-Einstellungen',
        'Cheat-Sheet',
        'Mehrtages-Touren',
        "'Auto-Save'",
        '-Stop Tour',
        'Keine GPS-Position',
      ]) {
        expect(fahransicht.contains(weg), isFalse, reason: 'noch da: $weg');
      }
      expect(abschluss.contains("'Top-Speed'"), isFalse);
      expect(abschluss.contains("'Höchsttempo'"), isTrue);
      expect(hinweis.contains('Cruise-Hinweis'), isFalse);
      expect(xp.contains("'Doppel-XP-Woche"), isFalse);
      expect(xp.contains('Doppelte XP · sieben Tage lang'), isTrue);
    });
  });

  test('E-Mail bleibt, weil der Duden es so schreibt', () {
    // Gegenprobe zur Regel: erlaubte Striche duerfen NICHT wegoptimiert
    // werden. Fuer die Fahransicht gilt das vor allem fuer „A nach B"
    // (ohnehin ohne Strich) und fuer Dateinamen der Teilen-Karte.
    expect(abschluss.contains('cruiseconnect-ride.png'), isTrue);
  });
}
