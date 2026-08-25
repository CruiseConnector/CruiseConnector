import 'dart:io';

import 'package:cruise_connect/presentation/widgets/app_tutorial_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-19 (vucko): „schau das das tutorial wirklich die ganze app
/// erklaert".
///
/// GEMESSENER IST-ZUSTAND vor dieser Aenderung: genau 7 Schritte. Abgedeckt
/// waren der Cruise-Knopf und die Community-Reiter Feed, Gruppen/Fahrten und
/// Entdecken. NICHT abgedeckt, obwohl vorhanden:
///   - der Community-Reiter „Chats" (Registry-Schluessel `communityChats` war
///     in community_page.dart:485 gemeldet, kein Schritt zeigte darauf)
///   - Analytics (Reiter 3): kein Schritt hatte `tab: 3`
///   - Profil (Reiter 4) und die Garage: kein Schritt hatte `tab: 4`
///   - die Startseite selbst: Schritt 1 und 7 liefen dort, zeigten aber auf
///     nichts
///   - alles nach der Fahrt (beenden, Foto, Speichern, XP)
/// Dazu der Widerspruch in settings_page.dart: der Untertitel versprach
/// „Analytics" und „Profil", die im Tutorial gar nicht vorkamen.
///
/// Diese Tests waren vor der Aenderung ROT (Gegenprobe im Bericht).
void main() {
  /// Ergebnis eines kompletten Durchlaufs durch das Overlay.
  ///
  /// Beim Durchlauf werden die Pflicht-Aktionen der beiden Attrappen
  /// erledigt, sonst bliebe „Weiter" gesperrt.
  Future<_Durchlauf> laufeDurch(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    final tabs = <int>[];
    final sections = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF05070B),
          body: AppTutorialOverlay(
            onTabChange: tabs.add,
            onCommunitySectionChange: sections.add,
            loadMemberSince: () async => DateTime(2026, 3, 14),
            claimReward: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titel = <String>[];
    final zaehler = <String>[];
    final koerper = <String>[];
    final alleTexte = <String>[];

    void sammleTexte() {
      alleTexte.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>(),
      );
    }

    // Der Zaehler ist die einzige Text-Anzeige der Form „3/12".
    String aktuellerZaehler() {
      final treffer = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => RegExp(r'^\d+/\d+$').hasMatch(s))
          .toList();
      expect(treffer, hasLength(1), reason: 'genau ein Schritt-Zaehler');
      return treffer.first;
    }

    // Titel = die fette 22er-Zeile in der Karte.
    String aktuellerTitel() {
      final treffer = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.fontSize == 22 && t.data != null)
          .map((t) => t.data!)
          .toList();
      expect(treffer, isNotEmpty, reason: 'jeder Schritt hat einen Titel');
      return treffer.first;
    }

    // Der Fliesstext (13.6 px) beschreibt den Bereich.
    String aktuellerKoerper() {
      final treffer = tester
          .widgetList<Text>(find.byType(Text))
          .where((t) => t.style?.fontSize == 13.6 && t.data != null)
          .map((t) => t.data!)
          .toList();
      return treffer.isEmpty ? '' : treffer.first;
    }

    // Hoechstens 40 Runden, damit ein Fehler nicht in eine Endlosschleife
    // laeuft.
    for (var runde = 0; runde < 40; runde++) {
      zaehler.add(aktuellerZaehler());
      titel.add(aktuellerTitel());
      koerper.add(aktuellerKoerper());

      // Pflicht-Aktion (a): Routensuche in der Attrappe starten.
      if (find.text('Route suchen').evaluate().isNotEmpty) {
        await tester.tap(find.text('Route suchen'));
        await tester.pumpAndSettle();
      }
      // Pflicht-Aktion (b): Adresse antippen, dann Stern.
      if (find.text('Feldkirch, Vorarlberg').evaluate().isNotEmpty) {
        await tester.tap(find.text('Feldkirch, Vorarlberg'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(CupertinoIcons.star));
        await tester.pumpAndSettle();
      }
      // NACH den Aktionen sammeln: die Erfolgstexte der Attrappen erscheinen
      // erst dann.
      sammleTexte();

      final weiter = find.widgetWithText(FilledButton, 'Weiter');
      if (weiter.evaluate().isEmpty) break; // letzter Schritt: „Fertig"
      expect(
        tester.widget<FilledButton>(weiter).onPressed,
        isNotNull,
        reason: 'Schritt ${zaehler.last} („${titel.last}") blockiert Weiter',
      );
      await tester.tap(weiter);
      await tester.pumpAndSettle();
    }

    return _Durchlauf(
      tabs: tabs,
      sections: sections,
      titel: titel,
      zaehler: zaehler,
      koerper: koerper,
      alleTexte: alleTexte,
    );
  }

  testWidgets('das Tutorial besucht JEDEN Reiter der App', (tester) async {
    final lauf = await laufeDurch(tester);

    expect(
      lauf.tabs.toSet(),
      containsAll(<int>[0, 1, 2, 3, 4]),
      reason:
          'Home, Community, Cruise, Analytics und Profil. Vorher fehlten 3 '
          '(Analytics) und 4 (Profil) komplett.',
    );
  });

  testWidgets('alle vier Community-Reiter kommen vor, auch Chats', (
    tester,
  ) async {
    final lauf = await laufeDurch(tester);

    expect(
      lauf.sections.toSet(),
      containsAll(<int>[0, 1, 2, 3]),
      reason:
          'Feed, Gruppen & Fahrten, Chats, Entdecken. Reiter 2 (Chats) hatte '
          'einen Registry-Schluessel, aber keinen Schritt.',
    );
  });

  testWidgets('Startseite, Fahrt-Ende, Analytics, Profil und Garage erklaert', (
    tester,
  ) async {
    final lauf = await laufeDurch(tester);
    final alles = '${lauf.titel.join(' | ')} || ${lauf.koerper.join(' | ')}';

    // Startseite: Starter-Paket UND Fortschritts-Kacheln.
    expect(alles, contains('Starterpaket'));
    expect(alles, contains('Kacheln'));
    // Was nach der Fahrt passiert.
    expect(alles, contains('Fahrt beenden'));
    expect(alles, contains('Foto'));
    expect(alles, contains('Speichern'));
    expect(alles, contains('XP'));
    // Analytics und Profil samt Garage.
    expect(lauf.titel, contains('Analytics'));
    expect(alles, contains('Rangliste'));
    expect(alles, contains('Meine Garage'));
    expect(lauf.titel, contains('Chats'));
  });

  testWidgets('der Zaehler zaehlt sauber von 1 bis N durch', (tester) async {
    final lauf = await laufeDurch(tester);

    final anzahl = lauf.zaehler.length;
    expect(
      anzahl,
      greaterThanOrEqualTo(12),
      reason: 'sieben Schritte reichten fuer die ganze App nicht',
    );
    for (var i = 0; i < anzahl; i++) {
      expect(lauf.zaehler[i], '${i + 1}/$anzahl');
    }
  });

  testWidgets('die Attrappen behaupten NICHT, die Aufgabe sei erledigt', (
    tester,
  ) async {
    final lauf = await laufeDurch(tester);
    final alles = lauf.gesamttext;

    // Der alte Text log: es wird nichts gespeichert, die Starter-Aufgabe
    // „Eine Adresse merken" bleibt offen.
    expect(alles, isNot(contains('Findest du ab jetzt in deinen Favoriten')));
    expect(alles, isNot(contains('Route gefunden')));
    // Stattdessen: klar als Uebung/Beispiel benannt.
    expect(alles, contains('Übung'));
    expect(alles, contains('Beispielroute'));
    // Und der Hinweis, wo die Aufgabe wirklich abgehakt wird.
    expect(
      RegExp('Aufgabe im Starterpaket').allMatches(alles).length,
      greaterThanOrEqualTo(2),
      reason: 'beide Attrappen muessen es sagen, nicht nur eine',
    );
  });

  testWidgets(
    'der Untertitel in den Einstellungen verspricht nichts Unerklaertes',
    (tester) async {
      final lauf = await laufeDurch(tester);

      final quelle = File(
        'lib/presentation/pages/settings_page.dart',
      ).readAsStringSync();
      final stelle = quelle.indexOf("'Tutorial nochmal anschauen'");
      expect(stelle, greaterThan(0));
      // `subtitle:` und der Text stehen je nach Zeilenlaenge in einer oder in
      // zwei Zeilen (dart format).
      final untertitel = RegExp(
        r"subtitle:\s*'([^']+)'",
      ).firstMatch(quelle.substring(stelle))!.group(1)!;

      // Jeder im Untertitel genannte Bereich muss einem Reiter entsprechen,
      // den das Tutorial auch wirklich ansteuert.
      const reiterFuerBereich = <String, int>{
        'Startseite': 0,
        'Community': 1,
        'Cruise': 2,
        'Analytics': 3,
        'Profil': 4,
      };
      final besucht = lauf.tabs.toSet();
      for (final eintrag in reiterFuerBereich.entries) {
        if (!untertitel.contains(eintrag.key)) continue;
        expect(
          besucht,
          contains(eintrag.value),
          reason:
              '„${eintrag.key}" steht im Untertitel, das Tutorial geht aber '
              'nie auf Reiter ${eintrag.value}',
        );
      }
      // Und der Untertitel darf die Bereiche nicht verschweigen.
      expect(untertitel, contains('Analytics'));
      expect(untertitel, contains('Profil'));
    },
  );
}

class _Durchlauf {
  const _Durchlauf({
    required this.tabs,
    required this.sections,
    required this.titel,
    required this.zaehler,
    required this.koerper,
    required this.alleTexte,
  });

  final List<int> tabs;
  final List<int> sections;
  final List<String> titel;
  final List<String> zaehler;
  final List<String> koerper;

  /// Jeder sichtbare Text jedes Schritts, inklusive der Erfolgstexte der
  /// beiden Attrappen (die stehen in der Karte, nicht im Fliesstext).
  final List<String> alleTexte;

  String get gesamttext => alleTexte.join(' | ');
}
