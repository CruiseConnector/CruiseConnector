import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/ride_rating_prompt_service.dart';

/// 2026-08-04 (vucko): „Nach der ersten Fahrt soll ein Pop-up kommen mit der
/// Sternebewertung. Nicht direkt nach dem Onboarding, weil die Leute kennen ja
/// die App nicht, sondern erst nach der ersten Fahrt, nachdem sie sie
/// abgeschlossen und dann entweder gespeichert oder verworfen haben. Auf gar
/// keinen Fall während der Fahrt. Und wenn sie nicht bewertet haben, soll es
/// alle drei Routen kommen."
///
/// 2026-08-11 (vucko, PRAEZISIERT): „Nach jeder dritten RUNDE, die man
/// gefahren ist, alleine oder in der Gruppe." Der Takt haengt seitdem an
/// abgeschlossenen FAHRTEN, nicht mehr an Routen-Ereignissen. Eine blosse
/// Routensuche zaehlt nicht mehr mit — sonst bekam das Popup, wer dreimal
/// suchte, ohne je zu fahren.
///
/// Diese Datei prüft jede dieser Regeln einzeln.
///
/// „Niemals während der Fahrt" steht bewusst NICHT hier: Das ist keine
/// Bedingung im Dienst, sondern ergibt sich daraus, dass nur die Home-Schale
/// beim Wechsel auf den Home-Tab fragt (home_page.dart,
/// `_pruefeBewertungsPopup`). Eine Bedingung kann man vergessen, den
/// Aufrufpunkt nicht.
void main() {
  late RideRatingPromptService dienst;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst = RideRatingPromptService.instance;
  });

  group('Nicht direkt nach dem Onboarding', () {
    test('frische Installation fragt nicht', () async {
      expect(await dienst.shouldPrompt(), isFalse);
    });

    test('auch nach mehreren Routensuchen ohne Fahrt wird nicht gefragt', () async {
      for (var i = 0; i < 10; i++) {
        await dienst.registerRouteEvent();
      }
      expect(
        await dienst.shouldPrompt(),
        isFalse,
        reason: 'Wer nur sucht und nie fährt, kennt die App noch nicht',
      );
    });
  });

  group('Erste Frage nach der ersten Fahrt', () {
    test('eine abgeschlossene Fahrt genügt', () async {
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isTrue);
    });

    test('nach dem Zeigen ist sofort wieder Ruhe', () async {
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isTrue);
      await dienst.markPromptShown();
      expect(
        await dienst.shouldPrompt(),
        isFalse,
        reason: 'Sonst käme es bei jedem Tab-Wechsel erneut',
      );
    });
  });

  group('Danach alle drei FAHRTEN', () {
    Future<void> ersteRundeAbhaken() async {
      await dienst.registerCompletedRide();
      await dienst.markPromptShown();
    }

    test('zwei Fahrten reichen noch nicht', () async {
      await ersteRundeAbhaken();
      await dienst.registerCompletedRide();
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isFalse);
    });

    test('die dritte Fahrt löst aus', () async {
      await ersteRundeAbhaken();
      await dienst.registerCompletedRide();
      await dienst.registerCompletedRide();
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isTrue);
    });

    test('reine Routensuchen zählen NICHT mehr mit', () async {
      // Bis 2026-08-11 löste das hier aus. Vucko wollte ausdrücklich den Takt
      // an gefahrenen Runden, nicht an Suchvorgängen — wer nur stöbert, soll
      // nicht nach einer Bewertung gefragt werden.
      await ersteRundeAbhaken();
      for (var i = 0; i < 10; i++) {
        await dienst.registerRouteEvent();
      }
      expect(await dienst.shouldPrompt(), isFalse);
    });

    test('eine Gruppenfahrt zählt genauso wie eine Solofahrt', () async {
      // Der Dienst unterscheidet bewusst nicht: cruise_mode_page meldet beide
      // über denselben Abschluss-Trichter (_presentCompletionSheet).
      await ersteRundeAbhaken();
      await dienst.registerCompletedRide();
      await dienst.registerCompletedRide();
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isTrue);
    });

    test('der Rhythmus beginnt nach jedem Popup von vorn', () async {
      await ersteRundeAbhaken();
      for (var i = 0; i < 3; i++) {
        await dienst.registerCompletedRide();
      }
      expect(await dienst.shouldPrompt(), isTrue);
      await dienst.markPromptShown();
      expect(await dienst.shouldPrompt(), isFalse);
      for (var i = 0; i < 2; i++) {
        await dienst.registerCompletedRide();
      }
      expect(await dienst.shouldPrompt(), isFalse);
      await dienst.registerCompletedRide();
      expect(await dienst.shouldPrompt(), isTrue);
    });
  });

  group('Wer bewertet hat, wird in Ruhe gelassen', () {
    test('nach markSettled fragt nichts mehr', () async {
      await dienst.registerCompletedRide();
      await dienst.markSettled();
      expect(await dienst.shouldPrompt(), isFalse);
      for (var i = 0; i < 20; i++) {
        await dienst.registerRouteEvent();
        await dienst.registerCompletedRide();
      }
      expect(
        await dienst.shouldPrompt(),
        isFalse,
        reason: 'Bewertet oder abgelehnt heißt endgültig',
      );
    });

    test('die Zähler laufen nach markSettled gar nicht mehr hoch', () async {
      await dienst.markSettled();
      await dienst.registerCompletedRide();
      expect(
        await dienst.debugState(),
        contains('Fahrten=0'),
        reason: 'Kein unnötiges Schreiben, wenn die Frage erledigt ist',
      );
    });
  });

  group('Die Drei-Schwelle ist die vereinbarte', () {
    test('ridesBetweenPrompts ist 3', () {
      expect(RideRatingPromptService.ridesBetweenPrompts, 3);
    });
  });
}
