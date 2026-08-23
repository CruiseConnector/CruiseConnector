import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_neuigkeit_service.dart';

/// 2026-08-24 — Aufgabe 1.1 aus dem Auftrag vom 23.08.
///
/// Vucko, Aufnahme 1: „dass da halt einfach so ein kleiner Punkt ist, im Sinne
/// von, wie in den ganzen Apps halt eine Benachrichtigung aussieht" …
/// „wenn man auf das Community draufdrückt, dass man dann oben entweder im
/// Feed oder im Entdecker oder bei den Gruppenfahrten oder in der Community
/// sieht: okay, ja, da sind neue Sachen passiert" … „Wenn man in der Community
/// draufdrückt, dann halt das nochmal benachrichtigungsmäßig — wie, in welcher
/// Community das jetzt genau war."
///
/// Bewacht werden die vier Akzeptanzkriterien, soweit sie ohne zwei Konten und
/// ohne Gerät prüfbar sind:
///   1. Etwas Neues in einem Unterbereich -> Punkt am Reiter UND oben.
///   2. Feed öffnen -> nur der Feed-Punkt geht aus, die anderen bleiben.
///   3. Alle Unterbereiche gelesen -> auch der Punkt oben geht aus.
///   4. Der Lesestand liegt serverseitig, nicht in SharedPreferences.
void main() {
  Map<String, dynamic> antwort({
    bool feed = false,
    bool gruppen = false,
    bool chats = false,
    bool entdecken = false,
    Map<String, bool> communities = const <String, bool>{},
  }) {
    return <String, dynamic>{
      'punkt': feed || gruppen || chats || entdecken,
      'reiter': <String, dynamic>{
        'feed': {'neu': feed, 'anzahl': feed ? 3 : 0},
        'gruppen': {'neu': gruppen, 'anzahl': gruppen ? 1 : 0},
        'chats': {'neu': chats, 'anzahl': chats ? 5 : 0},
        'entdecken': {'neu': entdecken, 'anzahl': entdecken ? 2 : 0},
      },
      'communities': communities.map(
        (id, neu) => MapEntry(id, {'neu': neu, 'anzahl': neu ? 4 : 0}),
      ),
      'stand': '2026-08-24T10:20:00+00:00',
    };
  }

  setUp(() {
    CommunityNeuigkeitService.instance.zuruecksetzenFuerTest();
  });

  group('1.1 — Ebene 1 wird berechnet, nicht gespeichert', () {
    test(
      'Akzeptanzkriterium 1: eine neue Gruppe setzt den Reiter-Punkt UND '
      'den Punkt oben',
      () {
        final dienst = CommunityNeuigkeitService.instance;
        dienst.standAusJsonFuerTest(
          antwort(gruppen: true, communities: {'c1': true}),
        );
        expect(dienst.stand.value.fuerReiter(CommunityBereich.gruppen).neu,
            isTrue);
        expect(dienst.stand.value.fuerCommunity('c1').neu, isTrue);
        expect(dienst.stand.value.punkt, isTrue);
        expect(dienst.hatNeues.value, isTrue);
      },
    );

    test('nichts neu heißt kein Punkt, auch nicht oben', () {
      final dienst = CommunityNeuigkeitService.instance;
      dienst.standAusJsonFuerTest(antwort());
      expect(dienst.stand.value.punkt, isFalse);
      expect(dienst.hatNeues.value, isFalse);
    });

    test(
      'Akzeptanzkriterium 3: sind alle vier Reiter gelesen, geht der Punkt '
      'oben von selbst aus',
      () {
        final dienst = CommunityNeuigkeitService.instance;
        dienst.standAusJsonFuerTest(
          antwort(feed: true, gruppen: true, chats: true, entdecken: true),
        );
        expect(dienst.stand.value.punkt, isTrue);

        var stand = dienst.stand.value;
        for (final bereich in [
          CommunityBereich.feed,
          CommunityBereich.gruppen,
          CommunityBereich.chats,
          CommunityBereich.entdecken,
        ]) {
          stand = stand.ohneReiter(bereich);
        }
        expect(stand.punkt, isFalse);
      },
    );
  });

  group('1.1 — Ebene 2: genau der geöffnete Reiter geht aus', () {
    test(
      'Akzeptanzkriterium 2: Feed öffnen löscht NUR den Feed-Punkt',
      () {
        final voll = CommunityNeuigkeitService.instance;
        voll.standAusJsonFuerTest(
          antwort(feed: true, gruppen: true, entdecken: true),
        );
        final nachher = voll.stand.value.ohneReiter(CommunityBereich.feed);

        expect(nachher.fuerReiter(CommunityBereich.feed).neu, isFalse);
        expect(nachher.fuerReiter(CommunityBereich.gruppen).neu, isTrue);
        expect(nachher.fuerReiter(CommunityBereich.entdecken).neu, isTrue);
        // Und oben bleibt der Punkt, weil noch zwei Reiter leuchten.
        expect(nachher.punkt, isTrue);
      },
    );

    test(
      'der Chats-Reiter bleibt an, solange eine einzelne Community neu ist '
      '(WhatsApp-Verhalten)',
      () {
        final dienst = CommunityNeuigkeitService.instance;
        dienst.standAusJsonFuerTest(
          antwort(chats: true, communities: {'c1': true}),
        );
        final nachher = dienst.stand.value.ohneReiter(CommunityBereich.chats);
        expect(
          nachher.fuerReiter(CommunityBereich.chats).neu,
          isTrue,
          reason: 'Der Punkt darf erst ausgehen, wenn die Community selbst '
              'geöffnet wurde.',
        );
      },
    );

    test(
      'ohne offene Community löscht der Chats-Reiter seinen Punkt sofort',
      () {
        final dienst = CommunityNeuigkeitService.instance;
        dienst.standAusJsonFuerTest(antwort(chats: true));
        final nachher = dienst.stand.value.ohneReiter(CommunityBereich.chats);
        expect(nachher.fuerReiter(CommunityBereich.chats).neu, isFalse);
      },
    );
  });

  group('1.1 — Ebene 3: die einzelne Community', () {
    test('eine Community öffnen löscht nur ihren eigenen Punkt', () {
      final dienst = CommunityNeuigkeitService.instance;
      dienst.standAusJsonFuerTest(
        antwort(chats: true, communities: {'c1': true, 'c2': true}),
      );
      final nachher = dienst.stand.value.ohneCommunity('c1');
      expect(nachher.fuerCommunity('c1').neu, isFalse);
      expect(nachher.fuerCommunity('c2').neu, isTrue);
      expect(nachher.fuerReiter(CommunityBereich.chats).neu, isTrue);
    });

    test('die letzte offene Community löscht auch den Chats-Punkt', () {
      final dienst = CommunityNeuigkeitService.instance;
      dienst.standAusJsonFuerTest(
        antwort(chats: true, communities: {'c1': true}),
      );
      final nachher = dienst.stand.value.ohneCommunity('c1');
      expect(nachher.fuerCommunity('c1').neu, isFalse);
      expect(nachher.fuerReiter(CommunityBereich.chats).neu, isFalse);
      expect(nachher.punkt, isFalse);
    });

    test('eine unbekannte Community leuchtet nicht', () {
      final dienst = CommunityNeuigkeitService.instance;
      dienst.standAusJsonFuerTest(antwort());
      expect(dienst.stand.value.fuerCommunity('gibtesnicht').neu, isFalse);
      expect(dienst.stand.value.fuerCommunity(null).neu, isFalse);
    });
  });

  group('1.1 — die Bereichsnamen müssen zur Datenbank passen', () {
    test(
      'genau die fünf Bereiche, die community_als_gesehen_markieren erlaubt',
      () {
        expect(
          CommunityBereich.values.map((b) => b.schluessel).toList(),
          <String>['feed', 'gruppen', 'chats', 'entdecken', 'community'],
        );
      },
    );

    test(
      'die Reiter-Indizes stimmen mit CommunityPage überein: '
      '0 Feed, 1 Gruppen, 2 Chats, 3 Entdecken',
      () {
        expect(CommunityBereich.vonReiter(0), CommunityBereich.feed);
        expect(CommunityBereich.vonReiter(1), CommunityBereich.gruppen);
        expect(CommunityBereich.vonReiter(2), CommunityBereich.chats);
        expect(CommunityBereich.vonReiter(3), CommunityBereich.entdecken);
        expect(CommunityBereich.vonReiter(4), isNull);
        expect(CommunityBereich.vonReiter(-1), isNull);
      },
    );

    test('eine kaputte Antwort führt nicht zu einem Absturz', () {
      final dienst = CommunityNeuigkeitService.instance;
      dienst.standAusJsonFuerTest(<String, dynamic>{'reiter': 'Unsinn'});
      expect(dienst.stand.value.punkt, isFalse);
      dienst.standAusJsonFuerTest(<String, dynamic>{
        'reiter': {'feed': 'Unsinn'},
        'communities': 42,
      });
      expect(dienst.stand.value.fuerReiter(CommunityBereich.feed).neu, isFalse);
    });
  });

  group('1.1 — was im Code stehen muss', () {
    late String dienst;
    late String home;
    late String page;
    late String chats;

    String ohneKommentare(String quelle) => quelle
        .split('\n')
        .where((zeile) {
          final t = zeile.trimLeft();
          return !t.startsWith('//') && !t.startsWith('///');
        })
        .join('\n');

    setUpAll(() {
      dienst = ohneKommentare(
        File(
          'lib/data/services/community_neuigkeit_service.dart',
        ).readAsStringSync(),
      );
      home = ohneKommentare(
        File('lib/presentation/pages/home_page.dart').readAsStringSync(),
      );
      page = ohneKommentare(
        File('lib/presentation/pages/community_page.dart').readAsStringSync(),
      );
      chats = ohneKommentare(
        File(
          'lib/presentation/pages/community_chats_tab.dart',
        ).readAsStringSync(),
      );
    });

    test(
      'Akzeptanzkriterium 4: der Lesestand liegt serverseitig, nicht in '
      'SharedPreferences',
      () {
        expect(dienst.contains("rpc('community_hinweispunkte')"), isTrue);
        expect(
          dienst.contains("rpc(\n        'community_als_gesehen_markieren'") ||
              dienst.contains("'community_als_gesehen_markieren'"),
          isTrue,
        );
        // Die beiden alten Zähler-Schlüssel sind weg.
        expect(dienst.contains('community_gesehen_gruppen_v1'), isFalse);
        expect(dienst.contains('community_gesehen_vorschlaege_v1'), isFalse);
        expect(dienst.contains('shared_preferences'), isFalse);
      },
    );

    test(
      'der Punkt geht NICHT mehr aus, nur weil man Community antippt',
      () {
        final stelle = home.indexOf('if (index == 1) {');
        expect(stelle, greaterThan(0));
        final block = home.substring(stelle, stelle + 600);
        expect(block.contains('alsGesehenMarkieren'), isFalse);
        expect(block.contains('aktualisieren'), isTrue);
      },
    );

    test('jeder Reiter meldet genau seinen eigenen Bereich', () {
      expect(page.contains('bereich: CommunityBereich.feed'), isTrue);
      expect(page.contains('bereich: CommunityBereich.gruppen'), isTrue);
      expect(page.contains('bereich: CommunityBereich.chats'), isTrue);
      expect(page.contains('bereich: CommunityBereich.entdecken'), isTrue);
      expect(page.contains('_markiereReiterGesehen'), isTrue);
    });

    test(
      'der Punkt am Reiter ist ein Positioned IM Reiter, nicht neben dem '
      'Text — sonst rechnet die FittedBox ihn mit herunter',
      () {
        final stelle = page.indexOf('Widget _buildTabLabel(');
        expect(stelle, greaterThan(0));
        final block = page.substring(stelle, stelle + 2200);
        expect(block.contains('Positioned('), isTrue);
        expect(block.contains('Stack('), isTrue);
        // Die Beschriftung selbst bleibt in der FittedBox.
        expect(block.contains('FittedBox('), isTrue);
      },
    );

    test('die einzelne Community meldet sich beim Öffnen, nicht vorher', () {
      final stelle = chats.indexOf('Future<void> _openCommunity(');
      expect(stelle, greaterThan(0));
      final block = chats.substring(stelle, stelle + 700);
      expect(block.contains('CommunityBereich.community'), isTrue);
      expect(block.contains('communityId: communityId'), isTrue);
    });
  });
}
