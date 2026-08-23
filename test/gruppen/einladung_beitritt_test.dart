import 'dart:io';

import 'package:cruise_connect/core/deep_links.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/presentation/pages/group_join_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-23 (vucko, Sprachnachricht vom 23.08.): „wenn er eine Gruppe
/// erstellt hat und er einen anderen einlaedt [...] und er ueber die Glocke
/// bzw. ueber den Quicklink dann joinen will [...] dass ein Fehler kommt."
///
/// Gemessener Vorfall: Gruppe ac29cf1f-e50f-4b2e-81d3-d99885e7e084
/// („latenight session", privat, 21.08. 21:38). Der Eingeladene
/// 645065af-3999-4e66-90cd-c4718c0b8ddf tippte um 21:42:49, 21:42:57 und
/// 21:44:13 auf die Glocke; jedes Mal HTTP 200 mit content_length 2 (leere
/// Liste), danach nie ein Lobby-Aufruf. Einladungen 2, eingeloest 0.
///
/// Ursache: `groups_visible_before_live_or_member` kennt keinen Zweig fuer
/// Eingeladene, `can_join_group` dagegen schon. Beitreten war erlaubt, LESEN
/// nicht. Der Client hat die leere Antwort als „geloescht" gedeutet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Die vier geforderten Kombinationen ──────────────────────────────────
  group('privat und oeffentlich, ueber Glocke und ueber Quicklink', () {
    // Beide Eingaenge nehmen exakt dieselbe Entscheidung (siehe Quelltext-
    // Pruefung weiter unten), deshalb steht die Regel hier einmal je Fall.

    test('privat, Lesepolitik versteckt die Gruppe: Einladung, nicht "weg"', () {
      // Genau der Zustand vom 21.08.: Zeile nicht lesbar, Einladung vorhanden.
      final zugang = SocialService.entscheideGruppenZugang(
        angemeldet: true,
        zeileLesbar: false,
        binMitglied: false,
        darfBeitreten: true,
      );
      expect(
        zugang,
        GruppenZugang.einladung,
        reason:
            'Eine leere Antwort heisst „du darfst nicht lesen", nicht „gibt '
            'es nicht". Sagt can_join_group ja, ist die Gruppe da.',
      );
    });

    test('privat, nach der Reparatur der Lesepolitik: weiterhin Einladung', () {
      final zugang = SocialService.entscheideGruppenZugang(
        angemeldet: true,
        zeileLesbar: true,
        binMitglied: false,
        darfBeitreten: true,
      );
      expect(zugang, GruppenZugang.einladung);
    });

    test('oeffentlich, noch nicht Mitglied: Einladung mit Beitreten-Knopf', () {
      final zugang = SocialService.entscheideGruppenZugang(
        angemeldet: true,
        zeileLesbar: true,
        binMitglied: false,
        darfBeitreten: true,
      );
      expect(zugang, GruppenZugang.einladung);
    });

    test('bereits Mitglied: direkt in die Lobby, ohne Rueckfrage', () {
      final zugang = SocialService.entscheideGruppenZugang(
        angemeldet: true,
        zeileLesbar: true,
        binMitglied: true,
        darfBeitreten: false,
      );
      expect(zugang, GruppenZugang.mitglied);
    });
  });

  // ── Die Ehrlichkeit in die andere Richtung ──────────────────────────────
  test('Gruppe wirklich geloescht: bleibt eine ehrliche Absage', () {
    final zugang = SocialService.entscheideGruppenZugang(
      angemeldet: true,
      zeileLesbar: false,
      binMitglied: false,
      darfBeitreten: false,
    );
    expect(
      zugang,
      GruppenZugang.nichtVerfuegbar,
      reason:
          'Sonst haetten wir den Fehler nur umgedreht und schickten Leute in '
          'eine Gruppe, die es nicht mehr gibt.',
    );
  });

  test('nicht angemeldet wird als eigener Fall behandelt', () {
    expect(
      SocialService.entscheideGruppenZugang(
        angemeldet: false,
        zeileLesbar: false,
        binMitglied: false,
        darfBeitreten: false,
      ),
      GruppenZugang.nichtAngemeldet,
    );
  });

  // ── Ohne Anmeldung: Link merken und nachholen ───────────────────────────
  group('Einladungslink ohne Anmeldung', () {
    test('wird gemerkt, ueberlebt den Kaltstart und wirkt genau einmal',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await OffenerEinladungsLink.merkeGruppe(
        'ac29cf1f-e50f-4b2e-81d3-d99885e7e084',
      );

      // Kaltstart: neue Instanz, aber dieselbe Platte.
      final ersteHolung = await OffenerEinladungsLink.holeUndLoescheGruppe();
      expect(
        ersteHolung,
        'ac29cf1f-e50f-4b2e-81d3-d99885e7e084',
        reason: 'Ein Einladungslink soll NEUE Leute holen. Genau die sind '
            'beim Antippen nicht angemeldet.',
      );

      final zweiteHolung = await OffenerEinladungsLink.holeUndLoescheGruppe();
      expect(
        zweiteHolung,
        isNull,
        reason: 'Sonst blendet die App bei jedem Start dieselbe Gruppe auf.',
      );
    });

    test('ein alter Link verfaellt statt Wochen spaeter aufzuploppen',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await OffenerEinladungsLink.merkeGruppe('alt-1234');
      final spaeter = DateTime.now().toUtc().add(const Duration(days: 8));
      expect(
        await OffenerEinladungsLink.holeUndLoescheGruppe(jetzt: spaeter),
        isNull,
      );
    });
  });

  // ── Link-Lesen ──────────────────────────────────────────────────────────
  test('Quicklink in allen Schreibweisen liefert dieselbe Gruppen-ID', () {
    const id = 'ac29cf1f-e50f-4b2e-81d3-d99885e7e084';
    expect(
      CruiseDeepLinks.gruppenIdAus(Uri.parse('https://cruiseconnector.at/?group=$id')),
      id,
    );
    expect(
      CruiseDeepLinks.gruppenIdAus(Uri.parse('https://cruiseconnector.at/group/$id')),
      id,
    );
    expect(
      CruiseDeepLinks.gruppenIdAus(Uri.parse('cruiseconnect://group/$id')),
      id,
    );
    expect(CruiseDeepLinks.gruppenIdAus(CruiseDeepLinks.groupUri(id)), id);
    expect(
      CruiseDeepLinks.gruppenIdAus(Uri.parse('https://cruiseconnector.at/?post=abc')),
      isNull,
    );
  });

  // ── Der fehlende Beitritts-Bildschirm ───────────────────────────────────
  group('Einladungsblatt', () {
    testWidgets('nennt Einlader und Gruppenname und hat einen Knopf',
        (tester) async {
      var getippt = false;
      await tester.pumpWidget(
        MaterialApp(
          home: GruppenEinladungsBlatt(
            gruppenName: 'latenight session',
            einladerName: 'vucko',
            mitgliederAnzahl: 2,
            onBeitreten: () => getippt = true,
          ),
        ),
      );

      expect(find.text('vucko lädt dich zu latenight session ein'), findsOneWidget);
      expect(find.text('Beitreten'), findsOneWidget);

      await tester.tap(find.text('Beitreten'));
      await tester.pump();
      expect(
        getippt,
        isTrue,
        reason: 'Die Lobby hat keinen Beitreten-Knopf. Ohne diesen hier gibt '
            'es fuer einen Eingeladenen keinen Weg hinein.',
      );
    });

    testWidgets('ohne bekannten Namen bleibt der Text lesbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GruppenEinladungsBlatt(onBeitreten: () {}),
        ),
      );
      expect(find.text('Du wurdest zu einer Gruppenfahrt eingeladen'),
          findsOneWidget);
    });

    testWidgets('waehrend des Beitritts ist der Knopf gesperrt',
        (tester) async {
      var getippt = false;
      await tester.pumpWidget(
        MaterialApp(
          home: GruppenEinladungsBlatt(
            laeuft: true,
            onBeitreten: () => getippt = true,
          ),
        ),
      );
      final knopf = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(knopf.onPressed, isNull);
      expect(getippt, isFalse);
    });
  });

  // ── Regressionsschutz an den drei Eingaengen ────────────────────────────
  group('Alle drei Eingaenge nehmen denselben Weg', () {
    test('groupExists ist verschwunden und darf nicht zurueckkommen', () {
      final quellen = [
        'lib/data/services/social_service.dart',
        'lib/main.dart',
        'lib/presentation/pages/notifications_page.dart',
      ];
      for (final pfad in quellen) {
        final text = File(pfad).readAsStringSync();
        final code = text
            .split('\n')
            .where((z) {
              final t = z.trimLeft();
              return !t.startsWith('///') && !t.startsWith('//');
            })
            .join('\n');
        expect(
          code.contains('groupExists'),
          isFalse,
          reason:
              '$pfad benutzt wieder groupExists. Diese Funktion hat eine '
              'leere PostgREST-Antwort als „geloescht" gedeutet und den '
              'eingeladenen Fahrer am 21.08. dreimal abgewiesen.',
        );
      }
    });

    test('der Quicklink bricht nicht mehr stumm ab', () {
      final quelle = File('lib/main.dart').readAsStringSync();
      expect(
        quelle.contains('GruppenEinstieg.oeffnen(groupId)'),
        isTrue,
        reason: 'main.dart muss den Gruppen-Deeplink an denselben Einstieg '
            'geben wie die Glocke.',
      );
    });

    test('die getippte Handy-Push ist verdrahtet', () {
      final quelle =
          File('lib/data/services/push_notification_service.dart')
              .readAsStringSync();
      expect(
        quelle.contains('NotificationRouter.ausPushDaten(data)'),
        isTrue,
        reason: '_handleTapData war ein leerer Rumpf mit TODO. Wer auf die '
            'Handy-Meldung tippte, landete auf der Startseite.',
      );
      expect(
        quelle.contains('FirebaseMessaging.onMessageOpenedApp'),
        isTrue,
        reason: 'Warmstart-Weg muss erhalten bleiben.',
      );
      expect(
        quelle.contains('FirebaseMessaging.instance.getInitialMessage()'),
        isTrue,
        reason: 'Kaltstart-Weg muss erhalten bleiben.',
      );
    });

    test('die Einladung laeuft ueber invite_to_group', () {
      final quelle =
          File('lib/data/services/social_service.dart').readAsStringSync();
      final block = quelle.substring(
        quelle.indexOf('static Future<void> inviteToGroup('),
      );
      final rumpf = block.substring(0, block.indexOf('\n  }'));
      expect(
        rumpf.contains("'invite_to_group'"),
        isTrue,
        reason:
            'Die RPC traegt payload.group_name ein (gelesen von '
            'notification_service.dart:327 und send-push) und prueft, wer '
            'einlaedt. Ohne sie heisst jede Einladung „laedt dich zu einer '
            'Gruppe ein", und jeder koennte sich per selbst geschriebener '
            'Einladung Lesezugang zu einer fremden privaten Gruppe holen.',
      );
      expect(
        rumpf.contains("from('notifications').insert"),
        isFalse,
        reason: 'Der ungepruefte Direkt-Insert darf nicht zurueckkommen.',
      );
    });

    test('die Glocke gibt an denselben Router ab', () {
      final quelle =
          File('lib/presentation/pages/notifications_page.dart')
              .readAsStringSync();
      expect(quelle.contains('NotificationRouter.oeffne('), isTrue);
    });

    test('der Kaltstart wartet auf den Navigator statt auf eine feste Zeit',
        () {
      final quelle = File('lib/main.dart').readAsStringSync();
      expect(
        quelle.contains('_wartAufNavigator('),
        isTrue,
        reason: 'Deep-Links gehen beim Kaltstart verloren, wenn man nur '
            'geraten kurz wartet.',
      );
      expect(
        quelle.contains('OffenerEinladungsLink') ||
            quelle.contains('holeGemerktenLinkNach'),
        isTrue,
        reason: 'Nach der Anmeldung muss der gemerkte Link nachgeholt werden.',
      );
    });
  });

  // ── App-Links-Einrichtung im Repo ───────────────────────────────────────
  group('App-Links-Dateien im Repo', () {
    test('assetlinks nennt das echte Paket', () {
      final text = File('web/.well-known/assetlinks.json').readAsStringSync();
      expect(text.contains('com.vucko.cruiserconnect'), isTrue);
      expect(
        text.contains('com.example.cruise_connect'),
        isFalse,
        reason: 'Mit dem Beispielpaket verifiziert Android den Link nie.',
      );
    });

    test('die AASA deckt Gruppen-Links ab', () {
      final text =
          File('web/.well-known/apple-app-site-association').readAsStringSync();
      expect(
        text.contains('"group"'),
        isTrue,
        reason: 'Ohne ?group=* oeffnet iOS den Einladungslink im Browser.',
      );
      expect(text.contains('"post"'), isTrue);
    });

    test('iOS traegt die verknuepfte Domain', () {
      final text = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(text.contains('com.apple.developer.associated-domains'), isTrue);
      expect(text.contains('applinks:cruiseconnector.at'), isTrue);
    });
  });
}
