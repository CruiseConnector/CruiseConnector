import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/completion_title_generator.dart';

void main() {
  group('CompletionTitleGenerator', () {
    // 2026-05-31: Donnerstag = 2026-05-28 (weekday 4), 18 Uhr → "...abend".
    final donnerstagAbend = DateTime(2026, 5, 28, 18, 30);
    final sonntagMorgen = DateTime(2026, 5, 31, 7, 0); // weekday 7

    test('ist deterministisch — gleiche Fahrt, gleicher Titel', () {
      final a = CompletionTitleGenerator.generate(
        time: donnerstagAbend,
        style: 'Sport Mode',
        distanceKm: 52.0,
        curves: 30,
      );
      final b = CompletionTitleGenerator.generate(
        time: donnerstagAbend,
        style: 'Sport Mode',
        distanceKm: 52.0,
        curves: 30,
      );
      expect(a, b);
    });

    test('Sport am Donnerstagabend → sportliches Adjektiv + Donnerstagabend', () {
      final title = CompletionTitleGenerator.generate(
        time: donnerstagAbend,
        style: 'Sport Mode',
        distanceKm: 52.0,
        curves: 30,
      );
      expect(title, endsWith('Donnerstagabend'));
      expect(
        ['Sportlicher', 'Flotter', 'Dynamischer']
            .any((adj) => title.startsWith(adj)),
        isTrue,
        reason: 'Titel "$title" sollte mit einem Sport-Adjektiv beginnen',
      );
    });

    test('Tageszeit-Suffix passt zur Stunde', () {
      expect(
        CompletionTitleGenerator.generate(
          time: sonntagMorgen,
          style: 'Kurvenjagd',
          distanceKm: 40,
        ),
        endsWith('Sonntagmorgen'),
      );
      expect(
        CompletionTitleGenerator.generate(
          time: DateTime(2026, 5, 30, 13), // Samstag 13 Uhr
          style: 'Abendrunde',
          distanceKm: 30,
        ),
        endsWith('Samstagmittag'),
      );
    });

    test('Kurven-Stil liefert kurvenpassendes Adjektiv', () {
      final title = CompletionTitleGenerator.generate(
        time: sonntagMorgen,
        style: 'Kurvenjagd',
        distanceKm: 60,
        curves: 80,
      );
      expect(
        ['Kurviger', 'Kurvenreicher', 'Verwinkelter']
            .any((adj) => title.startsWith(adj)),
        isTrue,
        reason: 'Titel "$title" sollte kurvenpassend sein',
      );
    });

    test('unbekannter Stil fällt auf neutrale Adjektive zurück', () {
      final title = CompletionTitleGenerator.generate(
        time: donnerstagAbend,
        style: 'irgendwas',
        distanceKm: 10,
      );
      expect(
        ['Schöner', 'Guter', 'Runder'].any((adj) => title.startsWith(adj)),
        isTrue,
      );
      expect(title, endsWith('Donnerstagabend'));
    });
  });
}
