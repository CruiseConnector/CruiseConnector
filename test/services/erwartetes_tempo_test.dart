import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/erwartetes_tempo.dart';
import 'package:cruise_connect/domain/models/route_result.dart';

/// 2026-08-20 (Vucko, Aufgabe 4): Der Massstab, gegen den [StauErkennung]
/// misst. Der gefaehrliche Fehler waere nicht ein verpasster Stau, sondern
/// eine Landstrasse, die als Stau gilt — die App lebt von Leuten, die
/// Kurvenstrassen absichtlich langsam fahren.
void main() {
  group('unterhalb von 80 km/h gibt es keine Erwartung', () {
    test('Ortsgebiet mit 50 liefert null', () {
      expect(erwartetesTempoMsAusTempolimit(50), isNull);
    });

    test('Tempo-30-Zone liefert null', () {
      expect(erwartetesTempoMsAusTempolimit(30), isNull);
    });

    test('genau 70 liefert noch null, genau 80 liefert einen Wert', () {
      expect(erwartetesTempoMsAusTempolimit(70), isNull);
      expect(erwartetesTempoMsAusTempolimit(80), isNotNull);
    });
  });

  group('oberhalb davon gilt das Limit mit Abschlag', () {
    test('Landstrasse 100 ergibt 85 km/h Erwartung', () {
      final ms = erwartetesTempoMsAusTempolimit(100)!;
      expect(ms * 3.6, closeTo(85.0, 0.01));
    });

    test('Autobahn 130 ergibt 110,5 km/h Erwartung', () {
      final ms = erwartetesTempoMsAusTempolimit(130)!;
      expect(ms * 3.6, closeTo(110.5, 0.01));
    });

    test('gemuetliche 60 km/h auf einer Landstrasse mit 100 gelten als normal',
        () {
      // 60 von 85 erwarteten sind 71 Prozent. Die Erkennung nennt erst
      // hoechstens 40 Prozent langsam — eine Kurvenfahrt loest damit nie aus.
      final erwartet = erwartetesTempoMsAusTempolimit(100)!;
      expect(60 / 3.6 / erwartet, greaterThan(0.4));
    });

    test('Schritttempo auf der Autobahn faellt klar unter die Schwelle', () {
      final erwartet = erwartetesTempoMsAusTempolimit(130)!;
      expect(20 / 3.6 / erwartet, lessThan(0.4));
    });
  });

  group('unbrauchbare Werte liefern null statt Unsinn', () {
    test('kein Limit bekannt', () {
      expect(erwartetesTempoMsAusTempolimit(null), isNull);
    });

    test('kaputte OSM-Werte', () {
      expect(erwartetesTempoMsAusTempolimit(0), isNull);
      expect(erwartetesTempoMsAusTempolimit(-50), isNull);
      expect(erwartetesTempoMsAusTempolimit(999), isNull);
    });
  });

  group('Abschnittssuche entlang der Route', () {
    final abschnitte = [
      const SpeedLimitSegment(startIndex: 0, endIndex: 40, speedKmh: 50),
      const SpeedLimitSegment(startIndex: 41, endIndex: 120, speedKmh: 100),
      const SpeedLimitSegment(startIndex: 121, endIndex: 300, speedKmh: 130),
    ];

    test('trifft den richtigen Abschnitt', () {
      expect(tempolimitAnRoutenIndex(abschnitte, 0), 50);
      expect(tempolimitAnRoutenIndex(abschnitte, 40), 50);
      expect(tempolimitAnRoutenIndex(abschnitte, 41), 100);
      expect(tempolimitAnRoutenIndex(abschnitte, 200), 130);
    });

    test('ausserhalb aller Abschnitte gibt es keine Erwartung', () {
      expect(tempolimitAnRoutenIndex(abschnitte, 5000), isNull);
      expect(tempolimitAnRoutenIndex(abschnitte, -1), isNull);
      expect(tempolimitAnRoutenIndex(const [], 10), isNull);
    });

    test('der Zusammenzug liefert im Ortsgebiet null, auf der Autobahn Tempo',
        () {
      expect(erwartetesTempoMsAnRoutenIndex(abschnitte, 10), isNull);
      expect(
        erwartetesTempoMsAnRoutenIndex(abschnitte, 200)! * 3.6,
        closeTo(110.5, 0.01),
      );
    });
  });
}
