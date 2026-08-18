import 'dart:io';

import 'package:cruise_connect/data/services/country_region.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Defekt 1b2 aus dem Produktionsbericht vom 18.08.):
/// „Villach und Lienz werden als Italien klassifiziert." Gemessen an der
/// Produktions-Edge stimmte das und traf zusätzlich Klagenfurt (→ SI).
/// Folge: Wer dort „Im Land bleiben" wählte, bekam 422 `no_inland_route`.
///
/// Der Test hält beides fest: die korrekte Zuordnung UND dass Client und
/// Edge dieselbe Bandtabelle benutzen. Laufen die auseinander, weist der
/// Server Routen ab, die der Client für inländisch hält.
void main() {
  group('CountryRegion.classify an der Südgrenze', () {
    const orte = <(String, double, double, String)>[
      // Österreich, das bisher als IT oder SI galt
      ('Villach', 46.610, 13.856, 'AT'),
      ('Lienz', 46.830, 12.769, 'AT'),
      ('Klagenfurt', 46.625, 14.308, 'AT'),
      ('Wolfsberg', 46.840, 14.845, 'AT'),
      ('Spittal an der Drau', 46.795, 13.499, 'AT'),
      ('Hermagor', 46.626, 13.367, 'AT'),
      ('Arnoldstein', 46.548, 13.708, 'AT'),
      ('Ferlach', 46.526, 14.303, 'AT'),
      ('Bleiburg', 46.588, 14.797, 'AT'),
      ('Lavamünd', 46.628, 14.938, 'AT'),
      ('Matrei in Osttirol', 47.000, 12.539, 'AT'),
      ('Sillian', 46.750, 12.419, 'AT'),
      // Österreich, das schon vorher stimmte — darf nicht kippen
      ('Graz', 47.071, 15.439, 'AT'),
      ('Eibiswald', 46.686, 15.248, 'AT'),
      ('Leibnitz', 46.783, 15.541, 'AT'),
      ('Spielfeld', 46.706, 15.634, 'AT'),
      ('Mureck', 46.708, 15.774, 'AT'),
      ('Bad Radkersburg', 46.687, 15.986, 'AT'),
      ('Innsbruck', 47.269, 11.404, 'AT'),
      ('Salzburg', 47.809, 13.055, 'AT'),
      ('Wien', 48.208, 16.373, 'AT'),
      ('Bregenz', 47.503, 9.747, 'AT'),
      // Ausland darf NICHT zu AT werden
      ('Bozen (IT)', 46.498, 11.354, 'IT'),
      ('Meran (IT)', 46.671, 11.159, 'IT'),
      ('Innichen (IT)', 46.733, 12.279, 'IT'),
      ('Udine (IT)', 46.063, 13.235, 'IT'),
      ('Tarvis (IT)', 46.505, 13.581, 'IT'),
      ('Ljubljana (SI)', 46.056, 14.506, 'SI'),
      ('Jesenice (SI)', 46.431, 14.058, 'SI'),
      ('Dravograd (SI)', 46.589, 15.017, 'SI'),
      ('Radlje ob Dravi (SI)', 46.614, 15.229, 'SI'),
      ('Maribor (SI)', 46.554, 15.646, 'SI'),
      ('Šentilj (SI)', 46.680, 15.647, 'SI'),
      ('Gornja Radgona (SI)', 46.6786, 15.991, 'SI'),
      ('Zürich (CH)', 47.377, 8.540, 'CH'),
      ('München (DE)', 48.135, 11.582, 'DE'),
      ('Vaduz (LI)', 47.141, 9.521, 'LI'),
    ];

    for (final (name, lat, lng, soll) in orte) {
      test('$name → $soll', () {
        expect(CountryRegion.classify(lat, lng), soll, reason: '$name ($lat/$lng)');
      });
    }
  });

  test('Client und Edge benutzen dieselbe Süd-Bandtabelle', () {
    // Reine Zahlenpaare aus beiden Dateien ziehen und vergleichen. Läuft die
    // Tabelle auseinander, klassifiziert der Server die Routenpunkte anders
    // als der Client den Startpunkt — genau die Falle aus Defekt 1b2.
    List<String> baender(String quelle, String funktion) {
      final start = quelle.indexOf(funktion);
      expect(start, greaterThan(-1), reason: '$funktion nicht gefunden');
      final ende = quelle.indexOf('\n}', start);
      final block = quelle.substring(start, ende);
      return RegExp(r'lng < (\d+\.\d+)\) return (\d+\.\d+)')
          .allMatches(block)
          .map((m) => '${m.group(1)}/${m.group(2)}')
          .toList();
    }

    final dart = baender(
      File('lib/data/services/country_region.dart').readAsStringSync(),
      'static double _austriaSouthLimit(',
    );
    final ts = baender(
      File('supabase/functions/generate-cruise-route-v2/index.ts').readAsStringSync(),
      'function austriaSouthLimit(',
    );
    expect(dart, isNotEmpty);
    expect(dart, ts, reason: 'Bandtabellen von Client und Edge weichen ab');
  });
}
