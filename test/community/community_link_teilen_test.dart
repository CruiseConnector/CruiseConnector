import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/pages/community_einstieg.dart';
import 'package:cruise_connect/presentation/pages/community_teilen_blatt.dart';

/// 2026-08-31 (Auftrag Vucko, Sprachnachricht: „dass man die community auch
/// auf anderen Seiten verlinken kann wie Instagram Snapchat und so weiter mit
/// deinem Link [...] dass man direkt in den Screen kommt wie wenn man auf die
/// Gruppe klickt").
///
/// Was hier geprueft wird, ist genau der Teil der Kette, der OHNE Netz und
/// ohne Datenbank stimmen muss: der Link wird gebaut, der Link wird wieder
/// gelesen, der gelesene Wert wird richtig einsortiert, und der gemerkte Link
/// ueberlebt eine Anmeldung.
///
/// Was hier NICHT geprueft werden kann: ob der Link von aussen die App
/// oeffnet. Das entscheidet der Webserver (assetlinks.json,
/// apple-app-site-association), nicht der Code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Community-Link bauen', () {
    test('Der Link traegt den Einladungscode im Pfad', () {
      final uri = CruiseDeepLinks.communityUri('CCC-ABC234');
      expect(uri.scheme, 'https');
      expect(uri.host, 'cruiseconnector.at');
      expect(uri.path, '/c/CCC-ABC234');
      expect(
        CruiseDeepLinks.communityUrl('CCC-ABC234'),
        'https://cruiseconnector.at/c/CCC-ABC234',
      );
    });

    test('Leerzeichen um den Code herum fliegen raus', () {
      expect(
        CruiseDeepLinks.communityUri('  CCC-ABC234 ').path,
        '/c/CCC-ABC234',
      );
    });

    test('Kein Fragezeichen im Link', () {
      // Begruendung steht bei communityUri: `https://cruiseconnector.at/?x=y`
      // antwortet mit 302 auf /home und wirft die Abfrage dabei weg.
      // Gemessen am 31.08.2026.
      expect(CruiseDeepLinks.communityUri('CCC-ABC234').hasQuery, isFalse);
    });
  });

  group('Community-Link lesen', () {
    test('Der selbst gebaute Link kommt wieder heraus', () {
      final uri = CruiseDeepLinks.communityUri('CCC-ABC234');
      expect(CruiseDeepLinks.communityCodeAus(uri), 'CCC-ABC234');
    });

    test('Alle Formen, die ein geteilter Link haben kann', () {
      final formen = <String>[
        'https://cruiseconnector.at/c/CCC-ABC234',
        'https://cruiseconnector.at/community/CCC-ABC234',
        'https://cruiseconnector.at/?community=CCC-ABC234',
        'https://cruiseconnector.at/?cm=CCC-ABC234',
        'cruiseconnect://community/CCC-ABC234',
        'cruiseconnect://c/CCC-ABC234',
      ];
      for (final form in formen) {
        expect(
          CruiseDeepLinks.communityCodeAus(Uri.parse(form)),
          'CCC-ABC234',
          reason: 'Form nicht erkannt: $form',
        );
      }
    });

    test('Fremde Links liefern nichts', () {
      final fremde = <String>[
        'https://cruiseconnector.at/home',
        'https://cruiseconnector.at/?group=abc',
        'https://cruiseconnector.at/?post=abc',
        'https://cruiseconnector.at/group/abc',
        'https://cruiseconnector.at/post/abc',
        'https://cruiseconnector.at/c/',
        'cruiseconnect://group/abc',
      ];
      for (final link in fremde) {
        expect(
          CruiseDeepLinks.communityCodeAus(Uri.parse(link)),
          isNull,
          reason: 'Faelschlich als Community gelesen: $link',
        );
      }
    });

    test('Ein Community-Link ist kein Gruppen-Link und kein Anmeldelink', () {
      // Die drei Leser in main.dart laufen nacheinander. Greift einer zu
      // frueh, kommt der Nutzer nie an. Genau so ist der Gruppen-Link am
      // 23.08. im Nichts verschwunden.
      final uri = CruiseDeepLinks.communityUri('CCC-ABC234');
      expect(CruiseDeepLinks.gruppenIdAus(uri), isNull);
      // `?code=` ist der Name, an dem main.dart einen Anmeldelink erkennt.
      // Der Community-Link darf ihn nicht benutzen.
      expect(uri.queryParameters.containsKey('code'), isFalse);
    });
  });

  group('Was im Link steht, wird richtig einsortiert', () {
    test('Ein Einladungscode wird als Code erkannt', () {
      expect(CommunityEinstieg.istEinladungscode('CCC-ABC234'), isTrue);
      expect(CommunityEinstieg.istEinladungscode('cccabc234'), isTrue);
      expect(CommunityEinstieg.istEinladungscode('CM-ABC234'), isTrue);
      expect(CommunityEinstieg.istKennung('CCC-ABC234'), isFalse);
    });

    test('Eine Kennung wird als Kennung erkannt', () {
      const kennung = '1f5c2b7e-4a3d-4c6b-9e21-8d0f7a6b5c34';
      expect(CommunityEinstieg.istKennung(kennung), isTrue);
      expect(CommunityEinstieg.istEinladungscode(kennung), isFalse);
    });

    test('Alles andere ist unbrauchbar und faellt in keinen der beiden Toepfe', () {
      for (final muell in <String>['', '   ', 'hallo', 'CCC-AB', '12345']) {
        expect(CommunityEinstieg.istEinladungscode(muell), isFalse);
        expect(CommunityEinstieg.istKennung(muell), isFalse);
      }
    });
  });

  group('Gemerkter Link ueberlebt die Anmeldung', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('Ohne gemerkten Link kommt nichts zurueck', () async {
      expect(await OffenerCommunityLink.holeUndLoescheCode(), isNull);
    });

    test('Der Code wird gemerkt und genau EINMAL herausgegeben', () async {
      await OffenerCommunityLink.merkeCode('CCC-ABC234');
      expect(await OffenerCommunityLink.holeUndLoescheCode(), 'CCC-ABC234');
      // Der zweite Aufruf muss leer sein, sonst blendet die App bei jedem
      // Start dieselbe fremde Community auf.
      expect(await OffenerCommunityLink.holeUndLoescheCode(), isNull);
    });

    test('Nach sieben Tagen ist der Link verfallen', () async {
      await OffenerCommunityLink.merkeCode('CCC-ABC234');
      final spaeter = DateTime.now().toUtc().add(const Duration(days: 8));
      expect(
        await OffenerCommunityLink.holeUndLoescheCode(jetzt: spaeter),
        isNull,
      );
    });

    test('Verwerfen loescht den gemerkten Link', () async {
      await OffenerCommunityLink.merkeCode('CCC-ABC234');
      await OffenerCommunityLink.verwerfen();
      expect(await OffenerCommunityLink.holeUndLoescheCode(), isNull);
    });

    test('Community- und Gruppen-Link liegen getrennt', () async {
      // Sonst wuerde ein Gruppen-Link einen gemerkten Community-Link
      // ueberschreiben, ohne dass es irgendwo auffaellt.
      await OffenerCommunityLink.merkeCode('CCC-ABC234');
      await OffenerEinladungsLink.merkeGruppe('gruppe-1');
      expect(await OffenerCommunityLink.holeUndLoescheCode(), 'CCC-ABC234');
      expect(await OffenerEinladungsLink.holeUndLoescheGruppe(), 'gruppe-1');
    });
  });

  group('Die Texte zum Teilen', () {
    const link = 'https://cruiseconnector.at/c/CCC-ABC234';

    test('Der Text nach aussen nennt Name und Link', () {
      final text = communityTeilenText(name: 'Vorarlberg Cruiser', linkUrl: link);
      expect(text, contains('Vorarlberg Cruiser'));
      expect(text, contains(link));
      // Wer den Link auf Instagram sieht, kennt die App nicht. Der Name muss
      // im Text stehen.
      expect(text, contains('Cruise Connect'));
    });

    test('Der Beitrag im Feed erklaert die App nicht noch einmal', () {
      final text = communityBeitragText(name: 'Vorarlberg Cruiser', linkUrl: link);
      expect(text, contains('Vorarlberg Cruiser'));
      expect(text, contains(link));
      expect(text.contains('Cruise Connect'), isFalse);
    });

    test('Ohne Namen bleibt ein ganzer Satz stehen', () {
      for (final name in <String>['', '   ']) {
        expect(communityTeilenText(name: name, linkUrl: link), contains(link));
        expect(
          communityBeitragText(name: name, linkUrl: link),
          contains(link),
        );
        expect(communityTeilenText(name: name, linkUrl: link), isNot(contains('..')));
      }
    });

    test('Kein Strich und echte Umlaute im Text selbst', () {
      // Der Waechtertest in test/core prueft lib/. Hier steht dieselbe Regel
      // noch einmal fuer den Teil, den der Nutzer verschickt: die Adresse
      // darf einen Strich haben, der Satz drumherum nicht.
      for (final text in <String>[
        communityTeilenText(name: 'Cruiser', linkUrl: link),
        communityBeitragText(name: 'Cruiser', linkUrl: link),
      ]) {
        final ohneLink = text.replaceAll(link, '');
        expect(ohneLink.contains('-'), isFalse, reason: text);
        expect(ohneLink.contains('–'), isFalse, reason: text);
        expect(ohneLink.contains('—'), isFalse, reason: text);
        expect(ohneLink.contains('ue'), isFalse, reason: text);
        expect(ohneLink.contains('ae'), isFalse, reason: text);
        expect(ohneLink.contains('oe'), isFalse, reason: text);
      }
    });
  });

  group('Ein eingefuegter Link im Suchfeld', () {
    test('Der ganze Link wird als Code verstanden', () {
      expect(
        CommunityChatService.einladungscodeAusEingabe(
          'https://cruiseconnector.at/c/CCC-ABC234',
        ),
        'CCC-ABC234',
      );
      expect(
        CommunityChatService.einladungscodeAusEingabe(
          '  https://cruiseconnector.at/community/ccc-abc234  ',
        ),
        'CCC-ABC234',
      );
    });

    test('Der blosse Code geht weiterhin durch', () {
      expect(
        CommunityChatService.einladungscodeAusEingabe('CCC-ABC234'),
        'CCC-ABC234',
      );
      expect(
        CommunityChatService.einladungscodeAusEingabe('cm abc234'),
        'CM-ABC234',
      );
    });

    test('Ein Name bleibt ein Name und wird nicht zum Code', () {
      // Das Feld sucht auch nach Namen. Wuerde hier etwas herauskommen,
      // liefe jede Namenssuche in eine Codeabfrage.
      for (final eingabe in <String>['Opel', 'Vorarlberg', '', 'https://x.at']) {
        expect(
          CommunityChatService.einladungscodeAusEingabe(eingabe),
          isNull,
          reason: eingabe,
        );
      }
    });
  });

  group('Ein eingefuegter Link fuehrt in die Vorschau, nicht in den Beitritt', () {
    test('_joinCommunityWithCode schickt Links ueber CommunityEinstieg', () {
      // Vucko woertlich: „dass man wieder den Vorschau Bildschirm hat mit
      // kurzer Beschreibung und dem Titel und dass man auf beitreten klicken
      // kann oder nicht." Ein Link darf also nie direkt beitreten.
      final quelle = File(
        'lib/presentation/pages/community_chats_tab.dart',
      ).readAsStringSync();
      final start = quelle.indexOf('Future<void> _joinCommunityWithCode');
      expect(start, greaterThan(-1));
      final block = quelle.substring(start, start + 1400);
      final linkZweig = block.indexOf('communityCodeAus');
      final beitrittZweig = block.indexOf('joinCommunityByCode');
      expect(linkZweig, greaterThan(-1));
      expect(beitrittZweig, greaterThan(-1));
      expect(
        linkZweig < beitrittZweig,
        isTrue,
        reason: 'Der Link muss VOR dem direkten Beitritt abgefangen werden.',
      );
      expect(block.contains('CommunityEinstieg.oeffnen('), isTrue);
    });
  });

  group('Der Code im Link ist derselbe, den die Datenbank kennt', () {
    test('normalizeInviteCode nimmt an, was communityUri baut', () {
      // Beide Enden derselben Kette: die App baut den Link aus dem Code, den
      // `get_community_invite_code` liefert, und schickt ihn spaeter genau so
      // an `find_community_by_code`.
      for (final code in <String>['CCC-ABC234', 'CM-ABC234']) {
        final uri = CruiseDeepLinks.communityUri(code);
        final gelesen = CruiseDeepLinks.communityCodeAus(uri);
        expect(CommunityChatService.normalizeInviteCode(gelesen!), code);
      }
    });
  });
}
