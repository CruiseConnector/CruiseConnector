import 'dart:async';
import 'dart:io';

import 'package:cruise_connect/presentation/pages/onboarding/post_auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 (Vorfall „Nutzer sitzt fest"): Derselbe Baufehler wie im Blatt
/// „Routing verstehen", nur an der Stelle, die JEDER Nutzer nach JEDER
/// Anmeldung durchläuft — dem Post-Auth-Tor.
///
/// Das Tor zeigte einen Ladekreis, solange `SocialService.needsOnboarding()`
/// lief. Diese Abfrage hatte KEINE Zeitgrenze. Kein Abbrechen, kein Zurück,
/// kein X. Fehler waren sauber abgefangen (sie fallen defensiv auf die
/// Startseite) — ein Hänger nicht. Bei schlechtem Netz drehte sich der Kreis
/// also endlos, und ein Neustart lief in dasselbe Loch.
///
/// Die Regel: Es muss immer einen Weg nach draußen geben, der ohne Netz und
/// ohne Antwort des Servers funktioniert. Der Ausweg darf deshalb NICHT an der
/// Antwort hängen, sondern nur an der Uhr.
///
/// Diese Datei hält zwei Dinge fest:
///
///  1. **Verhalten**: Eine Prüfung, die nie zurückkommt, führt trotzdem zu
///     bedienbaren Knöpfen — und zwar zu solchen, die etwas bewirken.
///  2. **Umfang**: Ein Quelltext-Wächter verlangt, dass jeder Netzaufruf, auf
///     den der Onboarding-Assistent mit gesperrtem Bildschirm (`_busy`)
///     wartet, eine Zeitgrenze trägt. Ein `finally` reicht dort NICHT: bei
///     einem hängenden `await` läuft es nie.
void main() {
  group('Post-Auth-Tor: der Ladekreis ist keine Sackgasse', () {
    testWidgets('Prüfung kommt nie zurück → Nutzer bekommt trotzdem Auswege', (
      tester,
    ) async {
      // Ein Future, das NIE abgeschlossen wird: genau der Hänger aus dem
      // Vorfall (Server antwortet nicht, kein Fehler, keine Antwort).
      final haenger = Completer<bool>();
      var aufrufe = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: PostAuthGate(
            wartezeitBisAusweg: const Duration(seconds: 8),
            onboardingPruefung: () {
              aufrufe++;
              return haenger.future;
            },
          ),
        ),
      );

      // Erster Moment: nur der Ladekreis — die 99 %, bei denen die Antwort
      // sofort da ist, sollen nichts Zusätzliches sehen.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsNothing);

      // Nach der Wartezeit MUSS ein Ausweg da sein, obwohl die Prüfung
      // weiterhin läuft. Genau das konnte die alte Fassung nicht.
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.text('Trotzdem zur App'), findsOneWidget);
      expect(find.text('Abmelden'), findsOneWidget);

      // Die Knöpfe müssen auch bedienbar sein (nicht nur sichtbar) …
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );

      // … und sie müssen etwas bewirken: „Erneut versuchen" startet die
      // Prüfung wirklich neu und blendet den Ausweg wieder aus.
      expect(aufrufe, 1);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      expect(aufrufe, 2);
      expect(find.text('Erneut versuchen'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Der zweite Versuch führt wieder zum Ausweg — kein Einweg-Notausgang.
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('Trotzdem zur App'), findsOneWidget);

      // Baum abräumen, damit kein Timer offen bleibt (dispose bricht ihn ab).
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Zeitgrenze der Prüfung → Ausweg statt stiller Entscheidung', (
      tester,
    ) async {
      // `needsOnboarding` wirft nach seiner eigenen Zeitgrenze. Das Tor darf
      // daraufhin NICHT wortlos weiterschalten, sondern muss fragen — wer
      // gerade ein Konto erstellt hat, braucht den Assistenten.
      final abgelaufen = Completer<bool>();
      await tester.pumpWidget(
        MaterialApp(
          home: PostAuthGate(
            wartezeitBisAusweg: const Duration(seconds: 8),
            onboardingPruefung: () => abgelaufen.future,
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      abgelaufen.completeError(
        TimeoutException('needsOnboarding', const Duration(seconds: 12)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('antwortet nicht'), findsOneWidget);
      expect(find.text('Erneut versuchen'), findsOneWidget);
      expect(find.text('Trotzdem zur App'), findsOneWidget);
      // Kein Ladekreis mehr: der Zustand ist entschieden, nur eben nicht gut.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Umfang: das Muster darf sich nicht unbemerkt vermehren
  // ───────────────────────────────────────────────────────────────────────

  group('Zeitgrenzen bleiben da, wo ein Bildschirm wartet', () {
    test('needsOnboarding hat eine Zeitgrenze und verschluckt sie nicht', () {
      final quelle = File(
        'lib/data/services/social_service.dart',
      ).readAsStringSync();
      final block = _methodenBlock(
        quelle,
        'static Future<bool> needsOnboarding',
      );
      expect(
        block.contains('.timeout('),
        isTrue,
        reason:
            'needsOnboarding traegt das Post-Auth-Tor. Ohne Zeitgrenze dreht '
            'sich dort bei schlechtem Netz ein Ladekreis ohne Ende.',
      );
      expect(
        block.contains('on TimeoutException'),
        isTrue,
        reason:
            'Ein Haenger ist kein Fehler mit Antwort: er muss beim Aufrufer '
            'ankommen, damit der dem Nutzer die Wahl lassen kann.',
      );
    });

    test('jeder Aufruf, der den Assistenten sperrt, hat eine Zeitgrenze', () {
      final quelle = File(
        'lib/presentation/pages/onboarding/onboarding_wizard_page.dart',
      ).readAsStringSync();

      // Alle awaits auf unsere eigenen Dienste — an genau diesen wartet der
      // Assistent mit `_busy = true`, also mit totem Weiter/Ueberspringen/
      // Zurueck und ohne Zurueck-Geste (PopScope(canPop: false)).
      final aufrufe = RegExp(
        r'await (AuthService|SocialService)\.([A-Za-z]+)\(',
      ).allMatches(quelle);
      expect(aufrufe, isNotEmpty);

      final ohneGrenze = <String>[];
      for (final m in aufrufe) {
        final ende = _klammerEnde(quelle, m.end - 1);
        // Alles bis zum Semikolon nach der schliessenden Klammer ansehen —
        // dort steht ein etwaiges `.timeout(...)`.
        final schwanz = quelle.substring(ende, quelle.indexOf(';', ende) + 1);
        if (!schwanz.contains('.timeout(')) ohneGrenze.add(m.group(0)!);
      }
      expect(
        ohneGrenze,
        isEmpty,
        reason:
            'Ohne Zeitgrenze laeuft das `finally` nie, `_busy` bleibt true und '
            'der Nutzer sitzt im Assistenten fest: ${ohneGrenze.join(', ')}',
      );
    });
  });
}

/// Schneidet den Quelltext einer Methode ab ihrer Signatur bis zum Beginn der
/// naechsten Methode heraus (grob, aber ausreichend fuer den Waechter).
String _methodenBlock(String quelle, String signatur) {
  final start = quelle.indexOf(signatur);
  expect(start, greaterThan(-1), reason: 'Signatur nicht gefunden: $signatur');
  final rest = quelle.substring(start);
  final ende = rest.indexOf('\n  }\n');
  return ende < 0 ? rest : rest.substring(0, ende);
}

/// Liefert die Position HINTER der zur oeffnenden Klammer an [auf] passenden
/// schliessenden Klammer.
int _klammerEnde(String quelle, int auf) {
  var tiefe = 0;
  for (var i = auf; i < quelle.length; i++) {
    final c = quelle[i];
    if (c == '(') tiefe++;
    if (c == ')') {
      tiefe--;
      if (tiefe == 0) return i + 1;
    }
  }
  return quelle.length;
}
