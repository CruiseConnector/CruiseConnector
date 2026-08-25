import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/community_chat_service.dart';
import 'package:cruise_connect/presentation/pages/community_settings_page.dart';

/// 2026-08-25 (Auftrag Vucko). Meldung: „Der Admin einer BESTEHENDEN Community
/// kann ihre Region nirgends ändern, sie wird nur beim Erstellen gesetzt."
/// Antwort wörtlich: „ja bitte der admin soll es bestimmen".
///
/// Diese Tests bewachen genau das, was ohne zwei Konten und ohne Gerät prüfbar
/// ist: dass die Werte überhaupt geladen werden, dass es Wege zum Ändern gibt,
/// dass eine Ablehnung den ALTEN Wert zurückholt, und die Entscheidung zum
/// Regionswechsel bei bestehenden Mitgliedern.
///
/// GEMESSEN am 25.08.2026 in der Produktivdatenbank, damit hier nichts geraten
/// ist: `authenticated` hat auf `communities` spaltenweise `update` auf
/// `fahrzeugart` UND `region_code`. In einer Transaktion mit Rücknahme geprüft:
/// als Besitzer geht der Update durch, als Mitglied ohne Admin-Rolle kommen
/// NULL Zeilen zurück, ohne Fehler. Eine Migration war deshalb nicht nötig,
/// aber `.select('id')` ist Pflicht.
void main() {
  late String service;
  late String seite;
  late String chatsTab;

  String ohneKommentare(String quelle) => quelle
      .split('\n')
      .where((zeile) {
        final t = zeile.trimLeft();
        return !t.startsWith('//') && !t.startsWith('///');
      })
      .join('\n');

  String abschnitt(String quelle, String von, String bis) {
    final start = quelle.indexOf(von);
    expect(start, isNot(-1), reason: 'Nicht gefunden: $von');
    final ende = quelle.indexOf(bis, start);
    expect(ende, isNot(-1), reason: 'Nicht gefunden: $bis (nach $von)');
    return quelle.substring(start, ende);
  }

  setUpAll(() {
    service = File(
      'lib/data/services/community_chat_service.dart',
    ).readAsStringSync();
    seite = File(
      'lib/presentation/pages/community_settings_page.dart',
    ).readAsStringSync();
    chatsTab = File(
      'lib/presentation/pages/community_chats_tab.dart',
    ).readAsStringSync();
  });

  // ───────────────────────────────────────────────────────────────────────
  // 1. Die Werte müssen überhaupt erst ankommen
  // ───────────────────────────────────────────────────────────────────────

  group('Laden', () {
    /// Nur die EIGENEN Spalten von public.communities, ohne die angehängten
    /// Joins. Sonst zählt ein Treffer aus `profiles:owner_id(...)` mit.
    String eigeneSpalten(String name) {
      final start = service.indexOf('static const String $name =');
      expect(start, isNot(-1), reason: 'Konstante fehlt: $name');
      final ganz = service.substring(start, service.indexOf(';', start));
      final join = ganz.indexOf('community_members(');
      expect(join, isNot(-1), reason: 'Join fehlt in $name');
      return ganz.substring(0, join);
    }

    test('fahrzeugart und region_code stehen in _communitySelect', () {
      // OHNE das hier ist die ganze Aufgabe wirkungslos: die Einstellungs-
      // Seite lädt ihre Zeile über fetchCommunity. Fehlten die Spalten,
      // stünde dort nach dem ersten Laden „Für alle, überregional" — egal was
      // in der Datenbank steht — und ein Speichern überschriebe den echten
      // Wert mit der Anzeige.
      final spalten = eigeneSpalten('_communitySelect');
      expect(spalten.contains('fahrzeugart'), isTrue);
      expect(spalten.contains('region_code'), isTrue);
    });

    test('_legacyCommunitySelect bleibt ohne die neuen Spalten', () {
      // Diese Liste läuft nur auf einem Datenbankstand VOR dem 24.08., dort
      // gibt es die Spalten nicht. Zöge sie mit, stürbe der Rückfall.
      final legacy = eigeneSpalten('_legacyCommunitySelect');
      expect(legacy.contains('fahrzeugart'), isFalse);
      expect(legacy.contains('region_code'), isFalse);
    });

    test('regionCodeVon liest die Spalte und behandelt Leeres als überregional', () {
      expect(CommunityChatService.regionCodeVon(null), isNull);
      expect(CommunityChatService.regionCodeVon(const {}), isNull);
      expect(CommunityChatService.regionCodeVon(const {'region_code': ''}), isNull);
      expect(
        CommunityChatService.regionCodeVon(const {'region_code': '   '}),
        isNull,
      );
      expect(
        CommunityChatService.regionCodeVon(const {'region_code': 'AT-8'}),
        'AT-8',
      );
    });

    test('regionNameFuer findet den Namen und zeigt sonst den Schlüssel', () {
      const regionen = [
        CommunityRegion(
          code: 'AT-8',
          landCode: 'AT',
          name: 'Vorarlberg',
          istLand: false,
        ),
      ];
      expect(CommunityChatService.regionNameFuer(regionen, null), isNull);
      expect(CommunityChatService.regionNameFuer(regionen, ''), isNull);
      expect(
        CommunityChatService.regionNameFuer(regionen, 'AT-8'),
        'Vorarlberg',
      );
      expect(
        CommunityChatService.regionNameFuer(const [], 'AT-8'),
        'AT-8',
        reason: 'Ohne geladene Liste ist der Schlüssel ehrlicher als ein '
            'leeres Feld, das behauptet, es sei keine Region gesetzt.',
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 2. Es muss einen Weg zum Ändern geben, und er muss ehrlich scheitern
  // ───────────────────────────────────────────────────────────────────────

  group('Schreiben', () {
    test('es gibt je einen Dienst für Fahrzeugart und Region', () {
      expect(
        service.contains('static Future<void> setCommunityFahrzeugart('),
        isTrue,
      );
      expect(
        service.contains('static Future<void> setCommunityRegion('),
        isTrue,
      );
    });

    test('die stille Ablehnung wird zum benannten Fehler', () {
      // Gemessen: als Nicht-Admin kommen NULL Zeilen zurück, OHNE Fehler.
      // Ohne .select('id') sähe das aus wie ein Erfolg.
      final block = abschnitt(
        service,
        'static Future<void> _setzeAusrichtung(',
        'static Future<void> updateCommunityProfile(',
      );
      expect(block.contains(".select('id')"), isTrue);
      expect(block.contains('(rows as List).isEmpty'), isTrue);
      expect(block.contains('CommunityChatServiceException'), isTrue);
      expect(
        block.contains('_isMissingColumn'),
        isTrue,
        reason: 'Eine App auf einer Datenbank vor dem 24.08. darf keinen '
            'rohen Datenbanktext zeigen.',
      );
    });

    test('nur der Admin kommt an die Seite, ein Moderator nicht', () {
      // is_community_owner liefert auch für Moderatoren true, die
      // Zeilenregel leaders_update_communities verlangt aber
      // is_community_admin, und das ist ausschliesslich owner. Die Seite
      // bleibt zeichengleich dazu.
      expect(
        ohneKommentare(seite).contains("bool get _amAdmin => _myRole == 'owner';"),
        isTrue,
      );
      final aufbau = abschnitt(seite, 'body: _loading', '_buildDangerSection()');
      expect(aufbau.contains('!_amAdmin'), isTrue);
      expect(aufbau.contains('_buildVisibilitySection()'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 3. Die Oberfläche: dieselben Bedienelemente, kein zweiter Regler
  // ───────────────────────────────────────────────────────────────────────

  group('Oberfläche', () {
    test('die Einstellungen benutzen die fertigen Bedienelemente', () {
      final ohne = ohneKommentare(seite);
      expect(ohne.contains('CommunityFahrzeugartChips('), isTrue);
      expect(ohne.contains('CommunityRegionBlatt.zeigen('), isTrue);
      expect(
        ohne.contains('community/community_filter_leiste.dart'),
        isTrue,
        reason: 'Ein zweiter, eigener Regler würde vom Erstellen-Blatt '
            'wegdriften.',
      );
    });

    test('beides sitzt im Abschnitt Sichtbarkeit, nicht in einem neuen', () {
      final block = abschnitt(
        seite,
        'Widget _buildVisibilitySection()',
        'Widget _buildFeldUeberschrift(',
      );
      expect(block.contains('CommunityFahrzeugartChips('), isTrue);
      expect(block.contains('_waehleRegion'), isTrue);
    });

    test('Erstellen und Einstellungen zeigen dieselbe Beschriftung', () {
      // Sonst heisst derselbe Zustand an zwei Stellen anders.
      expect(chatsTab.contains("alleBeschriftung: 'Für alle'"), isTrue);
      expect(seite.contains("alleBeschriftung: 'Für alle'"), isTrue);
      expect(
        seite.contains("alleBeschriftung: 'Keine Angabe (überregional)'"),
        isTrue,
      );
    });

    test('der Admin bekommt dieselbe Beschneidung nach Land', () {
      final ohne = ohneKommentare(seite);
      expect(ohne.contains('CommunityStandortLand.instance'), isTrue);
      expect(ohne.contains('landCode: _standortLand.landCode'), isTrue);
      expect(ohne.contains('landQuelle: _standortLand.quelle'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 4. Rückmeldung: sofort sichtbar, bei Ablehnung zurück auf den alten Wert
  // ───────────────────────────────────────────────────────────────────────

  group('Optimistic UI', () {
    test('die Fahrzeugart steht sofort da und kommt bei Fehler zurück', () {
      final block = abschnitt(
        seite,
        'Future<void> _setFahrzeugart(',
        'Future<void> _waehleRegion(',
      );
      expect(block.contains('final vorher = _fahrzeugart;'), isTrue);
      final catchStelle = block.indexOf('} catch (e) {');
      expect(catchStelle, isNot(-1));
      expect(
        block.substring(0, catchStelle).contains("'fahrzeugart': neu.spaltenWert"),
        isTrue,
        reason: 'Der neue Wert muss VOR dem Serveraufruf stehen.',
      );
      expect(
        block.substring(catchStelle).contains("'fahrzeugart': vorher.spaltenWert"),
        isTrue,
        reason: 'Lehnt der Server ab, muss der alte Wert zurück.',
      );
    });

    test('die Region steht sofort da und kommt bei Fehler zurück', () {
      final block = abschnitt(
        seite,
        'Future<void> _waehleRegion(',
        'Future<bool> _frageNach(',
      );
      expect(block.contains('final vorher = _regionCode;'), isTrue);
      final catchStelle = block.indexOf('} catch (e) {');
      expect(catchStelle, isNot(-1));
      expect(
        block.substring(0, catchStelle).contains("'region_code': neu"),
        isTrue,
      );
      expect(
        block.substring(catchStelle).contains("'region_code': vorher"),
        isTrue,
      );
    });

    test('die Übersicht lädt danach neu, der alte Wert bleibt nicht stehen', () {
      // Die Kachel und der Filter lesen fahrzeugart und region_code aus der
      // RPC-Zeile. Ohne _changed meldet die Seite „unchanged" und die
      // Übersicht zeigt weiter den alten Wert.
      for (final block in [
        abschnitt(seite, 'Future<void> _setFahrzeugart(', 'Future<void> _waehleRegion('),
        abschnitt(seite, 'Future<void> _waehleRegion(', 'Future<bool> _frageNach('),
      ]) {
        expect(block.contains('_changed = true;'), isTrue);
      }
      final auf = abschnitt(chatsTab, 'Future<void> _openSettings(', 'void _showMembers(');
      expect(auf.contains('CommunitySettingsResult.changed'), isTrue);
      expect(auf.contains('await _load();'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 5. Der Fall, den Vucko nicht genannt hat: die Community wechselt die
  //    Region, und es sind schon Leute drin
  // ───────────────────────────────────────────────────────────────────────

  group('Reichweite und bestehende Mitglieder', () {
    const regionen = [
      CommunityRegion(
        code: 'AT',
        landCode: 'AT',
        name: 'Österreich',
        istLand: true,
        sortierung: 0,
      ),
      CommunityRegion(
        code: 'AT-8',
        landCode: 'AT',
        name: 'Vorarlberg',
        istLand: false,
      ),
      CommunityRegion(
        code: 'AT-6',
        landCode: 'AT',
        name: 'Steiermark',
        istLand: false,
      ),
      CommunityRegion(
        code: 'DE-BY',
        landCode: 'DE',
        name: 'Bayern',
        istLand: false,
      ),
    ];

    test('Aufmachen fragt nicht, Verengen schon', () {
      expect(
        CommunityReichweite.fahrzeugartVerengt(
          vorher: CommunityFahrzeugart.auto,
          nachher: CommunityFahrzeugart.alle,
        ),
        isFalse,
      );
      expect(
        CommunityReichweite.fahrzeugartVerengt(
          vorher: CommunityFahrzeugart.alle,
          nachher: CommunityFahrzeugart.auto,
        ),
        isTrue,
      );
      expect(
        CommunityReichweite.fahrzeugartVerengt(
          vorher: CommunityFahrzeugart.auto,
          nachher: CommunityFahrzeugart.motorrad,
        ),
        isTrue,
        reason: 'Autofahrer verlieren die Community aus ihrem Filter.',
      );
    });

    test('überregional ist nie eine Verengung, eine Region schon', () {
      expect(
        CommunityReichweite.regionVerengt(
          vorher: 'AT-8',
          nachher: null,
          regionen: regionen,
        ),
        isFalse,
      );
      expect(
        CommunityReichweite.regionVerengt(
          vorher: null,
          nachher: 'AT-8',
          regionen: regionen,
        ),
        isTrue,
      );
      expect(
        CommunityReichweite.regionVerengt(
          vorher: 'AT-8',
          nachher: 'AT-6',
          regionen: regionen,
        ),
        isTrue,
      );
    });

    test('vom Bundesland aufs ganze Land ist ein Aufmachen', () {
      // Die Datenbank gibt das vor: eine Community auf `AT` erscheint im
      // Filter JEDES österreichischen Bundeslandes
      // (get_communities_gefiltert, Zweig `c.region_code = v_region_land`).
      // Eine Rückfrage wäre hier schlicht falsch.
      expect(
        CommunityReichweite.regionVerengt(
          vorher: 'AT-8',
          nachher: 'AT',
          regionen: regionen,
        ),
        isFalse,
      );
      expect(
        CommunityReichweite.regionVerengt(
          vorher: 'DE-BY',
          nachher: 'AT',
          regionen: regionen,
        ),
        isTrue,
        reason: 'Bayern nach Österreich ist ein Umzug, kein Aufmachen.',
      );
    });

    test('nur bei einer Verengung kommt eine Rückfrage', () {
      expect(
        CommunityReichweite.fahrzeugartFrage(
          vorher: CommunityFahrzeugart.auto,
          nachher: CommunityFahrzeugart.alle,
          mitglieder: 19,
        ),
        isNull,
      );
      expect(
        CommunityReichweite.regionFrage(
          vorher: 'AT-8',
          nachher: null,
          regionen: regionen,
          mitglieder: 19,
        ),
        isNull,
      );
      expect(
        CommunityReichweite.regionFrage(
          vorher: null,
          nachher: 'AT-8',
          regionen: regionen,
          mitglieder: 19,
        ),
        isNotNull,
      );
    });

    test('die Rückfrage sagt, dass alle drin bleiben, und wer es sagen muss', () {
      final frage = CommunityReichweite.regionFrage(
        vorher: null,
        nachher: 'AT-8',
        regionen: regionen,
        mitglieder: 19,
      )!;
      expect(frage.titel.contains('Vorarlberg'), isTrue);
      expect(frage.text.contains('Vorarlberg'), isTrue);
      // Die Entscheidung: niemand wird entfernt, niemand muss neu beitreten.
      expect(frage.text.contains('19 Mitglieder'), isTrue);
      expect(frage.text.contains('bleiben alle dabei'), isTrue);
      expect(frage.text.contains('neu beitreten'), isTrue);
      // Und die Ehrlichkeit: es gibt keine automatische Meldung an sie.
      expect(frage.text.contains('Chat'), isTrue);
    });

    test('ohne weitere Mitglieder steht kein leerer Satz über sie da', () {
      final frage = CommunityReichweite.fahrzeugartFrage(
        vorher: CommunityFahrzeugart.alle,
        nachher: CommunityFahrzeugart.motorrad,
        mitglieder: 1,
      )!;
      expect(frage.text.contains('1 Mitglieder'), isFalse);
      expect(frage.text.contains('Mitgliedschaft ändert sich nichts'), isTrue);
    });

    test('jeder Ausgang hat eine eigene Erfolgsmeldung', () {
      expect(
        CommunityReichweite.fahrzeugartErfolg(CommunityFahrzeugart.auto),
        contains('Autofahrer'),
      );
      expect(
        CommunityReichweite.fahrzeugartErfolg(CommunityFahrzeugart.motorrad),
        contains('Motorradfahrer'),
      );
      expect(
        CommunityReichweite.fahrzeugartErfolg(CommunityFahrzeugart.alle),
        contains('alle'),
      );
      expect(
        CommunityReichweite.regionErfolg(null),
        contains('überregional'),
      );
      expect(
        CommunityReichweite.regionErfolg('Vorarlberg'),
        contains('Vorarlberg'),
      );
    });

    test('privat bekommt einen eigenen Hinweis statt einer Halbwahrheit', () {
      // Bei einer privaten Community wirkt die Region nicht im Entdecken.
      // Stünde dort derselbe Satz wie bei öffentlich, wäre er schlicht falsch.
      expect(
        CommunityReichweite.regionHinweisPrivat ==
            CommunityReichweite.regionHinweisOeffentlich,
        isFalse,
      );
      expect(CommunityReichweite.regionHinweisPrivat.contains('Privat'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  // 6. Texthygiene, wie im bestehenden Test der Einstellungs-Seite
  // ───────────────────────────────────────────────────────────────────────

  group('Texthygiene', () {
    const regionen = [
      CommunityRegion(
        code: 'AT-8',
        landCode: 'AT',
        name: 'Vorarlberg',
        istLand: false,
      ),
    ];

    List<String> alleTexte() {
      final texte = <String>[
        CommunityReichweite.regionHinweisOeffentlich,
        CommunityReichweite.regionHinweisPrivat,
        CommunityReichweite.mitgliederSatz(0),
        CommunityReichweite.mitgliederSatz(19),
        CommunityReichweite.regionErfolg(null),
        CommunityReichweite.regionErfolg('Vorarlberg'),
      ];
      for (final art in CommunityFahrzeugart.values) {
        texte.add(CommunityReichweite.fahrzeugartErfolg(art));
        final frage = CommunityReichweite.fahrzeugartFrage(
          vorher: CommunityFahrzeugart.alle,
          nachher: art,
          mitglieder: 19,
        );
        if (frage != null) {
          texte.addAll([frage.titel, frage.text, frage.knopf, frage.erfolg]);
        }
      }
      final regionFrage = CommunityReichweite.regionFrage(
        vorher: null,
        nachher: 'AT-8',
        regionen: regionen,
        mitglieder: 19,
      )!;
      texte.addAll([
        regionFrage.titel,
        regionFrage.text,
        regionFrage.knopf,
        regionFrage.erfolg,
      ]);
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
      final verdaechtig = RegExp(
        r'\b(fuer|ueber|koenn|moeglich|oeffentlich|aendern|loeschen|zurueck'
        r'|groess|schliess)\w*',
        caseSensitive: false,
      );
      for (final text in alleTexte()) {
        expect(
          verdaechtig.allMatches(text).map((m) => m.group(0)!).toList(),
          isEmpty,
          reason: 'Umlaut-Ersatz in: $text',
        );
      }
    });

    test('kein Text ist leer oder endet mitten im Satz', () {
      for (final text in alleTexte()) {
        expect(text.trim(), isNotEmpty);
        expect(text.trim(), isNot(endsWith(',')));
      }
    });
  });
}
