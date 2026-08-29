import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-25 (vucko): „schau das in keiner erklaerung oder in irgendeinem
/// beispiel oder sonstigem irgendwo ein bindestrich zu finden ist bitte das
/// ist mir vorhin aufgefallen bei der taeglichen benachrichtigung."
///
/// Das war das ZWEITE Mal. Am 12.08. stand schon einmal dasselbe im Auftrag
/// („schau auch noch, dass das Update-Popup aeoeue verwendet und im Satz keine
/// Bindestriche hat"), damals nur fuer app_changelog.dart. Danach sind wieder
/// neue Striche in die App gewandert, weil nichts sie aufgehalten hat.
/// Deshalb dieser Test: Er ist die eigentliche Loesung, nicht die Aufraeum-
/// aktion von heute.
///
/// GEMESSEN am 25.08. vor der Aufraeumaktion: 254 Nutzertexte in 60 Dateien
/// mit einem Binde- oder Gedankenstrich (Protokollzeilen schon abgezogen).
///
/// WAS DER TEST PRUEFT
/// Jede Zeichenkette in lib/, die am Bildschirm landen kann. Fuer jeden Fund
/// nennt er Datei, Zeile und Text, damit man ihn sofort findet.
///
/// WAS ER BEWUSST NICHT PRUEFT (sonst wird er zum Nervtest, den man abschaltet)
///   * Kommentare und Doku im Code. Dort ist der Bindestrich Fachsprache.
///   * Protokollzeilen (debugPrint und Verwandte). Die sieht nur der Entwickler.
///   * Entwicklertexte an Parametern wie `debugMessage:`.
///   * Rohstrings (r'...'), regulaere Ausdruecke, Kennungen, Pfade, Adressen.
///   * Striche, die allein stehen: „—" als Platzhalter fuer „kein Wert" und
///     „12:00–18:00" als Bis-Strich sind Typografie, kein Satz.
///
/// WENN DER TEST ROT IST
/// Den Satz UMSCHREIBEN, nicht den Strich durch ein anderes Zeichen ersetzen.
/// „Entdecken-Bereich" wird „Bereich Entdecken", „Community-Name" wird „Name
/// der Community". Geht es nicht ohne, dass es holpert oder falsch wird, gehoert
/// das Wort in [erlaubteWoerter] weiter unten, MIT Begruendung.
void main() {
  // ── Was ein Strich ist ────────────────────────────────────────────────────
  // U+002D Bindestrich und alles, was auf dem Bildschirm wie ein laengerer
  // Strich aussieht: Gedankenstrich, Bis-Strich, Minuszeichen.
  const bindestrich = '-';
  const langeStriche = '‐‑‒–—―−';

  // ── Ausnahmeliste: Woerter, die ihren Strich behalten duerfen ─────────────
  // Jeder Eintrag braucht eine Begruendung. Ohne Begruendung kein Eintrag,
  // sonst waechst die Liste, bis der Test nichts mehr findet.
  const erlaubteWoerter = <String, String>{
    'E-Mail':
        'Duden. Jede andere Schreibung („EMail", „Email") ist schlicht falsch. '
            'Gilt auch fuer Zusammensetzungen wie E-Mail-Adresse.',
    'Harley-Davidson': 'Eigenname einer Marke.',
    'Mercedes-Benz': 'Eigenname einer Marke.',
    'Rolls-Royce': 'Eigenname einer Marke.',
    'Content-Type': 'Name einer HTTP-Kopfzeile, technisch festgelegt.',
    'User-Agent': 'Name einer HTTP-Kopfzeile, technisch festgelegt.',
    'Community-Stimme':
        'Name eines Abzeichens aus lib/domain/models/badge.dart. Wird der '
            'Name dort geaendert, gehoert er hier mit geaendert.',
  };

  // Kuerzel und Codes: „CC-XXXXXX" ist das echte Format eines Gruppencodes,
  // „AT-AUT" und „de-DE" sind Laender- und Sprachkuerzel. Der Strich gehoert
  // zum Datenformat, nicht zum Satz.
  final codeMuster = <RegExp>[
    RegExp(r'\b[A-Z]{2,4}-[A-Z0-9]{2,10}\b'),
    RegExp(r'\b[a-z]{2}-[A-Z]{2}\b'),
  ];

  // ── Ausnahmeliste: ganze Dateien ─────────────────────────────────────────
  const dateiAusnahmen = <String, String>{
    'lib/l10n/app_localizations_en.dart':
        'Englische Oberflaeche. Dort ist der Bindestrich korrekte '
            'Rechtschreibung („sign-in", „6-digit code"), kein Fehler.',
    // NACHZUZIEHEN (Stand 25.08.): Diese vier Dateien gehoerten am selben Tag
    // einem parallelen Auftrag (Starterpaket und Abzeichen) und durften nicht
    // angefasst werden. Sobald der durch ist, hier streichen und die Striche
    // in den vier Dateien entfernen.
    'lib/presentation/widgets/starter_paket_karte.dart':
        'NACHZUZIEHEN: gehoerte am 25.08. dem Auftrag Starterpaket.',
    'lib/domain/models/badge.dart':
        'NACHZUZIEHEN: gehoerte am 25.08. dem Auftrag Starterpaket.',
    'lib/data/services/starter_aufgaben_service.dart':
        'NACHZUZIEHEN: gehoerte am 25.08. dem Auftrag Starterpaket.',
    'lib/data/services/gamification_service.dart':
        'NACHZUZIEHEN: gehoerte am 25.08. dem Auftrag Starterpaket.',
  };

  // ── Ab hier die Mechanik ─────────────────────────────────────────────────

  /// Ein Textstueck aus dem Quelltext, das am Bildschirm landen kann.
  final funde = <_Fund>[];

  final wurzel = Directory('lib');
  test('lib/ ist vom Testlauf aus erreichbar', () {
    expect(
      wurzel.existsSync(),
      isTrue,
      reason: 'Der Test muss aus dem Projektwurzelverzeichnis laufen.',
    );
  });

  final dateien = wurzel
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList()
    ..sort();

  for (final pfad in dateien) {
    if (dateiAusnahmen.containsKey(pfad)) continue;
    final quelle = File(pfad).readAsStringSync();
    for (final literal in _literale(quelle)) {
      if (literal.roh) continue; // r'...' ist nie Bildschirmtext
      final text = literal.text;
      if (_istTechnisch(text)) continue;
      if (_nurStrich(text, bindestrich, langeStriche)) continue;

      var rest = text;
      for (final wort in erlaubteWoerter.keys) {
        rest = rest.replaceAll(wort, ' ');
      }
      for (final muster in codeMuster) {
        rest = rest.replaceAll(muster, ' ');
      }

      final lang = langeStriche.split('').firstWhere(
            rest.contains,
            orElse: () => '',
          );
      final bind = _bindestrichImWort(rest);
      if (lang.isEmpty && !bind) continue;

      funde.add(
        _Fund(
          datei: pfad,
          zeile: literal.zeile,
          art: lang.isNotEmpty ? 'Gedankenstrich' : 'Bindestrich',
          text: text,
        ),
      );
    }
  }

  test('kein Strich in Texten, die der Nutzer sieht', () {
    if (funde.isEmpty) return;
    final zeilen = funde
        .map((f) => '  ${f.datei}:${f.zeile}  [${f.art}]  „${f.text}"')
        .join('\n');
    fail(
      '${funde.length} Nutzertext(e) mit einem Strich:\n$zeilen\n\n'
      'Bitte den SATZ umschreiben, nicht den Strich ersetzen. Beispiele:\n'
      '  „Entdecken-Bereich"  ->  „Bereich Entdecken"\n'
      '  „Community-Name"     ->  „Name der Community"\n'
      '  „Fahrt fortgesetzt — gute Weiterfahrt!"  ->  zwei Saetze\n'
      'Geht es nicht ohne Strich, gehoert das Wort in die Ausnahmeliste '
      'oben in dieser Testdatei (mit Begruendung je Eintrag).',
    );
  });

  test('jede Ausnahme hat eine Begruendung', () {
    for (final eintrag in {...erlaubteWoerter.entries, ...dateiAusnahmen.entries}) {
      expect(
        eintrag.value.trim().length,
        greaterThanOrEqualTo(20),
        reason: 'Ausnahme „${eintrag.key}" ohne brauchbare Begruendung',
      );
    }
  });

  // ── Ersatzschreibungen statt echter Umlaute ──────────────────────────────
  // 2026-08-28: Genau dieselbe Geschichte wie beim Strich. Seit dem 12.08.
  // prueft test/release_hygiene_test.dart „ue statt ü" — aber NUR im
  // Update-Blatt. In der uebrigen App sind seither wieder solche Texte
  // gelandet; gemessen am 28.08. acht Stellen, darunter „Deine Rueckmeldung"
  // im Formular, „Bitte spaeter erneut versuchen" beim Melden und „Meldung
  // zurueckgenommen". Auf dem Handy sieht das unfertig aus.
  //
  // Geprueft wird gegen eine LISTE konkreter Ersatzschreibungen, nicht gegen
  // blosses „ue": sonst schlaegt der Test bei „neue" und „Leute" an. Die
  // Literal-Erkennung von oben wird mitbenutzt, damit Kommentare,
  // Protokollzeilen und Kennungen wie gehabt draussen bleiben.
  const ersatzschreibungen = <String>[
    'ueber', 'fuer', 'Fuer', 'koenn', 'moecht', 'waehr', 'zurueck', 'Zurueck',
    'schoen', 'gruen', 'muess', 'laesst', 'aendern', 'geaendert', 'Laenge',
    'laenge', 'Vorschlaege', 'vorschlaege', 'ruecken', 'fuehr', 'gemuetlich',
    'fluessig', 'zuverlaessig', 'kuerzer', 'groesse', 'strasse', 'Strasse',
    'schlaegt', 'gezaehlt', 'Rueck', 'rueck', 'naechst', 'spaeter', 'Spaeter',
    'haeuf', 'taeglich', 'maessig', 'bloss', 'grosse', 'Grosse',
  ];

  // Texte, die eine Ersatzschreibung behalten MUESSEN. Wie oben: ohne
  // Begruendung kein Eintrag.
  const ersatzAusnahmen = <String, String>{
    '__uebernommen_von':
        'Ein Schluessel in den SharedPreferences, kein Bildschirmtext. Wird '
            'er umbenannt, halten Geraete die einmalige Wertuebernahme ins '
            'Konto fuer noch nicht erledigt und fuehren sie erneut aus. Siehe '
            'NutzerPrefsSchluessel.uebernahmeMarke.',
    'Zu viele Rueckmeldungen':
        'Kein Bildschirmtext, sondern der Vergleich mit dem Wortlaut, den der '
            'Trigger in 20260809150000_feedback_aus_einstellungen.sql wirft. '
            'Wird er hier geaendert, erkennt die App das Stundenlimit nicht '
            'mehr und zeigt dem Nutzer die rohe Datenbankmeldung.',
  };

  final umlautFunde = <_Fund>[];
  for (final pfad in dateien) {
    if (dateiAusnahmen.containsKey(pfad)) continue;
    final quelle = File(pfad).readAsStringSync();
    for (final literal in _literale(quelle)) {
      if (literal.roh) continue;
      final text = literal.text;
      if (_istTechnisch(text)) continue;
      // Nur Saetze pruefen. Einzelwoerter ohne Leerzeichen sind fast immer
      // Kennungen, Schluessel oder Dateinamen.
      if (!text.contains(' ')) continue;

      var rest = text;
      for (final ausnahme in ersatzAusnahmen.keys) {
        rest = rest.replaceAll(ausnahme, ' ');
      }
      final treffer = ersatzschreibungen.firstWhere(
        rest.contains,
        orElse: () => '',
      );
      if (treffer.isEmpty) continue;

      umlautFunde.add(
        _Fund(
          datei: pfad,
          zeile: literal.zeile,
          art: 'Ersatzschreibung „$treffer"',
          text: text,
        ),
      );
    }
  }

  test('kein ue statt ü in Texten, die der Nutzer sieht', () {
    if (umlautFunde.isEmpty) return;
    final zeilen = umlautFunde
        .map((f) => '  ${f.datei}:${f.zeile}  [${f.art}]  „${f.text}"')
        .join('\n');
    fail(
      '${umlautFunde.length} Nutzertext(e) mit Ersatzschreibung:\n$zeilen\n\n'
      'Bitte den echten Umlaut schreiben: ü, ö, ä, ß. Das ist Text, den '
      'jemand auf dem Handy liest.\n'
      'Muss die Ersatzschreibung ausnahmsweise bleiben (etwa weil sie mit '
      'einer Servermeldung verglichen wird), gehoert sie in ersatzAusnahmen '
      'oben in dieser Datei, mit Begruendung.',
    );
  });

  test('jede Umlaut-Ausnahme hat eine Begruendung', () {
    for (final eintrag in ersatzAusnahmen.entries) {
      expect(
        eintrag.value.trim().length,
        greaterThanOrEqualTo(20),
        reason: 'Ausnahme „${eintrag.key}" ohne brauchbare Begruendung',
      );
    }
  });

  // ── Der Push kommt nicht aus lib/, sondern vom Server ────────────────────
  // Genau das war der Anlass am 25.08.: Auf dem Sperrbildschirm stand
  // „Bestes Cruise-Wetter" und „22 Grad und gut — Zeit fuer eine Runde",
  // waehrend in lib/ laengst der strichfreie Text lag. Die Edge Function
  // send-push rendert den Text selbst; sie muss deshalb mitgeprueft werden.
  group('Push vom Server', () {
    final datei = File('supabase/functions/send-push/index.ts');

    test('renderPush kommt ohne Strich aus', () {
      if (!datei.existsSync()) return;
      final quelle = datei.readAsStringSync();
      final block = RegExp(
        r'function renderPush\((.*?)\n\}',
        dotAll: true,
      ).firstMatch(quelle);
      expect(block, isNotNull, reason: 'renderPush nicht gefunden');

      // title: '...' und body: `...` einsammeln, Platzhalter herauswerfen.
      final texte = <String>[];
      for (final m in RegExp(
        r"(?:title|body):\s*(?:'([^']*)'|`([^`]*)`)",
      ).allMatches(block!.group(1)!)) {
        texte.add((m.group(1) ?? m.group(2) ?? '')
            .replaceAll(RegExp(r'\$\{[^}]*\}'), ' '));
      }
      expect(texte.length, greaterThan(5), reason: 'zu wenig Texte gefunden');

      final schlecht = <String>[];
      for (final t in texte) {
        var rest = t;
        for (final wort in erlaubteWoerter.keys) {
          rest = rest.replaceAll(wort, ' ');
        }
        final hatLang = langeStriche.split('').any(rest.contains);
        if (hatLang || _bindestrichImWort(rest)) schlecht.add(t);
      }
      expect(
        schlecht,
        isEmpty,
        reason: 'Strich im Push auf dem Sperrbildschirm: $schlecht',
      );
    });

    test('REGRESSION: der alte Wettertitel ist weg', () {
      if (!datei.existsSync()) return;
      final quelle = datei.readAsStringSync();
      // Nur der verdrahtete Titel selbst, nicht der Kommentar darueber, der
      // ihn zur Erinnerung zitiert.
      expect(
        quelle.contains("title: 'Bestes Cruise-Wetter'"),
        isFalse,
        reason: 'Genau dieser Titel stand am 25.08. auf dem Sperrbildschirm.',
      );
    });
  });

  group('der Waechter selbst', () {
    // Ein Waechter, dem man nicht ansieht, was er kann, wird abgeschaltet.
    // Diese Proben halten sein Verhalten fest.
    _Fund? pruefe(String quelle) {
      for (final literal in _literale(quelle)) {
        if (literal.roh) continue;
        final text = literal.text;
        if (_istTechnisch(text)) continue;
        if (_nurStrich(text, bindestrich, langeStriche)) continue;
        var rest = text;
        for (final wort in erlaubteWoerter.keys) {
          rest = rest.replaceAll(wort, ' ');
        }
        for (final muster in codeMuster) {
          rest = rest.replaceAll(muster, ' ');
        }
        final lang =
            langeStriche.split('').firstWhere(rest.contains, orElse: () => '');
        if (lang.isEmpty && !_bindestrichImWort(rest)) continue;
        return _Fund(
          datei: 'probe',
          zeile: literal.zeile,
          art: lang.isNotEmpty ? 'Gedankenstrich' : 'Bindestrich',
          text: text,
        );
      }
      return null;
    }

    test('findet einen Bindestrich in einem Nutzertext', () {
      expect(pruefe("const t = 'Der Entdecken-Bereich wartet';"), isNotNull);
    });

    test('findet einen Gedankenstrich', () {
      expect(
        pruefe("const t = 'Fahrt fortgesetzt — gute Weiterfahrt';"),
        isNotNull,
      );
    });

    test('laesst Kommentare in Ruhe', () {
      expect(pruefe('// Der Trip-Modus wird hier gesetzt\n'), isNull);
      expect(pruefe('/// Doku zum Starter-Paket\n'), isNull);
      expect(pruefe('/* Block mit Trip-Modus */'), isNull);
    });

    test('laesst Protokollzeilen in Ruhe', () {
      expect(pruefe("debugPrint('[Home] Trip-Status laden: \$e');"), isNull);
      expect(pruefe("debugPrintCommunity('Bild-Upload fehlgeschlagen');"), isNull);
      expect(pruefe("dev.log('Reroute-Attempt 3');"), isNull);
    });

    test('laesst Entwicklertexte an debugMessage in Ruhe', () {
      expect(
        pruefe("throw X(debugMessage: 'Access-Leg fehlgeschlagen');"),
        isNull,
      );
    });

    test('laesst Kennungen, Pfade und regulaere Ausdruecke in Ruhe', () {
      expect(pruefe("const a = 'empty-slot-icon.png';"), isNull);
      expect(pruefe(r"final r = RegExp('[A-Za-z0-9_-]+');"), isNull);
      expect(pruefe("const c = 'A-Za-z0-9_ÄÖÜäöüß';"), isNull);
      expect(pruefe("const u = 'https://tiles.cruiseconnector.at/a-b';"), isNull);
      expect(pruefe("const d = 'Nutze generateSequential() — parallel');"), isNull);
    });

    test('laesst allein stehende Striche in Ruhe', () {
      expect(pruefe("const leer = '—';"), isNull);
      expect(pruefe("const spanne = '\${a}–\${b}';"), isNull);
    });

    test('laesst die Ausnahmewoerter in Ruhe', () {
      expect(pruefe("const t = 'Bitte gib deine E-Mail-Adresse ein.';"), isNull);
      expect(pruefe("const t = 'Code der Gruppe (CC-XXXXXX)';"), isNull);
      expect(pruefe("const t = 'Meine Harley-Davidson steht bereit';"), isNull);
    });

    test('stolpert nicht ueber Anfuehrungszeichen in Platzhaltern', () {
      // Genau daran ist die erste Fassung dieses Waechters gescheitert:
      // '${map['key']} Trip-Modus' hat den Zeichenstrom entgleisen lassen,
      // danach galt halbe Datei als String und der Test fand nichts mehr.
      expect(
        pruefe("const t = '\${karte['schluessel']} Trip-Modus';"),
        isNotNull,
      );
    });

    test('findet den Strich auch in der Fuge zusammengesetzter Saetze', () {
      // Textbausteine, die aneinandergehaengt werden: der Strich steht im
      // zweiten Baustein und wuerde sonst durchrutschen.
      expect(
        pruefe("const t = 'Deine Runde wartet. '\n    'Im Trip-Modus bis 5 Stopps.';"),
        isNotNull,
      );
    });
  });
}

class _Fund {
  const _Fund({
    required this.datei,
    required this.zeile,
    required this.art,
    required this.text,
  });
  final String datei;
  final int zeile;
  final String art;
  final String text;
}

class _Literal {
  const _Literal(this.zeile, this.start, this.text, this.roh);
  final int zeile;
  final int start;
  final String text;
  final bool roh;
}

/// Ein Bindestrich zaehlt nur, wenn er wie in einem deutschen Wort steht.
///
///   * Buchstabe, Strich, GROSSBUCHSTABE  ->  „Trip-Modus", „E-Mail"
///     Genau die Form, die im Deutschen die zusammengesetzten Woerter
///     ausmacht, und die in Kennungen und Kebab-Case nicht vorkommt
///     (die sind klein geschrieben).
///   * Ziffer, Strich, kleiner Buchstabe  ->  „6-stellig", „2-fach"
///
/// Alles andere („utf-8", „a-b", „sha-256") ist Technik und bleibt in Ruhe.
bool _bindestrichImWort(String text) {
  final zusammensetzung = RegExp('[A-Za-zÄÖÜäöüß]-[A-ZÄÖÜ]');
  final mitZahl = RegExp('[0-9]-[a-zäöüß]');
  return zusammensetzung.hasMatch(text) || mitZahl.hasMatch(text);
}

/// Zeichenketten, die nie am Bildschirm landen.
bool _istTechnisch(String text) {
  // Eckige Klammer, Backslash, Dach: regulaerer Ausdruck oder Protokollpraefix
  // wie „[CruiseMode]".
  if (text.contains('[') || text.contains(r'\') || text.contains('^')) {
    return true;
  }
  // Verweis auf eine Methode, z. B. in einer @Deprecated-Meldung.
  if (text.contains('()')) return true;
  // Zeichenklasse eines regulaeren Ausdrucks ohne Klammern.
  if (!text.contains(' ') &&
      (text.contains('A-Z') || text.contains('a-z') || text.contains('0-9'))) {
    return true;
  }
  // Kennung, Dateipfad, Adresse: ein Punkt und kein einziges Leerzeichen.
  if (!text.contains(' ') && text.contains('.')) return true;
  return false;
}

/// Ein Literal, in dem ausser Strichen und Leerraum nichts steht, ist ein
/// Platzhalter („—" fuer „kein Wert") oder ein Trenner („12:00–18:00").
/// Beides ist Typografie und kein Satz.
bool _nurStrich(String text, String bindestrich, String langeStriche) {
  final ohne = text
      .split('')
      .where((c) => c != bindestrich && !langeStriche.contains(c))
      .join()
      .trim();
  return ohne.isEmpty;
}

/// Zerlegt Dart-Quelltext in seine Zeichenketten.
///
/// Muss drei Dinge koennen, sonst taugt der Waechter nichts:
///   1. Kommentare ueberspringen (auch die mit Apostroph darin).
///   2. Platzhalter `${...}` als Code behandeln, samt der Anfuehrungszeichen
///      DARIN. `'${karte['schluessel']}'` ist ein einziger String, kein Ende.
///   3. Protokollaufrufe erkennen, ohne sich an den Klammern der Platzhalter
///      zu verschlucken.
List<_Literal> _literale(String quelle) {
  final ergebnis = <_Literal>[];
  final zeichen = quelle.split('');
  // Gerippe: derselbe Text, aber Stringinhalte durch Leerzeichen ersetzt.
  // Darauf laeuft die Suche nach dem Aufrufernamen davor.
  final gerippe = List<String>.from(zeichen);

  var i = 0;
  final n = quelle.length;
  String? anfuehrung; // laufender String: "'", '"', "'''" oder '"""'
  var roh = false;
  var beginn = 0;
  final stuecke = <String>[];
  final stapel = <int>[]; // offene ${...}: gezaehlte geschweifte Klammern
  final gemerkt = <List<Object?>>[]; // (anfuehrung, roh, beginn, stuecke)

  void schliesse(int ende) {
    for (var k = beginn; k < ende && k < n; k++) {
      if (gerippe[k] != '\n') gerippe[k] = ' ';
    }
    ergebnis.add(
      _Literal(
        '\n'.allMatches(quelle.substring(0, beginn)).length + 1,
        beginn,
        stuecke.join(),
        roh,
      ),
    );
    anfuehrung = null;
    stuecke.clear();
  }

  while (i < n) {
    if (anfuehrung == null) {
      if (quelle.startsWith('//', i)) {
        var j = quelle.indexOf('\n', i);
        if (j < 0) j = n;
        for (var k = i; k < j; k++) {
          gerippe[k] = ' ';
        }
        i = j;
        continue;
      }
      if (quelle.startsWith('/*', i)) {
        var j = quelle.indexOf('*/', i + 2);
        j = j < 0 ? n : j + 2;
        for (var k = i; k < j; k++) {
          if (gerippe[k] != '\n') gerippe[k] = ' ';
        }
        i = j;
        continue;
      }
      final istRoh = quelle[i] == 'r';
      final p = istRoh ? i + 1 : i;
      String? auf;
      if (quelle.startsWith("'''", p)) {
        auf = "'''";
      } else if (quelle.startsWith('"""', p)) {
        auf = '"""';
      } else if (p < n && (quelle[p] == "'" || quelle[p] == '"')) {
        auf = quelle[p];
      }
      if (auf != null) {
        anfuehrung = auf;
        roh = istRoh;
        beginn = i;
        i = p + auf.length;
        continue;
      }
      if (stapel.isNotEmpty) {
        if (quelle[i] == '{') {
          stapel[stapel.length - 1]++;
          i++;
          continue;
        }
        if (quelle[i] == '}') {
          if (stapel.last == 0) {
            stapel.removeLast();
            final z = gemerkt.removeLast();
            anfuehrung = z[0] as String;
            roh = z[1] as bool;
            beginn = z[2] as int;
            stuecke
              ..clear()
              ..addAll(z[3] as List<String>);
            stuecke.add(' ');
            i++;
            continue;
          }
          stapel[stapel.length - 1]--;
          i++;
          continue;
        }
      }
      i++;
      continue;
    }

    final auf = anfuehrung!;
    if (!roh && quelle[i] == r'\' && i + 1 < n) {
      stuecke.add(quelle[i + 1]);
      i += 2;
      continue;
    }
    if (quelle.startsWith(auf, i)) {
      i += auf.length;
      schliesse(i);
      continue;
    }
    if (auf.length == 1 && quelle[i] == '\n') {
      // Unbeendeter String (sollte nicht vorkommen): nicht weiterschleppen.
      schliesse(i);
      i++;
      continue;
    }
    if (quelle.startsWith(r'${', i)) {
      gemerkt.add([auf, roh, beginn, List<String>.from(stuecke)]);
      stapel.add(0);
      anfuehrung = null;
      stuecke.clear();
      i += 2;
      continue;
    }
    if (quelle[i] == r'$') {
      var j = i + 1;
      while (j < n && (_istWortzeichen(quelle[j]))) {
        j++;
      }
      stuecke.add(' ');
      i = j;
      continue;
    }
    stuecke.add(quelle[i]);
    i++;
  }
  if (anfuehrung != null) schliesse(n);

  // Protokollaufrufe und Entwicklerparameter herausnehmen.
  final gerippeText = gerippe.join();
  return ergebnis.where((lit) {
    if (_istProtokoll(gerippeText, lit.start)) return false;
    if (_istEntwicklerParameter(gerippeText, lit.start)) return false;
    return true;
  }).toList();
}

bool _istWortzeichen(String c) =>
    RegExp('[A-Za-z0-9_]').hasMatch(c);

const _protokollNamen = {'print', 'log', 'assert'};

/// Steht das Literal in einem debugPrint, print, log oder assert?
///
/// Wandert vom Literal rueckwaerts durch das Gerippe bis zur oeffnenden
/// Klammer des Aufrufs. Weil Stringinhalte im Gerippe geleert sind, koennen
/// die Klammern aus Platzhaltern nicht mehr stoeren.
bool _istProtokoll(String gerippe, int stelle) {
  var j = stelle;
  var tiefe = 0;
  while (j > 0) {
    final c = gerippe[j - 1];
    if (c == ';' || c == '{' || c == '}') return false;
    if (c == ')') {
      tiefe++;
      j--;
      continue;
    }
    if (c == '(') {
      if (tiefe == 0) {
        var k = j - 1;
        while (k > 0 && RegExp(r'[A-Za-z0-9_.]').hasMatch(gerippe[k - 1])) {
          k--;
        }
        final name = gerippe.substring(k, j - 1).split('.').last;
        return _protokollNamen.contains(name) ||
            name.startsWith('debugPrint') ||
            name.toLowerCase().endsWith('log');
      }
      tiefe--;
    }
    j--;
  }
  return false;
}

/// Steht das Literal an einem Parameter, der ausdruecklich fuer Entwickler
/// gedacht ist (`debugMessage:`, `logText:`)?
bool _istEntwicklerParameter(String gerippe, int stelle) {
  var j = stelle;
  while (j > 0 && (gerippe[j - 1] == ' ' || gerippe[j - 1] == '\n')) {
    j--;
  }
  if (j == 0 || gerippe[j - 1] != ':') return false;
  j--;
  while (j > 0 && (gerippe[j - 1] == ' ' || gerippe[j - 1] == '\n')) {
    j--;
  }
  var k = j;
  while (k > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(gerippe[k - 1])) {
    k--;
  }
  final name = gerippe.substring(k, j).toLowerCase();
  return name.contains('debug') || name.contains('log');
}
