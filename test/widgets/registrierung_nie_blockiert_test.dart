import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-31, Nutzer zsago888 (per Instagram gemeldet, mit Screenshot):
/// „Bro wenn ich mich bei deiner app anmelden willl kann ich kein
/// Benutzername eingeben, da steht Konnte gerade nicht prüfen." Er hat
/// mehrere Namen probiert, keiner ging durch.
///
/// GEMESSEN in den Serverprotokollen vom 30.08.: 531 Zeitüberschreitungen
/// (504), 465 Überlastungen (503) und 2675 abgebrochene Vorgänge binnen 24
/// Stunden. Die Namensprüfung selbst ist in Ordnung — gegen die Produktion
/// geprüft, sie liefert für seinen Namen sauber `available: true`, auch ohne
/// Anmeldung. Er ist schlicht in eine dieser Zeitüberschreitungen gelaufen.
///
/// DER EIGENTLICHE FEHLER war die Reaktion darauf: `_canLeaveUsernamePage`
/// verlangte den Zustand `available`, und ein nicht erreichbarer Prüfdienst
/// sperrte damit den „Weiter"-Knopf. Der Nutzer sass mit einem gültigen,
/// freien Namen fest und konnte kein Konto anlegen.
///
/// Die Vorabprüfung ist Komfort. Verbindlich ist `set_username` beim Tippen
/// auf „Weiter": dieselbe Eindeutigkeitsprüfung, serverseitig, mit „taken"
/// und „reserved" als Antwort. Ein unerreichbarer Vorab-Dienst darf nie der
/// Grund sein, warum jemand kein Konto bekommt.
void main() {
  final quelle = File(
    'lib/presentation/pages/onboarding/onboarding_wizard_page.dart',
  ).readAsStringSync();

  group('Der Weiter-Knopf sperrt nur bei bekannten Absagen', () {
    test('ein nicht erreichbarer Prüfdienst blockiert NICHT', () {
      final start = quelle.indexOf('bool get _canLeaveUsernamePage');
      expect(start, greaterThan(0));
      final bedingung = quelle.substring(start, start + 320);
      expect(
        bedingung.contains('_uState == _UNameState.error'),
        isTrue,
        reason:
            'Genau das war der Fehler: Bei "Konnte gerade nicht prüfen" war '
            '"Weiter" gesperrt, und der Nutzer kam nie zu einem Konto.',
      );
    });

    test('belegte und reservierte Namen sperren weiterhin', () {
      final start = quelle.indexOf('bool get _canLeaveUsernamePage');
      final bedingung = quelle.substring(start, start + 320);
      for (final zustand in <String>['taken', 'reserved', 'invalid']) {
        expect(
          bedingung.contains('_UNameState.$zustand'),
          isFalse,
          reason:
              'Der Zustand $zustand ist eine beantwortete Absage und darf '
              'nicht durchgelassen werden.',
        );
      }
    });

    test('der Server entscheidet beim Weitertippen verbindlich', () {
      // Ohne diese Absicherung waere das Durchlassen gefaehrlich: dann kaeme
      // ein doppelter Name durch. set_username prueft gegen denselben
      // eindeutigen Schluessel und meldet es zurueck.
      final start = quelle.indexOf('Future<bool> _commitUsername()');
      expect(start, greaterThan(0));
      final rumpf = quelle.substring(start, start + 1400);
      expect(rumpf.contains('SocialService.setUsername('), isTrue);
      expect(
        rumpf.contains("res.error == 'taken'"),
        isTrue,
        reason: 'Ein belegter Name muss beim Weitertippen auffallen.',
      );
      expect(
        rumpf.contains("res.error == 'reserved'"),
        isTrue,
        reason: 'Ein reservierter Name ebenso.',
      );
    });

    test('der Hinweistext sagt, wie es weitergeht', () {
      // „Konnte gerade nicht prüfen." allein liess offen, ob man festsitzt.
      final start = quelle.indexOf('_UNameState.error => (');
      expect(start, greaterThan(0));
      final text = quelle.substring(start, start + 260);
      expect(
        text.contains('Weiter'),
        isTrue,
        reason:
            'Der Text muss den Weg nennen, sonst probiert der Nutzer weiter '
            'Namen durch, wie im gemeldeten Fall.',
      );
    });
  });

  group('Die Prüfung selbst bleibt abgesichert', () {
    test('sie läuft mit Zeitgrenze', () {
      // Ohne Zeitgrenze bliebe der Zustand ewig auf "checking", und dann
      // sperrt der Knopf wieder — nur eine Ebene tiefer.
      final start = quelle.indexOf('void _onUsernameChanged(');
      expect(start, greaterThan(0));
      final rumpf = quelle.substring(start, start + 1500);
      expect(rumpf.contains('.timeout('), isTrue);
      expect(
        rumpf.contains("reason: 'error'"),
        isTrue,
        reason:
            'Nach der Zeitgrenze muss derselbe Zustand gelten wie bei einem '
            'Fehler, damit der Knopf freigibt.',
      );
    });
  });
}
