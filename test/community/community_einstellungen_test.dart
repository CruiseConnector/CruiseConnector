import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/pages/community_settings_page.dart';

/// 2026-08-23 (Auftrag Vucko, Sprachnachricht): „...dass man für Communities
/// wirklich auch Profilbilder reintun kann und auch entweder in den nur
/// Schreibmodus für den Admin einstellen kann oder auch Schreibmodus für alle.
/// Und ganz wichtig, dass man auch im Nachhinein einstellen kann, ob eine
/// Community privat oder öffentlich ist."
///
/// Diese Tests bewachen genau das, was ohne zwei Konten und ohne Gerät
/// prüfbar ist: die Spaltenlisten, die Fehlerbehandlung beim Hochladen, die
/// Texte und die Auswertung des neuen Beitritts-Ergebnisses.
void main() {
  late String service;
  late String detailPage;
  late String chatsTab;

  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((zeile) {
        final t = zeile.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  setUpAll(() {
    service = File(
      'lib/data/services/community_chat_service.dart',
    ).readAsStringSync();
    detailPage = File(
      'lib/presentation/pages/community_chat_detail_page.dart',
    ).readAsStringSync();
    chatsTab = File(
      'lib/presentation/pages/community_chats_tab.dart',
    ).readAsStringSync();
  });

  // ───────────────────────────────────────────────────────────────────────
  // Aufgabe A: das Community-Bild
  // ───────────────────────────────────────────────────────────────────────

  group('Community-Bild', () {
    test('avatarUrl liest die Spalte und behandelt Leeres wie kein Bild', () {
      expect(CommunityChatService.avatarUrl(null), isNull);
      expect(CommunityChatService.avatarUrl(const {}), isNull);
      expect(CommunityChatService.avatarUrl(const {'avatar_url': ''}), isNull);
      expect(
        CommunityChatService.avatarUrl(const {'avatar_url': '   '}),
        isNull,
        reason: 'Nur Leerzeichen ist kein Bild, sonst bleibt der Platzhalter '
            'aus und die Kachel zeigt ein Loch.',
      );
      expect(
        CommunityChatService.avatarUrl(const {
          'avatar_url': 'https://x/y.jpg?t=1',
        }),
        'https://x/y.jpg?t=1',
      );
    });

    test('die drei Anzeigestellen benutzen dasselbe Widget', () {
      // Gemessen am 23.08.2026: die Kachel wird an DREI Orten gerendert
      // (Meine Communities, Entdecken, Treffer der Code-Suche), zusätzlich
      // gibt es die AppBar und die Kopfzeile im Chat. Wenn eine Stelle wieder
      // einen eigenen Platzhalter baut, laufen sie auseinander.
      expect(chatsTab.contains('CommunityAvatar.fromCommunity'), isTrue);
      expect(
        RegExp(
          'CommunityAvatar.fromCommunity',
        ).allMatches(detailPage).length,
        greaterThanOrEqualTo(2),
        reason: 'AppBar und Kopfzeile brauchen beide das Bild.',
      );
      // Der Platzhalter (Forum-Symbol bei öffentlich, Schloss bei privat)
      // gehört ins Widget. In der Kachel darf er nicht noch einmal stehen,
      // sonst laufen die Stellen wieder auseinander. Das Forum-Symbol im
      // Leerzustand („Noch keine Community") ist etwas anderes und bleibt.
      expect(
        ohneKommentare(chatsTab).contains(
          'isPublic ? Icons.forum_outlined : Icons.lock_outline',
        ),
        isFalse,
      );
    });

    test('zu großes Bild wird vor dem Hochladen abgefangen', () {
      final fehler = CommunityImageRules.fehlerFuer(
        fileName: 'bild.jpg',
        byteLength: CommunityImageRules.maxBytes + 1,
      );
      expect(fehler, CommunityImageRules.zuGross);
      expect(
        fehler,
        contains('5 MB'),
        reason: 'Der Nutzer muss die Grenze erfahren, nicht nur ein Nein.',
      );
    });

    test('genau an der Grenze geht das Bild noch durch', () {
      expect(
        CommunityImageRules.fehlerFuer(
          fileName: 'bild.jpg',
          byteLength: CommunityImageRules.maxBytes,
        ),
        isNull,
      );
    });

    test('falsches Format wird abgefangen, erlaubte Formate nicht', () {
      expect(
        CommunityImageRules.fehlerFuer(
          fileName: 'urlaub.heic',
          byteLength: 1000,
        ),
        CommunityImageRules.falschesFormat,
      );
      expect(
        CommunityImageRules.fehlerFuer(fileName: 'ohnePunkt', byteLength: 1000),
        CommunityImageRules.falschesFormat,
      );
      for (final endung in ['jpg', 'JPEG', 'png', 'WebP']) {
        expect(
          CommunityImageRules.fehlerFuer(
            fileName: 'bild.$endung',
            byteLength: 1000,
          ),
          isNull,
          reason: '$endung ist im Bucket community_images erlaubt.',
        );
      }
    });

    test('leere Datei bekommt einen eigenen Satz', () {
      expect(
        CommunityImageRules.fehlerFuer(fileName: 'bild.jpg', byteLength: 0),
        CommunityImageRules.leer,
      );
    });

    test('Endung wird auch mit Cache-Buster erkannt', () {
      expect(CommunityImageRules.dateiendung('a/b/c.JPG?t=17'), 'jpg');
      expect(CommunityImageRules.dateiendung('kein_punkt'), isNull);
      expect(CommunityImageRules.dateiendung('endet_mit.'), isNull);
    });

    test('jeder hässliche Fall hat eine deutsche Meldung, keine Ausnahme', () {
      final meldungen = [
        CommunityImageRules.zuGross,
        CommunityImageRules.falschesFormat,
        CommunityImageRules.leer,
        CommunityImageRules.hochladenFehlgeschlagen,
        CommunityImageRules.keinKameraZugriff,
        CommunityImageRules.keinGalerieZugriff,
      ];
      for (final meldung in meldungen) {
        expect(meldung.trim(), isNotEmpty);
        expect(
          meldung.toLowerCase(),
          isNot(contains('exception')),
          reason: 'Rohe Ausnahmen gehören nicht in einen Toast: $meldung',
        );
      }
    });

    test('der Upload nutzt eine ZWEITE Funktion, uploadUserAsset bleibt', () {
      final social = File(
        'lib/data/services/social_service.dart',
      ).readAsStringSync();
      expect(
        social.contains('static Future<String?> uploadUserAsset('),
        isTrue,
        reason: 'uploadUserAsset wird an fünf Stellen benutzt und bleibt.',
      );
      expect(
        social.contains('static Future<String?> uploadCommunityAsset('),
        isTrue,
      );
      // Der Ordner ist die Community-Kennung, nicht die Nutzer-Kennung: sonst
      // könnte der zweite Admin einer Community (gemessen: „Has.Crew" hat zwei
      // Zeilen mit role = owner) das Bild des ersten nie ersetzen.
      expect(social.contains("final path = '\$cleanId/\$fileName';"), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Spaltenlisten: der Einladungscode ist nicht mehr abgreifbar
  // ───────────────────────────────────────────────────────────────────────

  group('Spaltenliste communities', () {
    /// Nur die EIGENEN Spalten von public.communities, ohne den angehängten
    /// Join auf community_members und profiles. Sonst zählt das `avatar_url`
    /// aus `profiles:owner_id(...)` als Treffer und der Test ist wertlos.
    String eigeneSpalten(String name) {
      final start = service.indexOf('static const String $name =');
      expect(start, isNot(-1), reason: 'Konstante fehlt: $name');
      final ende = service.indexOf(';', start);
      final ganz = service.substring(start, ende);
      final join = ganz.indexOf('community_members(');
      expect(join, isNot(-1), reason: 'Join fehlt in $name');
      return ganz.substring(0, join);
    }

    test('invite_code steht NICHT mehr in _communitySelect', () {
      // Gemessen am 23.08.2026: `authenticated` hatte ein tabellenweites
      // Leserecht auf public.communities, also konnte jeder angemeldete Nutzer
      // den Code jeder öffentlichen Community abgreifen und ihn nach einem
      // Wechsel auf privat einlösen. Die Migration 20260823123000 hat das
      // Recht auf eine Spaltenliste OHNE invite_code verengt. Bliebe die
      // Spalte hier stehen, käme bei JEDEM Laden ein 42501.
      expect(eigeneSpalten('_communitySelect').contains('invite_code'), isFalse);
    });

    test('avatar_url steht in _communitySelect', () {
      expect(eigeneSpalten('_communitySelect').contains('avatar_url'), isTrue);
    });

    test('_legacyCommunitySelect bleibt unverändert', () {
      // Diese Liste läuft nur auf Datenbanken VOR der Migration. Dort ist der
      // Code noch tabellenweit lesbar; sie darf deshalb nicht mitgezogen
      // werden, sonst stirbt der Rückfall für alte Stände.
      final legacy = eigeneSpalten('_legacyCommunitySelect');
      expect(legacy.contains('invite_code'), isTrue);
      expect(legacy.contains('avatar_url'), isFalse);
      expect(legacy.contains('owner_only_messages'), isFalse);
    });

    test('der Code kommt über die RPC, nicht mehr aus der Zeile', () {
      expect(service.contains("'get_community_invite_code'"), isTrue);
      expect(
        ohneKommentare(detailPage).contains("community['invite_code']"),
        isFalse,
        reason: 'Die Spalte ist für die App nicht mehr lesbar.',
      );
      expect(detailPage.contains('CommunityChatService.inviteCodeFor'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Aufgabe B: Schreibmodus, ehrlicher Text und benannter Fehler
  // ───────────────────────────────────────────────────────────────────────

  group('Schreibmodus', () {
    test('der Text nennt Moderatoren mit, „Nur Owner" ist raus', () {
      // Gemessen an der Regel members_write_community_messages: im
      // nur-Admin-Modus dürfen owner UND moderator schreiben. Der alte
      // Menütext „Nur Owner schreibt" war damit sachlich falsch.
      expect(
        CommunityChatService.writeModeAdminsTitle.toLowerCase(),
        contains('moderator'),
      );
      expect(detailPage.contains('Nur Owner schreibt'), isFalse);
      expect(
        detailPage.contains('Nur Admins können hier posten.'),
        isFalse,
        reason: 'Auch dieser Satz verschwieg die Moderatoren.',
      );
    });

    test('die Erklärung sagt, dass Reagieren offen bleibt', () {
      // Entscheidung Vucko vom 23.08.2026: im Modus „nur Admin" werden NUR
      // Beiträge gesperrt. Wer etwas anderes erwartet, sucht später den Fehler.
      final text = CommunityChatService.writeModeExplanation.toLowerCase();
      expect(text, contains('beiträge'));
      expect(text, contains('reagieren'));
    });

    test('gesperrtes Schreiben bekommt einen benannten Fehler', () {
      expect(CommunityChatService.writeLockedCode, isNotEmpty);
      expect(
        CommunityChatService.writeLockedMessage,
        'Der Admin hat das Schreiben gerade gesperrt.',
      );
      const fehler = CommunityChatServiceException(
        CommunityChatService.writeLockedMessage,
        code: CommunityChatService.writeLockedCode,
      );
      expect(fehler.code, CommunityChatService.writeLockedCode);
    });

    test('_friendlyError lässt benannte Fehler durch', () {
      // Ohne diese Ausnahme filtert _friendlyError den echten Grund weg: es
      // wirft alles mit „policy" oder „row-level" bewusst als Rauschen raus,
      // und genau das schickt Postgres bei gesperrtem Schreiben.
      final rumpfStart = detailPage.indexOf(
        'String _friendlyError(Object error, String fallback) {',
      );
      expect(rumpfStart, isNot(-1));
      final rumpf = detailPage.substring(rumpfStart, rumpfStart + 900);
      expect(
        rumpf.contains('error is CommunityChatServiceException') &&
            rumpf.contains('error.code != null'),
        isTrue,
      );
      expect(
        rumpf.indexOf('error.code != null') < rumpf.indexOf('isBackendNoise'),
        isTrue,
        reason: 'Die Ausnahme muss VOR dem Rauschfilter greifen.',
      );
    });

    test('das Umschalten kommt bei offenem Chat an', () {
      // Gemessen: subscribeMessages und subscribeMembers horchen nicht auf
      // die Tabelle communities, obwohl sie in der Publikation liegt. Ein
      // Mitglied tippte deshalb im nur-Admin-Modus einen langen Beitrag und
      // erfuhr erst beim Senden davon.
      expect(service.contains('static RealtimeChannel subscribeCommunity('), isTrue);
      expect(service.contains("table: 'communities'"), isTrue);
      expect(detailPage.contains('_subscribeCommunity()'), isTrue);
      expect(detailPage.contains('_communityChannel?.unsubscribe()'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Aufgabe C: Sichtbarkeit mit Rückfrage
  // ───────────────────────────────────────────────────────────────────────

  group('Sichtbarkeit', () {
    test('auf privat: die Rückfrage nennt die Folge für alte Links', () {
      // Entscheidung Vucko vom 23.08.2026, bindend.
      final frage = CommunitySettingsTexte.sichtbarkeitsFrage(false);
      expect(frage.titel.toLowerCase(), contains('privat'));
      expect(frage.text.toLowerCase(), contains('beitrittsanfrage'));
      expect(
        frage.text.toLowerCase(),
        contains('mitglieder bleiben'),
        reason: 'Bestehende Mitglieder behalten ihren Zugang. Das muss dabei '
            'stehen, sonst traut sich niemand umzuschalten.',
      );
    });

    test('auf öffentlich: die Rückfrage sagt, dass jeder ohne Code reinkommt', () {
      final frage = CommunitySettingsTexte.sichtbarkeitsFrage(true);
      expect(frage.titel.toLowerCase(), contains('öffentlich'));
      expect(frage.text.toLowerCase(), contains('ohne code'));
    });

    test('es gibt keinen Weg mehr, ohne Rückfrage umzuschalten', () {
      // Gemessen: community_chat_detail_page.dart Zeile 890 schaltete direkt
      // um. Ein Fehltipp im Drei-Punkte-Menü machte eine private Community
      // sofort öffentlich.
      expect(detailPage.contains('_toggleVisibility'), isFalse);
      expect(detailPage.contains('_toggleOwnerOnlyMessages'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Beitritt per Code: fünf Ausgänge
  // ───────────────────────────────────────────────────────────────────────

  group('Beitritt per Einladungscode', () {
    CommunityJoinResult bau(String status) => CommunityJoinResult.fromJson({
      'community_id': 'abc',
      'name': 'Nightriders',
      'is_public': status == 'joined',
      'status': status,
    });

    test('jeder Status wird richtig gelesen', () {
      expect(bau('joined').status, CommunityJoinStatus.joined);
      expect(bau('already_member').status, CommunityJoinStatus.alreadyMember);
      expect(bau('request_created').status, CommunityJoinStatus.requestCreated);
      expect(bau('request_pending').status, CommunityJoinStatus.requestPending);
      expect(
        bau('request_rejected').status,
        CommunityJoinStatus.requestRejected,
      );
    });

    test('nur echte Mitgliedschaft öffnet den Chat', () {
      // Sonst landet der Fragende in einer leeren, nicht lesbaren Seite,
      // weil die Leseregel members_read_community_messages ihn ausschließt.
      expect(bau('joined').opensCommunity, isTrue);
      expect(bau('already_member').opensCommunity, isTrue);
      expect(bau('request_created').opensCommunity, isFalse);
      expect(bau('request_pending').opensCommunity, isFalse);
      expect(bau('request_rejected').opensCommunity, isFalse);
    });

    test('jeder Ausgang hat einen eigenen, verständlichen Satz', () {
      final saetze = <String>{};
      for (final status in [
        'joined',
        'already_member',
        'request_created',
        'request_pending',
        'request_rejected',
      ]) {
        final satz = bau(status).userMessage;
        expect(satz.trim(), isNotEmpty);
        expect(satz.contains('Nightriders'), isTrue);
        saetze.add(satz);
      }
      expect(saetze.length, 5, reason: 'Kein Satz darf doppelt vorkommen.');
    });

    test('ohne Namen bleibt der Satz lesbar', () {
      final ergebnis = CommunityJoinResult.fromJson({
        'community_id': 'abc',
        'status': 'request_created',
      });
      expect(ergebnis.userMessage, contains('der Community'));
      expect(ergebnis.userMessage.contains('„"'), isFalse);
    });

    test('die Übersicht wertet das Ergebnis aus statt blind zu öffnen', () {
      expect(chatsTab.contains('joinCommunityByCode'), isTrue);
      expect(chatsTab.contains('result.opensCommunity'), isTrue);
      expect(chatsTab.contains('result.userMessage'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Auffindbarkeit: die Einstellungen hängen an ZWEI Orten
  // ───────────────────────────────────────────────────────────────────────

  group('Auffindbarkeit der Einstellungen', () {
    test('sie sind aus dem Chat UND aus der Übersicht erreichbar', () {
      // Der eigentliche Auftrag: Schreibmodus und Sichtbarkeit gab es schon,
      // sie lagen nur im Drei-Punkte-Menü innerhalb des Chats. Vucko hat sie
      // nicht gefunden und hielt sie für fehlend.
      expect(detailPage.contains('CommunitySettingsPage('), isTrue);
      expect(chatsTab.contains('CommunitySettingsPage('), isTrue);
    });

    test('nur Admins sehen den Eintrag, und die Seite selbst sperrt auch', () {
      // Doppelt abgesichert: der Menue-Eintrag erscheint nur fuer Admins, UND
      // die Seite selbst zeigt einen ehrlichen Satz statt leerer Schalter,
      // falls jemand ueber einen alten Verweis dort landet oder die Rolle
      // zwischendurch entzogen wurde. Serverseitig gilt ohnehin
      // leaders_update_communities mit is_community_admin.
      final seite = File(
        'lib/presentation/pages/community_settings_page.dart',
      ).readAsStringSync();
      expect(seite.contains('!_amAdmin'), isTrue);
      expect(seite.contains('_buildNoAccess()'), isTrue);
      expect(CommunitySettingsTexte.keinZugriff.toLowerCase(), contains('admin'));

      final menue = chatsTab.substring(
        chatsTab.indexOf('Widget _buildCommunityMenu('),
      );
      final eintrag = menue.indexOf("value: 'settings'");
      expect(eintrag, isNot(-1));
      expect(
        menue.substring(0, eintrag).contains('if (isAdmin)'),
        isTrue,
        reason: 'Der Eintrag haengt an der Admin-Rolle.',
      );

      final chatMenue = detailPage.substring(
        detailPage.indexOf('PopupMenuButton<String>('),
      );
      final chatEintrag = chatMenue.indexOf("value: 'settings'");
      expect(chatEintrag, isNot(-1));
      expect(
        chatMenue.substring(0, chatEintrag).contains('if (_amAdmin)'),
        isTrue,
      );
    });

    test('die Seite bündelt alle sieben Punkte', () {
      final seite = File(
        'lib/presentation/pages/community_settings_page.dart',
      ).readAsStringSync();
      for (final punkt in [
        'Bild der Community',
        'Name und Beschreibung',
        'Wer darf schreiben',
        'Sichtbarkeit',
        'Einladungscode',
        'Mitglieder',
        'Community löschen',
      ]) {
        expect(
          seite.contains(punkt),
          isTrue,
          reason: 'Auf der Einstellungs-Seite fehlt: $punkt',
        );
      }
    });

    test('Name und Beschreibung sind überhaupt änderbar', () {
      // Gemessen am 23.08.2026: es gab im ganzen Repo keinen einzigen Aufruf,
      // der communities.name oder .description aktualisiert.
      expect(
        service.contains('static Future<void> updateCommunityProfile('),
        isTrue,
      );
    });

    test('Beitrittsanfragen haben eine Oberfläche', () {
      // Ohne sie versanden die Anfragen, die seit heute entstehen.
      expect(service.contains("'get_community_join_requests'"), isTrue);
      expect(service.contains("'accept_community_join_request'"), isTrue);
      expect(service.contains("'reject_community_join_request'"), isTrue);
      final seite = File(
        'lib/presentation/pages/community_settings_page.dart',
      ).readAsStringSync();
      expect(seite.contains('Beitrittsanfragen'), isTrue);
      expect(seite.contains('_answerJoinRequest'), isTrue);
    });

    test('offene Anfragen fallen dem Admin im Chat auf', () {
      // Eine Anfrage schreibt KEINE Benachrichtigung: join_community_with_code_v2
      // legt nur die Zeile an. Ohne einen Hinweis dort, wo der Admin ohnehin
      // ist, muesste er von sich aus in die Einstellungen schauen. Genau so
      // versanden Anfragen.
      expect(detailPage.contains('_loadOpenJoinRequests'), isTrue);
      expect(detailPage.contains('Beitrittsanfrage'), isTrue);
      expect(
        detailPage.contains("'1 Beitrittsanfrage'"),
        isTrue,
        reason: 'Einzahl und Mehrzahl muessen getrennt sein.',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Fehlertexte
  // ───────────────────────────────────────────────────────────────────────

  group('Fehlertexte der Einstellungs-Seite', () {
    test('ein benannter Fehler kommt durch', () {
      const fehler = CommunityChatServiceException(
        CommunityChatService.writeLockedMessage,
        code: CommunityChatService.writeLockedCode,
      );
      expect(
        CommunitySettingsTexte.lesbarerFehler(fehler, 'Ersatz'),
        CommunityChatService.writeLockedMessage,
      );
    });

    test('roher Datenbanktext wird durch den Ersatz ausgetauscht', () {
      for (final roh in [
        'PostgrestException(message: new row violates row-level security policy)',
        'permission denied for table communities',
        'duplicate key value violates unique constraint',
      ]) {
        expect(
          CommunitySettingsTexte.lesbarerFehler(Exception(roh), 'Ersatz'),
          'Ersatz',
          reason: 'Der Nutzer darf das nie lesen: $roh',
        );
      }
    });

    test('ein eigener deutscher Satz bleibt stehen', () {
      const fehler = CommunityChatServiceException(
        'Nur Admins können das Bild der Community ändern.',
      );
      expect(
        CommunitySettingsTexte.lesbarerFehler(fehler, 'Ersatz'),
        'Nur Admins können das Bild der Community ändern.',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // Harte Hausregeln: keine Gedankenstriche, echte Umlaute
  // ───────────────────────────────────────────────────────────────────────

  group('Texthygiene', () {
    /// Alle Sätze, die ein Nutzer tatsächlich zu sehen bekommt.
    List<String> alleTexte() {
      final texte = <String>[
        CommunityChatService.writeLockedMessage,
        CommunityChatService.writeModeAdminsTitle,
        CommunityChatService.writeModeEveryoneTitle,
        CommunityChatService.writeModeExplanation,
        CommunitySettingsTexte.keinZugriff,
        CommunitySettingsTexte.sichtbarkeitErklaerung,
        CommunityImageRules.zuGross,
        CommunityImageRules.falschesFormat,
        CommunityImageRules.leer,
        CommunityImageRules.hochladenFehlgeschlagen,
        CommunityImageRules.keinKameraZugriff,
        CommunityImageRules.keinGalerieZugriff,
      ];
      for (final oeffentlich in [true, false]) {
        final frage = CommunitySettingsTexte.sichtbarkeitsFrage(oeffentlich);
        texte.addAll([frage.titel, frage.text, frage.knopf, frage.erfolg]);
      }
      for (final status in [
        'joined',
        'already_member',
        'request_created',
        'request_pending',
        'request_rejected',
      ]) {
        texte.add(
          CommunityJoinResult.fromJson({
            'community_id': 'x',
            'name': 'Testcrew',
            'status': status,
          }).userMessage,
        );
      }
      return texte;
    }

    test('kein Gedankenstrich in einem Nutzertext', () {
      for (final text in alleTexte()) {
        expect(
          text.contains('—') || text.contains('–'),
          isFalse,
          reason: 'Gedankenstrich gefunden: $text',
        );
      }
    });

    test('Umlaute sind ausgeschrieben, nicht ae/oe/ue/ss', () {
      // Wiederkehrender Beschwerdepunkt von Vucko.
      final verdaechtig = RegExp(
        r'\b(fuer|ueber|koennen|koenne|moeglich|oeffentlich|privat'
        r'|aendern|loeschen|zurueck|muss(en)?te|groess|schliess|gross)\w*',
        caseSensitive: false,
      );
      for (final text in alleTexte()) {
        final treffer = verdaechtig
            .allMatches(text)
            .map((m) => m.group(0)!)
            .where(
              // „privat" und „gross" sind hier nur als Anker im Muster, echte
              // Wörter mit Umlaut sind es nicht.
              (wort) => RegExp(
                r'^(fuer|ueber|koenn|moeglich|oeffentlich|aendern|loeschen'
                r'|zurueck|groess|schliess)',
                caseSensitive: false,
              ).hasMatch(wort),
            )
            .toList();
        expect(treffer, isEmpty, reason: 'Umlaut-Ersatz in: $text');
      }
    });

    test('kein Text endet mitten im Satz oder ist leer', () {
      for (final text in alleTexte()) {
        expect(text.trim(), isNotEmpty);
        expect(text.trim(), isNot(endsWith(',')));
      }
    });
  });
}
