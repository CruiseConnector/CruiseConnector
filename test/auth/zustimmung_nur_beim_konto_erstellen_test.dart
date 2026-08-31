import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-31 — Vucko: „ich moechte nicht, dass jemand die
/// Datenschutzerklaerung ankreuzen muss … Ich moechte das nur wenn ich das
/// Konto erstelle, dass das gemacht wird und die die das bis jetzt noch nicht
/// gemacht haben sollen dann wirklich das ganze nachholen … und wenn man sich
/// einloggt sollte man das nicht noch mal bestaetigen muessen nur beim
/// Erstellen des Kontos."
///
/// WIE ES WAR. Beim Weg ueber E-Mail und Passwort wurde nie gefragt: die
/// [LegalGatePage] hinter der Anmeldung schaut in `legal_acceptances` nach und
/// laesst durch, wenn dort etwas steht. Nur der Weg ueber Google und Apple
/// stellte VOR der Anmeldung noch einmal die Frage — jedes Mal, auch bei
/// jemandem, dessen Zustimmung seit Monaten in der Tabelle steht. Genau das
/// hat Vucko gesehen.
///
/// WIE ES JETZT IST. Zustaendig ist nur noch das Tor hinter der Anmeldung.
/// Fuer ein frisch erstelltes Konto ist das der erste Moment danach (also
/// „beim Erstellen"), fuer ein Altkonto ohne Zeile das einmalige Nachholen,
/// fuer alle anderen passiert nichts.
///
/// Der Test prueft den Quelltext, weil sich die beiden Anmeldeseiten ohne
/// Supabase nicht aufbauen lassen. Er faellt genau dann, wenn jemand die
/// Vorab-Abfrage zurueckbaut.
void main() {
  const anmeldeseiten = <String>[
    'lib/presentation/pages/login_page.dart',
    'lib/presentation/pages/welcome_page.dart',
  ];

  for (final pfad in anmeldeseiten) {
    group(pfad, () {
      late final String quelle;

      setUpAll(() {
        final datei = File(pfad);
        expect(
          datei.existsSync(),
          isTrue,
          reason: 'Der Test muss aus dem Projektwurzelverzeichnis laufen.',
        );
        quelle = datei.readAsStringSync();
      });

      test('fragt die Rechtstexte nicht vor der Anmeldung ab', () {
        expect(
          quelle.contains('requestPreAuth'),
          isFalse,
          reason:
              'Die Vorab-Abfrage fragt JEDEN bei JEDER Anmeldung, auch wen '
              'die Datenbank laengst kennt. Zustaendig ist allein die '
              'LegalGatePage hinter der Anmeldung.',
        );
        expect(
          quelle.contains('LegalAcceptancePage'),
          isFalse,
          reason:
              'Die Seite mit den Kaestchen gehoert hinter die Anmeldung, '
              'nicht davor.',
        );
      });

      test('das Tor hinter der Anmeldung bleibt stehen', () {
        // Ohne dieses Tor wuerde niemand mehr zustimmen — weder ein neues
        // Konto noch die Altkonten, die es nachholen sollen.
        expect(
          quelle.contains('LegalGatePage(child: PostAuthGate())'),
          isTrue,
          reason:
              'Nach der Anmeldung muss weiterhin die LegalGatePage stehen.',
        );
      });
    });
  }

  test('das Tor entscheidet anhand der Datenbank, nicht anhand des Geraets',
      () {
    // Der eigentliche Kern der Aufgabe: „nur beim Erstellen" bedeutet, dass
    // die Zustimmung am KONTO haengt und in `legal_acceptances` steht. Ein
    // Merker auf dem Geraet wuerde beim naechsten Handy wieder fragen.
    final dienst = File(
      'lib/data/services/legal_acceptance_service.dart',
    ).readAsStringSync();
    expect(dienst.contains("from('legal_acceptances')"), isTrue);
    expect(
      dienst.contains('hasCurrentAcceptance'),
      isTrue,
      reason:
          'Die Pruefung, ob schon zugestimmt wurde, muss die Tabelle '
          'befragen.',
    );
  });
}
