import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/widgets/community/community_eckdaten_blatt.dart';

/// 2026-08-24 — Auftrag Vucko: „man soll auch community anpinnen koennen und
/// wenn man in der community oben klickt auf den namen wenn man drinnen ist,
/// soll man auch als normaler user in der gruppe die eckdaten wie mitglieder
/// usw sehen koennen aber man soll nichts aendern koennen das soll gelocked
/// sein".
///
/// GEMESSEN vor der Aenderung in `community_chat_detail_page.dart`:
/// - Zeile 1055-1073 (Titel der AppBar) und Zeile 1204-1224 (Kopfzeile
///   darunter) waren beide ein blosser `Row` aus `CommunityAvatar` und
///   `Text` — kein `onTap`, kein `InkWell`, kein `GestureDetector`.
/// - Der einzige Weg zu Sichtbarkeit, Schreibmodus, Bild und Beschreibung war
///   `CommunitySettingsPage`, und die zeigt fuer alle ausser dem Owner
///   `_buildNoAccess()`.
///
/// Ohne die Aenderung ist diese Datei doppelt rot: die Nachstellung findet
/// `_oeffneEckdaten` nicht in der Seite, und die Widget-Tests uebersetzen
/// nicht, weil `CommunityEckdatenBlatt` noch nicht existiert.
void main() {
  /// Kommentare zaehlen nicht mit: dieselbe Methode steht auch in der
  /// Begruendung darueber, und die soll den Zaehler nicht verfaelschen.
  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((zeile) {
        final t = zeile.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  group('Nachstellung: der Name oben war nicht antippbar', () {
    final quelle = ohneKommentare(
      File(
        'lib/presentation/pages/community_chat_detail_page.dart',
      ).readAsStringSync(),
    );

    test('beide Namen oben haengen an genau einer Methode', () {
      // Einmal die Definition, zweimal der Aufruf: AppBar-Titel und die
      // Kopfzeile direkt darunter. Vorher: null Treffer.
      expect(
        '_oeffneEckdaten'.allMatches(quelle).length,
        3,
        reason:
            'Erwartet: Definition + Tipp auf den AppBar-Titel + Tipp auf die '
            'Kopfzeile. Laeuft eine Stelle an der Methode vorbei, koennen die '
            'beiden Wege auseinanderlaufen.',
      );
    });

    test('die Entscheidung faellt in der benannten Funktion, nicht inline', () {
      expect(quelle.contains('communityKopfzeileZiel('), isTrue);
      expect(quelle.contains('CommunityEckdatenBlatt.zeigen('), isTrue);
    });

    test('das Blatt selbst kann gar nichts schreiben', () {
      final blatt = ohneKommentare(
        File(
          'lib/presentation/widgets/community/community_eckdaten_blatt.dart',
        ).readAsStringSync(),
      );
      // „Gelocked" heisst hier: die Nur-Lesen-Ansicht kennt keinen einzigen
      // schreibenden Dienst. Was es nicht aufruft, kann es nicht aendern.
      for (final schreibend in <String>[
        'setCommunityVisibility',
        'setOwnerOnlyMessages',
        'updateCommunityProfile',
        'setCommunityAvatarUrl',
        'setMemberRole',
        'removeMember',
        'deleteCommunity',
      ]) {
        expect(
          blatt.contains(schreibend),
          isFalse,
          reason: '$schreibend hat in einer Nur-Lesen-Ansicht nichts zu suchen.',
        );
      }
    });
  });

  group('Wohin ein Tipp auf den Namen fuehrt', () {
    test('Admin kommt ohne Umweg in die Einstellungen', () {
      expect(
        communityKopfzeileZiel(rolle: 'owner'),
        CommunityKopfzeileZiel.einstellungen,
        reason:
            'Vuckos Punkt 4: der Admin soll nicht erst durch eine '
            'Nur-Lesen-Ansicht hindurch.',
      );
    });

    test('Moderator und Mitglied sehen die Eckdaten', () {
      expect(
        communityKopfzeileZiel(rolle: 'moderator'),
        CommunityKopfzeileZiel.eckdaten,
      );
      expect(
        communityKopfzeileZiel(rolle: 'member'),
        CommunityKopfzeileZiel.eckdaten,
      );
    });

    test('unbekannte Rolle fuehrt in die Eckdaten, nicht in die Sperre', () {
      // Solange die Mitglieder noch laden, ist die Rolle null. Die
      // Einstellungs-Seite wuerde dann „Kein Zugriff" zeigen.
      expect(
        communityKopfzeileZiel(rolle: null),
        CommunityKopfzeileZiel.eckdaten,
      );
    });
  });

  group('Eckdaten-Blatt', () {
    Map<String, dynamic> community({
      bool oeffentlich = true,
      bool nurAdminsSchreiben = false,
      String? beschreibung = 'Wir fahren jeden Freitag.',
    }) {
      return <String, dynamic>{
        'id': 'c-1',
        'owner_id': 'u-1',
        'name': 'Nachtcruiser',
        'description': beschreibung,
        'is_public': oeffentlich,
        'owner_only_messages': nurAdminsSchreiben,
        'created_at': '2026-05-04T09:00:00Z',
        'member_count': 12,
        'owner_profile': {'id': 'u-1', 'username': 'vucko'},
      };
    }

    Future<void> pumpBlatt(
      WidgetTester tester, {
      required Map<String, dynamic> daten,
      String? rolle = 'member',
      List<String>? protokoll,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF151821),
            body: CommunityEckdatenBlatt(
              community: daten,
              rolle: rolle,
              onMitgliederAnzeigen: () => protokoll?.add('mitglieder'),
              onSchliessen: () => protokoll?.add('zu'),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('ein normales Mitglied sieht alle Eckdaten', (tester) async {
      await pumpBlatt(tester, daten: community(nurAdminsSchreiben: true));

      expect(find.text('Nachtcruiser'), findsOneWidget);
      expect(find.text('@vucko'), findsOneWidget);
      expect(find.text('12 Mitglieder'), findsOneWidget);
      expect(find.text('Gegründet am 04.05.2026'), findsOneWidget);
      expect(find.text('Wir fahren jeden Freitag.'), findsOneWidget);
      expect(find.text('Öffentlich'), findsOneWidget);
      expect(find.text('Du: User'), findsOneWidget);
      expect(
        find.textContaining(CommunityChatService.writeModeAdminsTitle),
        findsOneWidget,
      );
    });

    testWidgets('privat und „alle schreiben" stehen genauso drin', (
      tester,
    ) async {
      await pumpBlatt(tester, daten: community(oeffentlich: false));

      expect(find.text('Privat'), findsOneWidget);
      expect(
        find.textContaining(CommunityChatService.writeModeEveryoneTitle),
        findsOneWidget,
      );
    });

    testWidgets('nichts davon ist aenderbar', (tester) async {
      await pumpBlatt(tester, daten: community());

      // Das ist der Kern von „gelocked": kein Eingabefeld, kein Schalter,
      // kein Speichern. Nicht: alles grau.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Speichern'), findsNothing);
      expect(find.text('Bild ändern'), findsNothing);
      expect(find.text('Community löschen'), findsNothing);
    });

    testWidgets('der Schloss-Satz sagt, WER aendern darf', (tester) async {
      await pumpBlatt(tester, daten: community());

      // Nicht „gesperrt", sondern eine Auskunft: der Nutzer soll wissen, an
      // wen er sich wendet, statt sich ausgesperrt zu fuehlen.
      expect(find.textContaining('ändern kann sie nur er'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
    });

    testWidgets('ein Moderator bekommt seinen eigenen Satz', (tester) async {
      await pumpBlatt(tester, daten: community(), rolle: 'moderator');

      expect(find.text('Du: Moderator'), findsOneWidget);
      expect(
        find.textContaining('Als Moderator moderierst du'),
        findsOneWidget,
        reason:
            'Ein Moderator darf sehr wohl etwas (anheften, Mitglieder '
            'entfernen). Ihm „du kannst nichts" zu sagen waere falsch.',
      );
      // Aendern darf auch er hier nichts.
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('die Mitgliederliste bleibt fuer jeden offen', (tester) async {
      final protokoll = <String>[];
      await pumpBlatt(tester, daten: community(), protokoll: protokoll);

      await tester.tap(find.text('Mitglieder ansehen'));
      await tester.pump();

      expect(protokoll, ['mitglieder']);
    });

    testWidgets('es gibt immer einen sichtbaren Ausweg', (tester) async {
      final protokoll = <String>[];
      await pumpBlatt(tester, daten: community(), protokoll: protokoll);

      await tester.tap(find.text('Schließen'));
      await tester.pump();

      expect(protokoll, ['zu']);
    });

    testWidgets('ohne Beschreibung steht ein Satz statt einer Luecke', (
      tester,
    ) async {
      await pumpBlatt(tester, daten: community(beschreibung: null));

      expect(
        find.text('Diese Community hat noch keine Beschreibung.'),
        findsOneWidget,
      );
    });
  });
}
