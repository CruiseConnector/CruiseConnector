import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-09-01 — Waechter ueber die DRITTE Fassung der Laender-Klassifikation.
///
/// Es gibt sie jetzt an drei Stellen:
///   1. lib/data/services/country_region.dart              (Client)
///   2. supabase/functions/generate-cruise-route-v2/index.ts (Routing)
///   3. supabase/functions/badge-kennzahlen/land_klassifikation.ts (Abzeichen)
///
/// Die dritte kam fuer die neue Familie "Laender" (badge_77 bis badge_79)
/// dazu. Vuckos Vorgabe: "serverseitige Laender-Klassifikation verwenden,
/// NICHT den Client entscheiden lassen."
///
/// WARUM EINE KOPIE UND NICHT EIN GEMEINSAMES MODUL: Die sauberere Loesung
/// waere gewesen, die Funktionen aus der Routing-Funktion herauszuloesen. Das
/// faellt aber mitten in die Datei, die Vucko als wichtigstes Stueck benannt
/// hat und die am selben Tag schon fuer den Kehrtwenden-Fix geaendert wurde.
/// Fuer ein Abzeichen war mir das Risiko zu gross.
///
/// Der Preis dafuer ist dieser Test. Laufen die Fassungen auseinander, faellt
/// er — und zwar an genau der Bandtabelle, die abweicht. Die Herausloesung
/// gehoert nachgeholt, sobald die Routing-Funktion aus anderem Grund ohnehin
/// angefasst wird; dann kann diese Datei ersatzlos weg.
void main() {
  final routing = File(
    'supabase/functions/generate-cruise-route-v2/index.ts',
  ).readAsStringSync();
  final abzeichen = File(
    'supabase/functions/badge-kennzahlen/land_klassifikation.ts',
  ).readAsStringSync();

  /// Die Zahlenpaare einer Bandtabelle, aus dem Quelltext gelesen.
  List<String> baender(String quelle, String funktion) {
    final start = quelle.indexOf(funktion);
    expect(start, greaterThan(-1), reason: '$funktion nicht gefunden');
    final rest = quelle.substring(start);
    final ende = RegExp(r'\n *\}').firstMatch(rest)!.start;
    // Die Tabellen sind unterschiedlich formuliert: die einen pruefen
    // `lng < x`, andere `lat >= x`. Beide Formen zaehlen.
    return RegExp(r'(?:lng|lat) [<>]=? (\d+\.\d+)\) return (\d+\.\d+)')
        .allMatches(rest.substring(0, ende))
        .map((m) => '${m.group(1)}/${m.group(2)}')
        .toList();
  }

  group('Die Abzeichen-Fassung rechnet wie die Routing-Fassung', () {
    for (final funktion in const [
      'function austriaSouthLimit(',
      'function austriaNorthLimit(',
      'function croatiaNorthLimit(',
      'function croatiaSouthLimit(',
      'function vorarlbergWestLimit(',
    ]) {
      test('Bandtabelle $funktion ist gleich', () {
        final a = baender(routing, funktion);
        final b = baender(abzeichen, funktion);
        expect(
          a,
          isNotEmpty,
          reason:
              'In der Routing-Funktion wurde keine Bandtabelle gefunden. '
              'Wurde $funktion umbenannt? Dann diesen Waechter mitziehen.',
        );
        expect(
          b,
          a,
          reason:
              'Die Abzeichen-Fassung weicht bei $funktion ab. Damit zaehlt '
              'die Laender-Familie andere Grenzen als das Routing — ein '
              'Nutzer bekaeme ein Abzeichen fuer ein Land, in dem er laut '
              'Server nie war.',
        );
      });
    }

    test('die festen Grenzboxen sind gleich', () {
      // Nicht alle Grenzen stehen in Bandtabellen; die Schweiz, Lindau und
      // Liechtenstein sind feste Kaesten. Auch die muessen uebereinstimmen.
      List<String> kaesten(String q) {
        final i = q.indexOf('function classifyCountry(');
        expect(i, greaterThan(-1));
        final rest = q.substring(i);
        final ende = RegExp(r'\n\}').firstMatch(rest)!.start;
        return RegExp(r'(\d+\.\d+)')
            .allMatches(rest.substring(0, ende))
            .map((m) => m.group(1)!)
            .toList();
      }

      final a = kaesten(routing);
      final b = kaesten(abzeichen);
      expect(a, isNotEmpty);
      expect(
        b,
        a,
        reason:
            'Die Zahlen in classifyCountry weichen ab. Beide Fassungen '
            'muessen dieselben Grenzen ziehen.',
      );
    });

    test('die Reihenfolge der Pruefungen ist gleich', () {
      // Die Reihenfolge traegt Bedeutung: Vorarlberg wird VOR der Schweiz
      // geprueft, Kroatien VOR Italien und Slowenien. Eine andere Reihenfolge
      // liefert bei gleichen Zahlen andere Ergebnisse.
      List<String> reihenfolge(String q) {
        final i = q.indexOf('function classifyCountry(');
        final rest = q.substring(i);
        final ende = RegExp(r'\n\}').firstMatch(rest)!.start;
        return RegExp(r"return '([A-Z]{2})'")
            .allMatches(rest.substring(0, ende))
            .map((m) => m.group(1)!)
            .toList();
      }

      final a = reihenfolge(routing);
      final b = reihenfolge(abzeichen);
      expect(a, isNotEmpty);
      expect(b, a, reason: 'Die Laender werden in anderer Reihenfolge geprueft.');
    });
  });

  group('Die Abzeichen-Funktion fragt sicher', () {
    late String dienst;

    setUpAll(() {
      dienst = File(
        'supabase/functions/badge-kennzahlen/index.ts',
      ).readAsStringSync();
    });

    test('sie nimmt die Kennung NUR aus dem Token', () {
      expect(
        dienst.contains('auth.getUser(token)'),
        isTrue,
        reason:
            'Wer die Nutzerkennung aus dem Anfragekoerper naehme, liesse '
            'jeden die Zahlen eines anderen holen.',
      );
      expect(
        RegExp(r"user_id[\s\S]{0,40}koerper|body\.user").hasMatch(dienst),
        isFalse,
        reason: 'Keine Kennung aus dem Koerper.',
      );
    });

    test('sie gibt keine Koordinaten zurueck', () {
      // Sie beantwortet eine Zahl. Eine Spur zurueckzugeben waere ein
      // Standortverlauf.
      expect(dienst.contains('track_geometry'), isTrue);
      // Die ERFOLGS-Antwort, nicht die Fehlerantworten weiter oben.
      final i = dienst.indexOf('return antwort({\n      laender:');
      expect(i, greaterThan(-1), reason: 'Erfolgsantwort nicht gefunden');
      final block = dienst.substring(i, i + 260);
      expect(
        block.contains('laender') && block.contains('codes'),
        isTrue,
      );
      expect(
        block.contains('track') || block.contains('spur:'),
        isFalse,
        reason: 'Die Antwort darf nur Zahl und Laenderkuerzel enthalten.',
      );
    });
  });
}
