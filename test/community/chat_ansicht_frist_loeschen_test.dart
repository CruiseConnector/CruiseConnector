import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';

/// 2026-08-24 (Auftrag Vucko):
///   „man soll seine Nachrichten bis zu 6h nach abschicken bearbeiten koennen
///    danach gehts nicht mehr [...] und nicht durch zeit zurueckstellen oder
///    datum zurueckstellen irgendwie manipuliert werden kann"
///   „auch fuer alle loeschen koennen oder nur fuer sich selber wie bei
///    whatsapp"
///   „man soll sehen wer dazu gekommen ist und wer aus der community gegangen
///    ist danach"
///   „man soll die chat art optimieren koennen"
///
/// DURCHGESETZT wird die Frist in der Datenbank (Trigger
/// `trg_wacht_ueber_community_nachricht`, Migration 20260824160000). Dieser
/// Test bewacht die CLIENT-Seite: dass die ANZEIGE gegen die Serverzeit
/// rechnet und nicht gegen die Uhr des Geraets, dass ein „nur fuer mich"
/// wirklich verschwindet, dass eine fuer alle geloeschte Nachricht als Spur
/// stehen bleibt und dass die Zu- und Abgaenge den Chat nicht zumuellen.
///
/// Ohne die Aenderung ist die ganze Datei rot: es gab weder
/// `verbleibendeBearbeitungszeit` noch `Serverzeit` noch
/// `CommunityChatTimeline`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> nachricht({
    required String id,
    required String userId,
    required String erstellt,
    String body = 'Text',
    bool geloescht = false,
    String? angepinntAm,
  }) => <String, dynamic>{
    'id': id,
    'community_id': 'c1',
    'user_id': userId,
    'body': geloescht ? '' : body,
    'created_at': erstellt,
    'deleted_at': geloescht ? erstellt : null,
    'pinned_at': angepinntAm,
    if (geloescht) '_geloescht': true,
  };

  Map<String, dynamic> verlauf({
    required String id,
    required String userId,
    required String art,
    required String am,
    String? name,
  }) => <String, dynamic>{
    'id': id,
    'community_id': 'c1',
    'user_id': userId,
    'art': art,
    'am': am,
    'profiles': {'id': userId, 'username': name ?? userId},
  };

  tearDown(() {
    Serverzeit.resetForTests();
    CommunityChatService.resetChatDarstellungFuerTests();
    NutzerPrefsSchluessel.nutzerIdFuerTests = null;
  });

  group('Die Frist rechnet gegen die Serveruhr', () {
    test('ein VORgestelltes Handy nimmt die Bearbeitung nicht weg', () {
      // Nachricht ist echt vor 3 Stunden entstanden (Serverzeit setzt
      // created_at, das kann der Client nicht beeinflussen).
      final erstellt = DateTime.utc(2026, 8, 24, 9);
      final serverJetzt = DateTime.utc(2026, 8, 24, 12);
      // Das Handy steht drei Stunden vor. Wer gegen DateTime.now() rechnet,
      // kommt auf 6 Stunden Abstand und sagt „abgelaufen".
      final geraetJetzt = DateTime.utc(2026, 8, 24, 15);

      Serverzeit.geraetezeitFuerTests = () => geraetJetzt;
      Serverzeit.merkeServerzeit(serverJetzt);

      expect(Serverzeit.jetzt, serverJetzt);

      final rest = CommunityChatService.verbleibendeBearbeitungszeit(
        erstelltAm: erstellt,
        serverJetzt: Serverzeit.jetzt,
      );
      expect(rest, const Duration(hours: 3));
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: true,
          istGeloescht: false,
          istUnterwegs: false,
          verbleibend: rest,
        ),
        isTrue,
        reason:
            'Das Handy geht falsch, die Nachricht ist drei Stunden alt. '
            'Bearbeiten muss moeglich bleiben.',
      );

      // Gegenprobe: die Geraeteuhr allein haette „abgelaufen" gesagt.
      final restNachGeraet = CommunityChatService.verbleibendeBearbeitungszeit(
        erstelltAm: erstellt,
        serverJetzt: geraetJetzt,
      );
      expect(restNachGeraet, Duration.zero);
    });

    test('ein ZURUECKgestelltes Handy erschleicht keine Verlaengerung', () {
      // Acht Stunden alt: die Frist ist echt vorbei.
      final erstellt = DateTime.utc(2026, 8, 24, 4);
      final serverJetzt = DateTime.utc(2026, 8, 24, 12);
      // Das Handy behauptet, es sei erst 5 Uhr.
      final geraetJetzt = DateTime.utc(2026, 8, 24, 5);

      Serverzeit.geraetezeitFuerTests = () => geraetJetzt;
      Serverzeit.merkeServerzeit(serverJetzt);

      final rest = CommunityChatService.verbleibendeBearbeitungszeit(
        erstelltAm: erstellt,
        serverJetzt: Serverzeit.jetzt,
      );
      expect(rest, Duration.zero);
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: true,
          istGeloescht: false,
          istUnterwegs: false,
          verbleibend: rest,
        ),
        isFalse,
      );

      // Gegenprobe: gegen die Geraeteuhr waeren es noch fuenf Stunden.
      expect(
        CommunityChatService.verbleibendeBearbeitungszeit(
          erstelltAm: erstellt,
          serverJetzt: geraetJetzt,
        ),
        const Duration(hours: 5),
      );
    });

    test('ohne gemessene Serverzeit wird nichts behauptet, aber angeboten', () {
      expect(Serverzeit.istAbgeglichen, isFalse);
      expect(Serverzeit.jetzt, isNull);

      final rest = CommunityChatService.verbleibendeBearbeitungszeit(
        erstelltAm: DateTime.utc(2026, 8, 24, 9),
        serverJetzt: Serverzeit.jetzt,
      );
      expect(rest, isNull, reason: 'null heisst „unbekannt", nicht „0".');
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: true,
          istGeloescht: false,
          istUnterwegs: false,
          verbleibend: rest,
        ),
        isTrue,
        reason:
            'Der Eintrag bleibt stehen, der Server lehnt notfalls ab. Der '
            'umgekehrte Fehler waere schlimmer.',
      );
    });

    test('fremde, geloeschte und noch nicht gesendete sind tabu', () {
      const voll = Duration(hours: 5);
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: false,
          istGeloescht: false,
          istUnterwegs: false,
          verbleibend: voll,
        ),
        isFalse,
      );
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: true,
          istGeloescht: true,
          istUnterwegs: false,
          verbleibend: voll,
        ),
        isFalse,
      );
      expect(
        CommunityChatService.darfBearbeiten(
          istEigene: true,
          istGeloescht: false,
          istUnterwegs: true,
          verbleibend: voll,
        ),
        isFalse,
      );
    });

    test('der Abgleich merkt sich den Versatz', () async {
      final geraetJetzt = DateTime.utc(2026, 8, 24, 15);
      Serverzeit.geraetezeitFuerTests = () => geraetJetzt;
      Serverzeit.abfrageFuerTests = () async => DateTime.utc(2026, 8, 24, 12);

      expect(await Serverzeit.abgleichen(), isTrue);
      expect(Serverzeit.istAbgeglichen, isTrue);
      expect(Serverzeit.jetzt, DateTime.utc(2026, 8, 24, 12));
    });

    test('scheitert der Abgleich, bleibt die Zeit unbekannt', () async {
      Serverzeit.abfrageFuerTests = () async => null;
      expect(await Serverzeit.abgleichen(), isFalse);
      expect(Serverzeit.jetzt, isNull);
    });

    test('die Fristanzeige ist deutsch und ohne Gedankenstriche', () {
      expect(
        CommunityChatService.fristText(
          const Duration(hours: 4, minutes: 12),
        ),
        'Noch 4 Std. 12 Min. bearbeitbar',
      );
      expect(
        CommunityChatService.fristText(const Duration(hours: 2)),
        'Noch 2 Std. bearbeitbar',
      );
      expect(
        CommunityChatService.fristText(const Duration(minutes: 7)),
        'Noch 7 Min. bearbeitbar',
      );
      expect(
        CommunityChatService.fristText(const Duration(seconds: 40)),
        'Noch 40 Sek. bearbeitbar',
      );
      expect(
        CommunityChatService.fristText(Duration.zero),
        'Frist abgelaufen',
      );
      expect(
        CommunityChatService.bearbeitungsfrist,
        const Duration(hours: 6),
        reason: 'Kopie der Frist aus dem Trigger. Sechs Stunden, wie gesagt.',
      );
    });
  });

  group('Loeschen: fuer alle bleibt eine Spur, nur fuer mich nicht', () {
    test('fuer alle geloescht steht als Grabstein in der Zeitleiste', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(
            id: 'm1',
            userId: 'u1',
            erstellt: '2026-08-24T09:00:00Z',
            geloescht: true,
          ),
          nachricht(id: 'm2', userId: 'u2', erstellt: '2026-08-24T09:05:00Z'),
        ],
        verlauf: const [],
        ausgeblendet: const <String>{},
        angepinntZuerst: false,
      );
      expect(zeilen.map((z) => z.art).toList(), [
        ChatZeileArt.geloescht,
        ChatZeileArt.nachricht,
      ]);
      expect(
        zeilen.first.nachricht?['body'],
        '',
        reason:
            'Der Text einer fuer alle geloeschten Nachricht darf gar nicht '
            'erst auf dem Geraet liegen.',
      );
    });

    test('nur fuer mich geloescht faellt restlos weg', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T09:00:00Z'),
          nachricht(id: 'm2', userId: 'u2', erstellt: '2026-08-24T09:05:00Z'),
        ],
        verlauf: const [],
        ausgeblendet: const {'m1'},
        angepinntZuerst: false,
      );
      expect(zeilen.length, 1);
      expect(zeilen.single.nachricht?['id'], 'm2');
    });

    test('ausgeblendet schlaegt Grabstein: auch der verschwindet', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(
            id: 'm1',
            userId: 'u1',
            erstellt: '2026-08-24T09:00:00Z',
            geloescht: true,
          ),
        ],
        verlauf: const [],
        ausgeblendet: const {'m1'},
        angepinntZuerst: false,
      );
      expect(zeilen, isEmpty);
    });

    test('die Grabstein-Abfrage fragt den Text gar nicht erst ab', () {
      final quelle = File(
        'lib/data/services/community_chat_service.dart',
      ).readAsStringSync();
      final von = quelle.indexOf(
        'static Future<List<Map<String, dynamic>>> _fetchGeloeschteHuellen(',
      );
      expect(von, isNot(-1));
      final bis = quelle.indexOf('\n  static ', von + 40);
      final block = quelle.substring(von, bis == -1 ? quelle.length : bis);
      // Nur die Spaltenliste der Abfrage betrachten, nicht den ganzen Block:
      // weiter unten steht absichtlich `'body': ''`, damit die Oberflaeche
      // einen leeren Text vorfindet statt `null`.
      final auswahl = block.substring(
        block.indexOf('.select('),
        block.indexOf(".eq('community_id'"),
      );
      expect(
        auswahl.contains("'id, community_id, user_id, created_at, deleted_at, "),
        isTrue,
      );
      expect(
        RegExp(r'\bbody\b').hasMatch(auswahl),
        isFalse,
        reason:
            '`deleted_at` zu setzen loescht den Text NICHT. Wer ihn hier mit '
            'abfragt, legt jede geloeschte Nachricht wieder aufs Geraet.',
      );
    });
  });

  group('Wer kam und wer ging', () {
    test('zehn Beitritte am Stueck werden EINE Zeile', () {
      final eintraege = [
        for (var i = 0; i < 10; i++)
          verlauf(
            id: 'v$i',
            userId: 'u$i',
            art: 'beitritt',
            am: '2026-08-24T08:0${i}:00Z',
            name: 'Person$i',
          ),
      ];
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T09:00:00Z'),
        ],
        verlauf: eintraege,
        ausgeblendet: const <String>{},
        angepinntZuerst: false,
      );
      expect(zeilen.length, 2, reason: 'Eine Verlaufszeile, eine Nachricht.');
      expect(zeilen.first.art, ChatZeileArt.verlauf);
      expect(zeilen.first.verlauf.length, 10);
      expect(
        CommunityChatTimeline.verlaufText(zeilen.first.verlauf),
        'Person0, Person1, Person2 und 7 weitere sind beigetreten.',
      );
    });

    test('eine Nachricht dazwischen trennt die Zeilen', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T08:30:00Z'),
        ],
        verlauf: [
          verlauf(
            id: 'v1',
            userId: 'u1',
            art: 'beitritt',
            am: '2026-08-24T08:00:00Z',
            name: 'Anna',
          ),
          verlauf(
            id: 'v2',
            userId: 'u2',
            art: 'beitritt',
            am: '2026-08-24T09:00:00Z',
            name: 'Ben',
          ),
        ],
        ausgeblendet: const <String>{},
        angepinntZuerst: false,
      );
      expect(zeilen.map((z) => z.art).toList(), [
        ChatZeileArt.verlauf,
        ChatZeileArt.nachricht,
        ChatZeileArt.verlauf,
      ]);
    });

    test('Beitritt und Austritt landen nie im selben Satz', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: const [],
        verlauf: [
          verlauf(
            id: 'v1',
            userId: 'u1',
            art: 'beitritt',
            am: '2026-08-24T08:00:00Z',
            name: 'Anna',
          ),
          verlauf(
            id: 'v2',
            userId: 'u2',
            art: 'austritt',
            am: '2026-08-24T08:01:00Z',
            name: 'Ben',
          ),
        ],
        ausgeblendet: const <String>{},
        angepinntZuerst: false,
      );
      expect(zeilen.length, 2);
      expect(
        CommunityChatTimeline.verlaufText(zeilen[0].verlauf),
        'Anna ist beigetreten.',
      );
      expect(
        CommunityChatTimeline.verlaufText(zeilen[1].verlauf),
        'Ben hat die Community verlassen.',
      );
    });

    test('die Saetze stimmen in Ein- und Mehrzahl', () {
      String text(int anzahl, String art) => CommunityChatTimeline.verlaufText([
        for (var i = 0; i < anzahl; i++)
          verlauf(
            id: 'v$i',
            userId: 'u$i',
            art: art,
            am: '2026-08-24T08:00:00Z',
            name: ['Anna', 'Ben', 'Cem', 'Dana'][i],
          ),
      ]);

      expect(text(1, 'beitritt'), 'Anna ist beigetreten.');
      expect(text(2, 'beitritt'), 'Anna und Ben sind beigetreten.');
      expect(text(3, 'beitritt'), 'Anna, Ben und Cem sind beigetreten.');
      expect(
        text(4, 'beitritt'),
        'Anna, Ben, Cem und 1 weitere sind beigetreten.',
      );
      expect(text(1, 'entfernt'), 'Anna wurde entfernt.');
      expect(text(2, 'entfernt'), 'Anna und Ben wurden entfernt.');
      expect(text(2, 'austritt'), 'Anna und Ben haben die Community verlassen.');
    });
  });

  group('Die beiden Chat-Arten', () {
    test('Beitragsansicht zieht Angepinntes nach oben', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T09:00:00Z'),
          nachricht(
            id: 'm2',
            userId: 'u2',
            erstellt: '2026-08-24T08:00:00Z',
            angepinntAm: '2026-08-24T10:00:00Z',
          ),
        ],
        verlauf: const [],
        ausgeblendet: const <String>{},
        angepinntZuerst: true,
      );
      expect(zeilen.map((z) => z.nachricht?['id']).toList(), ['m2', 'm1']);
      expect(zeilen.first.angepinnt, isTrue);
    });

    test('Nachrichten-Ansicht bleibt streng chronologisch', () {
      final zeilen = CommunityChatTimeline.baue(
        nachrichten: [
          nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T09:00:00Z'),
          nachricht(
            id: 'm2',
            userId: 'u2',
            erstellt: '2026-08-24T08:00:00Z',
            angepinntAm: '2026-08-24T10:00:00Z',
          ),
        ],
        verlauf: const [],
        ausgeblendet: const <String>{},
        angepinntZuerst: false,
      );
      expect(
        zeilen.map((z) => z.nachricht?['id']).toList(),
        ['m2', 'm1'],
        reason:
            'Chronologisch: m2 ist aelter. Das Angepinnte steht in dieser '
            'Ansicht im Band ueber der Liste, nicht mitten im Verlauf.',
      );
      // Angepinnt bleibt erkennbar, es wird nur nicht umsortiert.
      expect(zeilen.first.angepinnt, isTrue);
    });

    test('beide Arten bekommen dieselben Zeilen, nur anders sortiert', () {
      final nachrichten = [
        nachricht(id: 'm1', userId: 'u1', erstellt: '2026-08-24T09:00:00Z'),
        nachricht(
          id: 'm2',
          userId: 'u2',
          erstellt: '2026-08-24T08:00:00Z',
          angepinntAm: '2026-08-24T10:00:00Z',
        ),
        nachricht(
          id: 'm3',
          userId: 'u3',
          erstellt: '2026-08-24T07:00:00Z',
          geloescht: true,
        ),
      ];
      final eintraege = [
        verlauf(
          id: 'v1',
          userId: 'u9',
          art: 'beitritt',
          am: '2026-08-24T06:00:00Z',
          name: 'Anna',
        ),
      ];
      Set<String?> kennungen(bool angepinntZuerst) => CommunityChatTimeline.baue(
        nachrichten: nachrichten,
        verlauf: eintraege,
        ausgeblendet: const <String>{},
        angepinntZuerst: angepinntZuerst,
      ).map((z) => z.id).toSet();

      expect(kennungen(true), kennungen(false));
      expect(kennungen(true).length, 4);
    });

    test('die Wahl ueberlebt den Neustart und haengt am Konto', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-a';

      ChatDarstellung? amKonto;
      CommunityChatService.chatDarstellungSchreiberFuerTests = (art) async {
        amKonto = art;
      };

      expect(await CommunityChatService.chatDarstellungVomGeraet(), isNull);

      await CommunityChatService.merkeChatDarstellung(
        ChatDarstellung.nachrichten,
      );

      // Neustart = neu vom Geraet lesen.
      expect(
        await CommunityChatService.chatDarstellungVomGeraet(),
        ChatDarstellung.nachrichten,
      );
      expect(
        amKonto,
        ChatDarstellung.nachrichten,
        reason:
            'Am Konto, nicht nur am Geraet — sonst kommt die Wahl nicht aufs '
            'naechste Handy mit.',
      );

      // Ein zweites Konto auf demselben Handy erbt die Wahl NICHT.
      NutzerPrefsSchluessel.nutzerIdFuerTests = () => 'konto-b';
      expect(await CommunityChatService.chatDarstellungVomGeraet(), isNull);
    });

    test('die Datenbank kennt genau diese beiden Werte', () {
      expect(ChatDarstellung.standard.wert, 'standard');
      expect(ChatDarstellung.nachrichten.wert, 'nachrichten');
      expect(ChatDarstellung.ausWert('nachrichten'), ChatDarstellung.nachrichten);
      expect(ChatDarstellung.ausWert(null), isNull);
      expect(
        ChatDarstellung.ausWert('irgendwas'),
        isNull,
        reason:
            'Ein unbekannter Wert darf nicht stillschweigend zu einer Ansicht '
            'werden — der CHECK profiles_chat_darstellung_chk laesst ihn '
            'ohnehin nicht zu.',
      );
    });
  });
}
