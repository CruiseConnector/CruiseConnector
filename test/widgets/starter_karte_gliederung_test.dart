import 'dart:convert';

import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/presentation/widgets/starter_bereiche.dart';
import 'package:cruise_connect/presentation/widgets/starter_paket_karte.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-25 (vucko wörtlich): „mache es so das die leute es zuklappen
/// koennen und das ganze besser gegliedert ist unter fahren unter community
/// usw. und das auch noch ausklappen koennen sonnst ist es zu unuebersichtlich
/// das man auch sieht was man als belohnung bekommt unten [...] und auch noch
/// soll beim ausklappen eine coole kleine animation sein beim ersten mal [...]
/// und es soll besser eingerahmt sein pro aufgabe".
///
/// DIE ZAHL, UM DIE ES GEHT (gemessen im selben Aufbau wie hier, 320 Punkte
/// Breite, frisches Konto):
///
///   vorher   2165 pt Kartenhöhe, davon 1870 pt flache Aufgabenliste
///   nachher    759 pt
///
/// [maximaleHoehe] nagelt das fest. Der Wert liegt bewusst deutlich über den
/// gemessenen 759 (Schriftmetriken schwanken zwischen Plattformen), aber weit
/// unter dem alten Zustand: Wer die Gliederung wieder ausbaut, kommt nie unter
/// diese Schranke.
const double maximaleHoehe = 900;

void main() {
  final dienst = StarterAufgabenService.instance;

  List<String> alleZwoelf() =>
      StarterAufgabenService.aufgaben.map((a) => a.id).toList();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dienst.resetForTests();
    StarterKartenGedaechtnis.resetForTests();
  });

  Future<void> zeige(
    WidgetTester tester, {
    List<String> erledigt = const [],
    double breite = 320,
    ValueChanged<int>? onTabChange,
    bool bewegungReduzieren = false,
    bool settle = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'starter_aufgaben_erledigt_v1': jsonEncode(erledigt),
    });
    dienst.resetForTests();
    tester.view.physicalSize = Size(breite, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: bewegungReduzieren),
          child: Scaffold(
            body: SingleChildScrollView(
              child: StarterPaketKarte(onTabChange: onTabChange),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder aufgabe(String id) => find.byKey(ValueKey('starter_aufgabe_$id'));
  Finder bereich(String id) => find.byKey(ValueKey('starter_bereich_$id'));

  group('Gliederung: jede Aufgabe hat genau einen Bereich', () {
    test('alle zwoelf sind zugeordnet, keine doppelt, kein Auffangbereich', () {
      final verteilt = <String>[];
      for (final inhalt in starterBereicheMitAufgaben()) {
        expect(
          inhalt.bereich.id,
          isNot(starterBereichWeiteres.id),
          reason:
              'Eine Aufgabe aus starter_aufgaben_service.dart steht in keinem '
              'Bereich. Der Auffangbereich rettet die Anzeige, aber die '
              'Zuordnung gehoert nachgetragen: ${inhalt.aufgaben.map((a) => a.id)}',
        );
        verteilt.addAll(inhalt.aufgaben.map((a) => a.id));
      }
      expect(verteilt.toSet().length, verteilt.length, reason: 'keine doppelt');
      expect(verteilt.toSet(), alleZwoelf().toSet());
    });

    test('die Bereiche heissen so, wie ein Fahrer sie sucht', () {
      expect(
        starterBereiche.map((b) => b.titel).toList(),
        ['Fahren', 'Community', 'Dein Profil'],
      );
    });

    test('unbekannte Aufgaben fallen nicht unter den Tisch', () {
      // Die Zuordnung kennt keine Aufgabe „bratwurst" — trotzdem darf keine
      // Aufgabe des Dienstes unsichtbar werden. Hier wird nur geprueft, dass
      // der Auffangbereich existiert und leer bleibt, solange alles passt.
      expect(starterBereichWeiteres.aufgabenIds, isEmpty);
      final ids = starterBereiche.expand((b) => b.aufgabenIds).toSet();
      expect(ids.containsAll(alleZwoelf()), isTrue);
    });
  });

  group('Auslieferungszustand', () {
    testWidgets('genau EIN Bereich ist offen: der erste mit offener Aufgabe',
        (tester) async {
      await zeige(tester);

      // Alle drei Ueberschriften stehen da ...
      expect(bereich('fahren'), findsOneWidget);
      expect(bereich('community'), findsOneWidget);
      expect(bereich('profil'), findsOneWidget);

      // ... aber nur „Fahren" zeigt seine Aufgaben.
      expect(aufgabe('route'), findsOneWidget);
      expect(aufgabe('km50'), findsOneWidget);
      expect(
        aufgabe('community'),
        findsNothing,
        reason: 'Alles offen waere wieder die flache Liste von 2165 Punkten.',
      );
      expect(aufgabe('tutorial'), findsNothing);
    });

    testWidgets('offen ist der Bereich, in dem man wirklich steht',
        (tester) async {
      // Vuckos Stand vom 25.08.: „Fahren" und „Dein Profil" sind fertig, offen
      // sind nur hashtag und gruppenfahrt — beide in „Community".
      await zeige(tester, erledigt: const [
        'route', 'favorit', 'speichern', 'runde', 'km50',
        'tutorial', 'garage', 'abzeichen',
        'community', 'post',
      ]);
      expect(aufgabe('hashtag'), findsOneWidget);
      expect(aufgabe('gruppenfahrt'), findsOneWidget);
      expect(aufgabe('route'), findsNothing);
    });

    testWidgets('die Karte ist nicht laenger als vorher', (tester) async {
      await zeige(tester);
      final hoehe = tester.getSize(find.byType(StarterPaketKarte)).height;
      expect(
        hoehe,
        lessThan(maximaleHoehe),
        reason: 'Vorher: 2165 Punkte bei 320 Breite. Das war die Beschwerde.',
      );
    });

    testWidgets('auch bei 320 Punkten laeuft nichts ueber', (tester) async {
      await zeige(tester);
      expect(tester.takeException(), isNull);
      // Alle drei Bereiche aufklappen: der schlimmste Fall.
      for (final id in ['community', 'profil']) {
        await tester.tap(bereich(id));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Zuklappen und Ausklappen', () {
    testWidgets('ein Bereich laesst sich oeffnen und wieder schliessen',
        (tester) async {
      await zeige(tester);
      expect(aufgabe('post'), findsNothing);

      await tester.tap(bereich('community'));
      await tester.pumpAndSettle();
      expect(aufgabe('post'), findsOneWidget);

      await tester.tap(bereich('community'));
      await tester.pumpAndSettle();
      expect(aufgabe('post'), findsNothing);
    });

    testWidgets('der Vorgabe-Bereich laesst sich zuklappen', (tester) async {
      await zeige(tester);
      expect(aufgabe('route'), findsOneWidget);
      await tester.tap(bereich('fahren'));
      await tester.pumpAndSettle();
      expect(aufgabe('route'), findsNothing);
    });

    testWidgets('die ganze Karte laesst sich zuklappen und bleibt es',
        (tester) async {
      await zeige(tester);
      await tester.tap(find.byKey(const ValueKey('starter_karte_kopf')));
      await tester.pumpAndSettle();

      expect(bereich('fahren'), findsNothing);
      expect(aufgabe('route'), findsNothing);
      // Der Stand und der Grund bleiben sichtbar.
      expect(find.text('0/12'), findsOneWidget);
      expect(find.textContaining('Belohnung'), findsOneWidget);
      expect(
        tester.getSize(find.byType(StarterPaketKarte)).height,
        lessThan(200),
      );

      // Und es bleibt so, auch beim naechsten App-Start.
      expect(StarterKartenGedaechtnis.zugeklappt, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(StarterKartenGedaechtnis.kZugeklappt), isTrue);
    });

    testWidgets('zugeklappt gespeichert: die Karte kommt zugeklappt hoch',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': jsonEncode(const <String>[]),
        StarterKartenGedaechtnis.kZugeklappt: true,
      });
      dienst.resetForTests();
      StarterKartenGedaechtnis.resetForTests();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StarterPaketKarte()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dein Starter-Paket'), findsOneWidget);
      expect(aufgabe('route'), findsNothing);
      expect(bereich('fahren'), findsNothing);
    });
  });

  group('„Zeigen" bleibt erreichbar', () {
    testWidgets('auch in einem Bereich, der zugeklappt ausgeliefert wird',
        (tester) async {
      var tab = -1;
      await zeige(tester, onTabChange: (i) => tab = i);

      // „Community" ist im Auslieferungszustand ZU. Aufklappen, dann fuehrt
      // die Aufgabe genauso hin wie vorher in der flachen Liste.
      await tester.tap(bereich('community'));
      await tester.pumpAndSettle();
      await tester.tap(aufgabe('community'));
      await tester.pump();
      expect(tab, 1);
      // Die Fuehrung wartet 420 ms auf den Tabwechsel und zeigt dann ihren
      // Hinweis. Ohne dieses Warten bliebe ein Timer offen und der Test
      // scheiterte am Aufraeumen, nicht an der Sache.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    });

    testWidgets('jede offene Aufgabe traegt ihren Knopf', (tester) async {
      await zeige(tester);
      for (final b in ['fahren', 'community', 'profil']) {
        if (b != 'fahren') {
          await tester.tap(bereich(b));
          await tester.pumpAndSettle();
        }
      }
      for (final a in StarterAufgabenService.aufgaben) {
        expect(aufgabe(a.id), findsOneWidget, reason: a.id);
        final semantik = tester.getSemantics(aufgabe(a.id));
        expect(semantik.label, contains(a.titel));
      }
      // Der naechste Schritt jedes Bereichs traegt die Beschriftung „Zeigen",
      // die uebrigen den Pfeil. Drei Bereiche, also drei Knoepfe.
      expect(find.text('Zeigen'), findsNWidgets(3));
    });
  });

  group('Die Belohnung steht unten und ist konkret', () {
    testWidgets('Abzeichen „Startklar", 1000 XP, sieben Tage doppelte XP',
        (tester) async {
      await zeige(tester);
      expect(find.textContaining('Startklar'), findsOneWidget);
      expect(find.text('1000 XP'), findsOneWidget);
      expect(find.text('7 Tage doppelte XP'), findsOneWidget);
      expect(
        find.textContaining('Durchgespielt'),
        findsNothing,
        reason: '„das abzeichen nach dem onboarding soll startklar heissen '
            'und nicht durchgespielt".',
      );
    });

    testWidgets('sie steht UNTER allen Bereichen', (tester) async {
      await zeige(tester);
      final belohnung = tester.getTopLeft(find.byType(StarterBelohnungsBlock));
      for (final id in ['fahren', 'community', 'profil']) {
        expect(
          belohnung.dy,
          greaterThan(tester.getBottomLeft(bereich(id)).dy),
          reason: '„das man auch sieht was man als belohnung bekommt unten".',
        );
      }
    });

    testWidgets('keine der drei Beschriftungen wird abgeschnitten',
        (tester) async {
      // ACHTUNG BEIM LESEN DIESER ZAHLEN: Im Widget-Test rendert Flutter mit
      // der Testschrift, in der JEDES Zeichen ein Quadrat von der Hoehe der
      // Schriftgroesse ist. „Abzeichen Startklar" braucht dort 209 Punkte, bei
      // einer echten Schrift etwa die Haelfte. Was hier passt, passt auf jedem
      // Geraet — es ist der denkbar schlechteste Fall.
      //
      // Genau daran ist die erste Fassung gescheitert: „Abzeichen „Startklar""
      // als dritte Pille in einer Reihe bekam 242 Punkte und brauchte 254.
      await zeige(tester);
      for (final text in [
        'Startklar',
        '1000 XP',
        '7 Tage doppelte XP',
      ]) {
        final absatz = tester.renderObject<RenderParagraph>(
          find.textContaining(text).first,
        );
        expect(
          absatz.didExceedMaxLines,
          isFalse,
          reason: 'Bei 320 Punkten Breite darf „$text" nicht mit … enden.',
        );
      }
    });

    testWidgets('sie nennt den Rest der Liste, nicht die Boost-Schwelle',
        (tester) async {
      await zeige(tester);
      expect(find.text('Noch 12 Schritte'), findsOneWidget);
    });

    testWidgets('bei elf von zwoelf steht da „Noch 1 Schritt"', (tester) async {
      await zeige(tester, erledigt: alleZwoelf().take(11).toList());
      expect(find.text('Noch 1 Schritt'), findsOneWidget);
    });
  });

  group('Die Animation beim ersten Ausklappen', () {
    /// Waehrend der Staffelung liegt ueber jeder Kachel ein [Opacity]. Ist sie
    /// vorbei (oder lief sie nie), gibt es das Widget nicht.
    Finder verblassend(String id) => find.ancestor(
          of: find.byKey(ValueKey('starter_aufgabe_$id')),
          matching: find.byType(Opacity),
        );

    testWidgets('sie laeuft beim ersten Mal und merkt sich das', (tester) async {
      await zeige(tester, settle: false);
      // Bild 1: Dienst geladen. Bild 2: Gedaechtnis geladen, Animation an.
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        verblassend('km50'),
        findsOneWidget,
        reason: 'Die letzte Kachel des Bereichs blendet noch auf.',
      );
      await tester.pumpAndSettle();
      expect(verblassend('km50'), findsNothing);

      expect(StarterKartenGedaechtnis.animierteBereiche, contains('fahren'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList(StarterKartenGedaechtnis.kAnimiert),
        contains('fahren'),
      );
    });

    testWidgets('beim zweiten Mal nicht mehr', (tester) async {
      SharedPreferences.setMockInitialValues({
        'starter_aufgaben_erledigt_v1': jsonEncode(const <String>[]),
        StarterKartenGedaechtnis.kAnimiert: ['fahren'],
      });
      dienst.resetForTests();
      StarterKartenGedaechtnis.resetForTests();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StarterPaketKarte()),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(verblassend('km50'), findsNothing);
      expect(aufgabe('km50'), findsOneWidget);
    });

    testWidgets('jeder Bereich bekommt seine eigene, genau einmal',
        (tester) async {
      await zeige(tester);
      expect(StarterKartenGedaechtnis.animierteBereiche, contains('fahren'));
      expect(
        StarterKartenGedaechtnis.animierteBereiche.contains('community'),
        isFalse,
        reason: 'Was nie offen war, hat seine Animation noch vor sich.',
      );

      await tester.tap(bereich('community'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(verblassend('post'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(StarterKartenGedaechtnis.animierteBereiche, contains('community'));

      // Zu und wieder auf: keine zweite Vorstellung.
      await tester.tap(bereich('community'));
      await tester.pumpAndSettle();
      await tester.tap(bereich('community'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(verblassend('post'), findsNothing);
    });

    testWidgets('„Bewegung reduzieren" hebt sie ersatzlos auf', (tester) async {
      await zeige(tester, bewegungReduzieren: true, settle: false);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(verblassend('km50'), findsNothing);
      expect(aufgabe('km50'), findsOneWidget);
      expect(
        StarterKartenGedaechtnis.animierteBereiche,
        isEmpty,
        reason: 'Kein Vermerk: wer die Einstellung abschaltet, bekommt sie '
            'dann noch.',
      );
    });
  });

  group('Der Rahmen pro Aufgabe', () {
    testWidgets('der naechste Schritt traegt seine Beschreibung, der Rest '
        'nicht', (tester) async {
      await zeige(tester);
      final erste = StarterAufgabenService.aufgaben
          .firstWhere((a) => a.id == 'route');
      final zweite = StarterAufgabenService.aufgaben
          .firstWhere((a) => a.id == 'favorit');
      expect(find.text(erste.beschreibung), findsOneWidget);
      expect(
        find.text(zweite.beschreibung),
        findsNothing,
        reason: 'Zwoelf Beschreibungen untereinander waren 1870 Punkte hoch.',
      );
    });

    testWidgets('erledigte Aufgaben haben keinen Rahmen und fuehren nirgends '
        'hin', (tester) async {
      var tab = -1;
      await zeige(
        tester,
        erledigt: const ['route'],
        onTabChange: (i) => tab = i,
      );
      await tester.tap(aufgabe('route'));
      await tester.pump();
      expect(tab, -1);
      final semantik = tester.getSemantics(aufgabe('route'));
      expect(semantik.label, contains('erledigt'));
    });
  });
}
