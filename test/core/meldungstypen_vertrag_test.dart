// 2026-08-31 — Waechter fuer den Vertrag rund um notifications.type.
//
// WARUM ES DIESEN TEST GIBT
//
// Beim Einbau der Webseiten-Meldung (Auftrag 13) war der neue Typ an DREI
// Stellen noetig, und ich hatte zunaechst nur eine bedacht:
//
//   1. Die Pruefregel notifications_type_check in der Datenbank. Fehlt der
//      Typ dort, schlaegt das Einfuegen fehl — laut und sofort. Das ist der
//      gutartige Fall, und er hat den Einbau tatsaechlich gestoppt.
//   2. supabase/functions/send-push. Fehlt der Typ dort, faellt die Funktion
//      in ihren default-Zweig und schickt "Benachrichtigung" plus einen
//      Namen. Der Nutzer sieht auf dem Sperrbildschirm etwas Nichtssagendes.
//   3. NotificationService im Client. Fehlt der Typ dort, steht in der Liste
//      in der App dasselbe Nichtssagende.
//
// Faelle 2 und 3 sind die gefaehrlichen: kein Fehler, kein Protokolleintrag,
// nur eine Meldung, die niemandem etwas sagt. Genau davor schuetzt dieser
// Test.
//
// Er prueft nur die Typen, die ihren Wortlaut SELBST mitbringen (monitor_alarm
// und webseite_anmeldung). Die sozialen Typen bauen ihren Text aus Namen und
// Zahlen zusammen; fuer die gilt der Vertrag nicht.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Typen, die Titel und Text in ihrer Nutzlast tragen und deshalb an allen
/// drei Stellen einen eigenen Zweig brauchen.
const eigenerWortlaut = <String>['monitor_alarm', 'webseite_anmeldung'];

void main() {
  late String migration;
  late String sendPush;
  late String client;

  setUpAll(() {
    // Die juengste Migration, die die Pruefregel setzt.
    final treffer =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .where(
              (f) => f.readAsStringSync().contains('notifications_type_check'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(
      treffer,
      isNotEmpty,
      reason:
          'Keine Migration setzt notifications_type_check. Wurde die Regel '
          'umbenannt? Dann diesen Waechter mitziehen.',
    );
    migration = treffer.last.readAsStringSync();
    sendPush = File(
      'supabase/functions/send-push/index.ts',
    ).readAsStringSync();
    client = File(
      'lib/data/services/notification_service.dart',
    ).readAsStringSync();
  });

  group('Ein Meldungstyp muss an allen drei Stellen bekannt sein', () {
    for (final typ in eigenerWortlaut) {
      test('$typ steht in der Pruefregel der Datenbank', () {
        expect(
          migration.contains("'$typ'"),
          isTrue,
          reason:
              'Ohne den Typ in notifications_type_check schlaegt jedes '
              'Einfuegen fehl und es wird gar nichts gemeldet.',
        );
      });

      test('$typ hat einen eigenen Zweig in send-push', () {
        expect(
          sendPush.contains("case '$typ':"),
          isTrue,
          reason:
              'Ohne eigenen Zweig faellt send-push in den default und schickt '
              '"Benachrichtigung" statt des Wortlauts aus der Nutzlast. Auf '
              'dem Sperrbildschirm steht dann etwas Nichtssagendes, und '
              'niemand merkt es, weil kein Fehler entsteht.',
        );
      });

      test('$typ hat einen eigenen Zweig im Client', () {
        expect(
          client.contains("case '$typ':"),
          isTrue,
          reason:
              'Ohne eigenen Zweig zeigt die Liste in der App nur '
              '"Benachrichtigung" und einen Namen, der hier niemandem hilft.',
        );
      });
    }

    test('beide Seiten lesen denselben Wortlaut aus der Nutzlast', () {
      // send-push und Client muessen aus title/body rendern, nicht aus einem
      // fest verdrahteten Text. Sonst laufen Sperrbildschirm und App-Liste
      // auseinander — genau der Fehler, den die Wetter-Meldung schon hatte.
      for (final quelle in [sendPush, client]) {
        final stelle = quelle.indexOf("case 'webseite_anmeldung':");
        expect(stelle, greaterThanOrEqualTo(0));
        final block = quelle.substring(
          stelle,
          stelle + 600 > quelle.length ? quelle.length : stelle + 600,
        );
        // TypeScript schreibt payload.title, Dart payload['title'] — beide
        // Schreibweisen gelten.
        expect(
          block.contains("payload.title") || block.contains("payload['title']"),
          isTrue,
          reason:
              'Der Titel muss aus der Nutzlast kommen, nicht fest im Code '
              'stehen. Sonst laufen Sperrbildschirm und App-Liste '
              'auseinander.',
        );
        expect(
          block.contains("payload.body") || block.contains("payload['body']"),
          isTrue,
          reason: 'Der Text muss aus der Nutzlast kommen.',
        );
      }
    });
  });
}
