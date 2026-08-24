import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cruise_connect/core/legal_documents.dart';
import 'package:cruise_connect/data/services/legal_acceptance_service.dart';
import 'package:cruise_connect/presentation/pages/legal_acceptance_page.dart';
import 'package:cruise_connect/presentation/pages/legal_gate_page.dart';
import 'package:cruise_connect/presentation/utils/legal_link_launcher.dart';

/// 2026-08-24 (Vorfall „Nutzer sitzt im Rechts-Tor fest"): Das Rechts-Tor
/// laeuft VOR der ganzen App. Es hatte genau EINEN Ausgang — den Weiter-Knopf
/// —, und der haing an zwei Haekchen, die erst freigaben, wenn
/// `launchLegalDocument` true lieferte. Das war `launchUrl` mit
/// `LaunchMode.externalApplication`, also ein EXTERNER Browser.
///
/// Ist auf dem Geraet kein Browser startbar — Bildschirmzeit („Web-Inhalte
/// beschraenken"), verwaltetes Geraet, Browser deaktiviert, kein
/// Standardbrowser gesetzt —, lieferte der Start false. Damit blieben die
/// Haekchen fuer immer gesperrt, der Weiter-Knopf auch, und Zurueck gab es
/// nicht (`PopScope(canPop: false)`, kein Zurueck-Pfeil). Die App war ab dem
/// Start unbenutzbar; Neuinstallation half nicht, weil die Sperre am Konto
/// haengt. Bildschirmzeit-Beschraenkungen sind bei jungen Fahrern verbreitet
/// — also genau bei der Zielgruppe.
///
/// Die Regel, die diese Datei festhaelt: Aus dem Rechts-Tor MUSS immer ein
/// Weg herausfuehren, der ohne Netz, ohne Browser und ohne Antwort des
/// Systems funktioniert. Das Tor darf sperren, aber der Nutzer muss dort
/// etwas tun koennen, das ihn weiterbringt. Die Zustimmung bleibt echt: der
/// Ersatzweg zeigt die vollstaendige Adresse und verlangt eine ausdrueckliche
/// Bestaetigung, die in der Zustimmung mitprotokolliert wird.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugLegalUrlOpener = null;
  });

  // ──────────────────────────────────────────────────────────────────────
  // 1. Der Vorfall: kein Browser auf dem Geraet
  // ──────────────────────────────────────────────────────────────────────

  group('Rechts-Tor ohne startbaren Browser', () {
    testWidgets(
      'Ersatzweg gibt die Haekchen frei — der Weiter-Knopf wird bedienbar',
      (tester) async {
        debugLegalUrlOpener = (uri, mode) async => false; // kein Browser da

        await _pumpeTor(tester);

        // Der Nutzer versucht beide Texte zu lesen. Beide Male passiert nichts.
        await _tippeLesen(tester, 0);
        await _tippeLesen(tester, 1);

        // Vorbedingung: ueber den Browser kommt hier niemand weiter.
        expect(
          _weiterFrei(tester),
          isFalse,
          reason: 'Ohne gelesene Texte darf der Weiter-Knopf nicht freigeben.',
        );

        // Der Ersatzweg steht fuer BEIDE Dokumente bereit und nennt die
        // vollstaendige Adresse, damit der Nutzer sie anderswo lesen kann.
        expect(find.text(LegalDocuments.terms.url), findsOneWidget);
        expect(find.text(LegalDocuments.privacy.url), findsOneWidget);
        expect(
          find.text('Adresse notiert — Häkchen freigeben'),
          findsNWidgets(2),
          reason:
              'Ohne Ersatzweg bleibt das Haekchen fuer immer gesperrt — genau '
              'die Sackgasse aus dem Vorfall.',
        );

        // Der Nutzer bestaetigt den Ersatzweg und setzt beide Haekchen.
        await tester.tap(find.text('Adresse notiert — Häkchen freigeben').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Adresse notiert — Häkchen freigeben').first);
        await tester.pumpAndSettle();

        expect(
          _gesperrteHaekchen(tester),
          0,
          reason: 'Nach dem Ersatzweg muessen beide Haekchen bedienbar sein.',
        );

        await _setzeHaekchen(tester, 0);
        await _setzeHaekchen(tester, 1);

        expect(
          _weiterFrei(tester),
          isTrue,
          reason:
              'Der Nutzer hat beide Texte zur Kenntnis genommen und beide '
              'Haekchen gesetzt — jetzt MUSS es weitergehen.',
        );
      },
    );

    testWidgets('Es gibt immer einen Ausweg, auch ohne Zurueck-Pfeil', (
      tester,
    ) async {
      debugLegalUrlOpener = (uri, mode) async => false;
      final wege = <String>[];

      await _pumpeTor(tester, onExit: (_) async => wege.add('abgemeldet'));

      // Kein Zurueck: das Tor darf nicht einfach uebersprungen werden.
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(find.byType(BackButton), findsNothing);

      // Aber es gibt einen bedienbaren Ausweg, der ohne Netz, ohne Browser
      // und ohne Antwort des Systems funktioniert.
      final ausweg = find.widgetWithText(TextButton, 'Abmelden');
      expect(
        ausweg,
        findsOneWidget,
        reason:
            'Ohne Ausweg steht ein Nutzer, der die Bedingungen nicht annehmen '
            'kann oder will, ohne jede Handlungsmoeglichkeit da.',
      );
      expect(tester.widget<TextButton>(ausweg).onPressed, isNotNull);

      await tester.tap(ausweg);
      await tester.pumpAndSettle();

      // Rueckfrage statt versehentlichem Abmelden — und der Dialog selbst ist
      // wegtippbar, sperrt also niemanden erneut ein.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Abmelden').last);
      await tester.pumpAndSettle();

      expect(wege, ['abgemeldet']);
    });

    testWidgets('Der Ersatzweg wird in der Zustimmung mitprotokolliert', (
      tester,
    ) async {
      debugLegalUrlOpener = (uri, mode) async => false;

      await _pumpeTorMitUnterseite(tester);
      await _tippeLesen(tester, 0);
      await _tippeLesen(tester, 1);
      await tester.tap(find.text('Adresse notiert — Häkchen freigeben').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adresse notiert — Häkchen freigeben').first);
      await tester.pumpAndSettle();
      await _setzeHaekchen(tester, 0);
      await _setzeHaekchen(tester, 1);
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Bestätigen und fortfahren'),
      );
      await tester.pumpAndSettle();

      final gemerkt = await LegalAcceptanceService.pendingPreAuthAcceptance();
      expect(gemerkt, isNotNull);
      expect(
        gemerkt!.readPath,
        LegalAcceptanceSnapshot.readPathLinkFallback,
        reason:
            'Die Zustimmung muss nachweisbar bleiben: es muss erkennbar sein, '
            'dass die Texte ueber die Adresse statt im Browser zugaenglich '
            'gemacht wurden.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 2. Der normale Weg bleibt heil
  // ──────────────────────────────────────────────────────────────────────

  group('Der normale Lese-Weg', () {
    testWidgets('Oeffnet der Browser, gibt es keinen Ersatzweg und kein Tor', (
      tester,
    ) async {
      debugLegalUrlOpener = (uri, mode) async => true;

      await _pumpeTor(tester);
      await _tippeLesen(tester, 0);
      await _tippeLesen(tester, 1);

      expect(find.text(LegalDocuments.terms.url), findsNothing);
      expect(find.text('Adresse notiert — Häkchen freigeben'), findsNothing);
      expect(_gesperrteHaekchen(tester), 0);
    });

    testWidgets('Ungelesen bleibt ungelesen — das Tor sperrt weiterhin', (
      tester,
    ) async {
      debugLegalUrlOpener = (uri, mode) async => true;

      await _pumpeTor(tester);

      expect(
        _gesperrteHaekchen(tester),
        2,
        reason: 'Ohne Lese-Schritt darf kein Haekchen setzbar sein.',
      );
      expect(_weiterFrei(tester), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 3. Der Start-Versuch selbst
  // ──────────────────────────────────────────────────────────────────────

  group('launchLegalDocument', () {
    testWidgets('Scheitert der eigene Browser, greift der In-App-Browser', (
      tester,
    ) async {
      final versucht = <LaunchMode>[];
      debugLegalUrlOpener = (uri, mode) async {
        versucht.add(mode);
        if (mode == LaunchMode.externalApplication) {
          throw Exception('kein Browser gesetzt');
        }
        return true;
      };

      expect(await launchLegalDocument(LegalDocuments.terms), isTrue);
      expect(versucht, [
        LaunchMode.externalApplication,
        LaunchMode.inAppBrowserView,
      ]);
    });

    testWidgets('Erst wenn ALLE Wege scheitern, ist es ein Fehlschlag', (
      tester,
    ) async {
      final versucht = <LaunchMode>[];
      debugLegalUrlOpener = (uri, mode) async {
        versucht.add(mode);
        return false;
      };

      expect(await launchLegalDocument(LegalDocuments.privacy), isFalse);
      expect(versucht, legalLaunchModes);
    });

    testWidgets('Antwortet das System gar nicht, laeuft eine Frist ab', (
      tester,
    ) async {
      // Der Plattform-Kanal antwortet nie — frueher haette der Aufrufer ewig
      // gewartet, mit einem stillstehenden Bildschirm davor.
      debugLegalUrlOpener = (uri, mode) => Completer<bool>().future;

      bool? ergebnis;
      unawaited(
        launchLegalDocument(
          LegalDocuments.terms,
        ).then((wert) => ergebnis = wert),
      );

      await tester.pump(const Duration(seconds: 1));
      expect(ergebnis, isNull, reason: 'Die Frist darf nicht sofort zuschlagen.');

      await tester.pump(legalLaunchTimeout * 3 + const Duration(seconds: 1));
      await tester.pump();
      expect(ergebnis, isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // 4. Der Fehler-Bildschirm des Tors (Vorfall 2026-07-21)
  // ──────────────────────────────────────────────────────────────────────

  testWidgets('Der Fehler-Bildschirm des Tors hat mehr als „Erneut versuchen"', (
    tester,
  ) async {
    final wege = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LegalGateErrorScreen(
          onRetry: () {},
          onExit: (_) async => wege.add('abgemeldet'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Erneut versuchen'), findsOneWidget);
    await tester.tap(find.text('Abmelden und zurück zum Start'));
    await tester.pumpAndSettle();

    expect(
      wege,
      ['abgemeldet'],
      reason:
          'Am 21.07. lag der Fehler in der Datenbank, nicht am Geraet — '
          '„Erneut versuchen" half nicht, und alle Nutzer standen fest.',
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════
// Werkzeuge
// ═════════════════════════════════════════════════════════════════════════

/// Ein hoher Bildschirm, damit die ListView den Weiter-Knopf wirklich baut —
/// sonst prueft der Test einen Knopf, den es im Baum gar nicht gibt.
void _grossesGeraet(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(430, 1800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpeTor(
  WidgetTester tester, {
  Future<void> Function(BuildContext context)? onExit,
}) async {
  _grossesGeraet(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: LegalAcceptancePage(
        source: 'test',
        persistAcceptance: false,
        canGoBack: false,
        onExit: onExit,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Wie `_pumpeTor`, aber mit einer Seite darunter — damit das Tor sich beim
/// Bestaetigen schliessen kann.
Future<void> _pumpeTorMitUnterseite(WidgetTester tester) async {
  _grossesGeraet(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<LegalAcceptanceSnapshot>(
                  builder: (_) => const LegalAcceptancePage(
                    source: 'test',
                    persistAcceptance: false,
                    canGoBack: false,
                  ),
                ),
              ),
              child: const Text('Tor öffnen'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Tor öffnen'));
  await tester.pumpAndSettle();
}

Future<void> _tippeLesen(WidgetTester tester, int index) async {
  final knopf = find.byIcon(Icons.open_in_new).at(index);
  await tester.tap(knopf);
  await tester.pumpAndSettle();
}

Future<void> _setzeHaekchen(WidgetTester tester, int index) async {
  await tester.tap(find.byType(CheckboxListTile).at(index));
  await tester.pumpAndSettle();
}

int _gesperrteHaekchen(WidgetTester tester) => tester
    .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
    .where((tile) => tile.onChanged == null)
    .length;

bool _weiterFrei(WidgetTester tester) {
  final knopf = tester.widget<ElevatedButton>(
    find.widgetWithText(ElevatedButton, 'Bestätigen und fortfahren'),
  );
  return knopf.onPressed != null;
}
