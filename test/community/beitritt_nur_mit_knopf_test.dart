import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/presentation/widgets/community/community_vorschau_blatt.dart';

/// 2026-08-24 — Auftrag Vucko vom 24.08., dringender Teil.
///
/// Vucko: „zudem moechte ich einen beitret button weil man wenn man auf eine
/// community klickt, dass man direkt beitritt ohne beitrettbutton -> fixxen
/// das muss noch umgehend gefixxt werden".
///
/// Gemessen vor der Aenderung in `community_chats_tab.dart`:
/// - Zeile 374: `onTap: () => _joinCommunity(community)` fuer jede Community
///   der Entdecken-Liste,
/// - Zeile 577: dieses `onTap` lag als InkWell ueber der KOMPLETTEN Kachel.
///
/// Ein Tipp auf Bild, Name oder Beschreibung machte einen also sofort zum
/// Mitglied. Dieselbe Falle stand in der Code-Suche (Zeile 435).
///
/// Ohne die Aenderung ist diese Datei doppelt rot: die Nachstellung findet
/// die beiden `onTap`-Zeilen, und die Widget-Tests uebersetzen nicht, weil
/// `CommunityVorschauBlatt` noch nicht existiert.
void main() {
  group('Nachstellung: der Tipp auf die Kachel trat sofort bei', () {
    final quelle = File(
      'lib/presentation/pages/community_chats_tab.dart',
    ).readAsStringSync();

    test('kein einziges onTap loest einen Beitritt aus', () {
      // Alles, was hinter einem `onTap:` steht (grosszuegige 200 Zeichen,
      // damit auch mehrzeilige Aufrufe erfasst werden), darf keinen
      // Beitritt anstossen.
      final verdaechtig = <String>[];
      for (final treffer in 'onTap:'.allMatches(quelle)) {
        final ende = (treffer.end + 200).clamp(0, quelle.length);
        final abschnitt = quelle.substring(treffer.end, ende);
        // Der naechste `onTap:` beendet den Abschnitt, sonst schlaegt ein
        // harmloser Nachbar durch.
        final naechster = abschnitt.indexOf('onTap:');
        final block = naechster == -1
            ? abschnitt
            : abschnitt.substring(0, naechster);
        if (block.contains('_join')) verdaechtig.add(block.trim());
      }
      expect(
        verdaechtig,
        isEmpty,
        reason:
            'Ein Tipp auf die Kachel darf NIE beitreten. Gefunden:\n'
            '${verdaechtig.join('\n---\n')}',
      );
    });

    test('alle drei Kacheln gehen ueber dieselbe Entscheidung', () {
      // Einmal die Definition, dreimal der Aufruf: Meine Communities,
      // Oeffentliche Communities, Treffer der Code-Suche.
      expect('_kachelGetippt('.allMatches(quelle).length, 4);
      expect(quelle.contains('communityKachelZiel('), isTrue);
    });
  });

  group('Die Entscheidung selbst', () {
    test('kein Mitglied fuehrt in die Vorschau, nicht in den Beitritt', () {
      expect(
        communityKachelZiel(istMitglied: false),
        CommunityKachelZiel.vorschau,
      );
    });

    test('Mitglied fuehrt in den Chat', () {
      expect(communityKachelZiel(istMitglied: true), CommunityKachelZiel.chat);
    });
  });

  group('Vorschau-Blatt', () {
    // Fester Bezugspunkt, damit „Vor kurzem erstellt" nicht von der Uhr des
    // Rechners abhaengt.
    final jetzt = DateTime.utc(2026, 8, 24, 12);

    Map<String, dynamic> community({
      bool oeffentlich = true,
      int mitglieder = 3,
      String? erstellt = '2026-08-20T12:00:00Z',
      String? beschreibung = 'Alles rund um alte Opel.',
    }) {
      return <String, dynamic>{
        'id': 'c-1',
        'owner_id': 'u-1',
        'name': 'Opel-Crew',
        'description': beschreibung,
        'is_public': oeffentlich,
        'created_at': erstellt,
        'member_count': mitglieder,
        'owner_profile': {'id': 'u-1', 'username': 'vucko'},
      };
    }

    Future<void> pumpBlatt(
      WidgetTester tester, {
      required Map<String, dynamic> daten,
      required Future<CommunityBeitrittsErgebnis> Function() onBeitreten,
      required List<CommunityBeitrittsErgebnis> fertig,
      bool istMitglied = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF151821),
            body: SingleChildScrollView(
              child: CommunityVorschauBlatt(
                community: daten,
                istMitglied: istMitglied,
                onBeitreten: onBeitreten,
                onFertig: fertig.add,
                jetzt: jetzt,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('zeigt Name, Besitzer, Mitgliederzahl und Gruendungsdatum', (
      tester,
    ) async {
      await pumpBlatt(
        tester,
        daten: community(),
        onBeitreten: () async =>
            const CommunityBeitrittsErgebnis(CommunityBeitrittAusgang.fehler),
        fertig: [],
      );

      expect(find.text('Opel-Crew'), findsOneWidget);
      expect(find.text('@vucko'), findsOneWidget);
      expect(find.text('3 Mitglieder'), findsOneWidget);
      expect(find.text('Gegründet am 20.08.2026'), findsOneWidget);
      expect(find.text('Vor kurzem erstellt'), findsOneWidget);
      expect(find.text('Beitreten'), findsOneWidget);
    });

    testWidgets('eine alte Community traegt kein „Vor kurzem erstellt"', (
      tester,
    ) async {
      await pumpBlatt(
        tester,
        daten: community(erstellt: '2026-07-01T12:00:00Z'),
        onBeitreten: () async =>
            const CommunityBeitrittsErgebnis(CommunityBeitrittAusgang.fehler),
        fertig: [],
      );

      expect(find.text('Vor kurzem erstellt'), findsNothing);
      expect(find.text('Gegründet am 01.07.2026'), findsOneWidget);
    });

    testWidgets('ein Tipp auf Name, Bild oder Text tritt NICHT bei', (
      tester,
    ) async {
      var aufrufe = 0;
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(),
        onBeitreten: () async {
          aufrufe++;
          return const CommunityBeitrittsErgebnis(
            CommunityBeitrittAusgang.beigetreten,
            communityId: 'c-1',
          );
        },
        fertig: fertig,
      );

      await tester.tap(find.text('Opel-Crew'));
      await tester.tap(find.text('Alles rund um alte Opel.'));
      await tester.tap(find.text('3 Mitglieder'));
      await tester.tap(find.text('@vucko'));
      await tester.pumpAndSettle();

      expect(aufrufe, 0, reason: 'Nur der Knopf darf beitreten.');
      expect(fertig, isEmpty);
    });

    testWidgets('der Knopf tritt bei und meldet die Community zurueck', (
      tester,
    ) async {
      var aufrufe = 0;
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(),
        onBeitreten: () async {
          aufrufe++;
          return const CommunityBeitrittsErgebnis(
            CommunityBeitrittAusgang.beigetreten,
            communityId: 'c-1',
          );
        },
        fertig: fertig,
      );

      await tester.tap(find.text('Beitreten'));
      await tester.pumpAndSettle();

      expect(aufrufe, 1);
      expect(fertig.length, 1);
      expect(fertig.single.communityId, 'c-1');
      expect(fertig.single.oeffnetChat, isTrue);
    });

    testWidgets('die Mitgliederzahl steigt sofort um eins', (tester) async {
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(mitglieder: 3),
        onBeitreten: () async => const CommunityBeitrittsErgebnis(
          CommunityBeitrittAusgang.beigetreten,
          communityId: 'c-1',
        ),
        fertig: fertig,
      );

      expect(find.text('3 Mitglieder'), findsOneWidget);
      await tester.tap(find.text('Beitreten'));
      await tester.pumpAndSettle();

      expect(find.text('4 Mitglieder'), findsOneWidget);
      expect(find.text('3 Mitglieder'), findsNothing);
      expect(find.text('Chat öffnen'), findsOneWidget);
    });

    testWidgets('zweimal tippen tritt trotzdem nur einmal bei', (tester) async {
      var aufrufe = 0;
      final tor = Completer<CommunityBeitrittsErgebnis>();
      await pumpBlatt(
        tester,
        daten: community(),
        onBeitreten: () {
          aufrufe++;
          return tor.future;
        },
        fertig: [],
      );

      await tester.tap(find.text('Beitreten'));
      await tester.pump();
      // Waehrend der Beitritt laeuft, ist der Knopf gesperrt.
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();

      expect(aufrufe, 1);

      tor.complete(
        const CommunityBeitrittsErgebnis(
          CommunityBeitrittAusgang.beigetreten,
          communityId: 'c-1',
        ),
      );
      await tester.pumpAndSettle();
      expect(aufrufe, 1);
    });

    testWidgets('privat: der Knopf heisst „Beitritt anfragen"', (tester) async {
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(oeffentlich: false),
        onBeitreten: () async => const CommunityBeitrittsErgebnis(
          CommunityBeitrittAusgang.angefragt,
          communityId: 'c-1',
          meldung: '„Opel-Crew" ist privat. Deine Anfrage liegt beim Admin.',
        ),
        fertig: fertig,
      );

      expect(find.text('Beitritt anfragen'), findsOneWidget);
      expect(find.text('Beitreten'), findsNothing);
      expect(
        find.text('Privat. Der Admin muss deine Anfrage annehmen.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Beitritt anfragen'));
      await tester.pumpAndSettle();

      expect(
        find.text('„Opel-Crew" ist privat. Deine Anfrage liegt beim Admin.'),
        findsOneWidget,
      );
      expect(find.text('Anfrage liegt beim Admin'), findsOneWidget);
      expect(
        fertig,
        isEmpty,
        reason: 'Eine Anfrage macht noch kein Mitglied, der Chat bleibt zu.',
      );
    });

    testWidgets('geloeschte Community: der Grund steht im Blatt', (
      tester,
    ) async {
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(),
        onBeitreten: () async => CommunityBeitrittsErgebnis(
          CommunityBeitrittAusgang.fehler,
          meldung: beitrittsFehlerText(
            'PostgrestException: insert violates foreign key constraint',
          ),
        ),
        fertig: fertig,
      );

      await tester.tap(find.text('Beitreten'));
      await tester.pumpAndSettle();

      expect(find.text('Diese Community gibt es nicht mehr.'), findsOneWidget);
      expect(fertig, isEmpty);
      // Nach einem Fehler darf man es erneut versuchen.
      expect(find.text('Beitreten'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('schon Mitglied: der Knopf oeffnet nur noch den Chat', (
      tester,
    ) async {
      var aufrufe = 0;
      final fertig = <CommunityBeitrittsErgebnis>[];
      await pumpBlatt(
        tester,
        daten: community(),
        istMitglied: true,
        onBeitreten: () async {
          aufrufe++;
          return const CommunityBeitrittsErgebnis(
            CommunityBeitrittAusgang.beigetreten,
          );
        },
        fertig: fertig,
      );

      expect(find.text('Chat öffnen'), findsOneWidget);
      await tester.tap(find.text('Chat öffnen'));
      await tester.pumpAndSettle();

      expect(aufrufe, 0, reason: 'Kein zweiter Beitritt.');
      expect(fertig.single.oeffnetChat, isTrue);
      expect(find.text('3 Mitglieder'), findsOneWidget);
    });
  });

  group('Fehlertexte beim Beitreten', () {
    test('geloeschte Community', () {
      expect(
        beitrittsFehlerText('violates foreign key constraint "fk_community"'),
        'Diese Community gibt es nicht mehr.',
      );
    });

    test('kein Netz', () {
      expect(
        beitrittsFehlerText('SocketException: Failed host lookup: supabase.co'),
        'Keine Verbindung. Sobald du wieder Netz hast, klappt der Beitritt.',
      );
    });

    test('privat: der Satz des Dienstes bleibt stehen', () {
      const satz =
          'Diese Community ist privat. Nutze den Invite-Code vom Leader.';
      expect(beitrittsFehlerText(satz), satz);
    });

    test('Datenbankrauschen wird nicht durchgereicht', () {
      final text = beitrittsFehlerText(
        'PostgrestException(message: new row violates row-level security policy)',
      );
      expect(text.toLowerCase().contains('policy'), isFalse);
      expect(
        text,
        'Beitreten gerade nicht möglich. Versuch es gleich noch einmal.',
      );
    });
  });
}
