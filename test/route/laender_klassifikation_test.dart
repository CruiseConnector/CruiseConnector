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
      // 2026-08-25 (Feld-Kommentar „App meldet in Italien bleiben obwohl ich
      // derzeit in Kroatien bin"): Kroatien fehlte komplett. Gemessen ergaben
      // Pula/Poreč/Rovinj/Umag/Motovun 'IT', Zagreb und sieben weitere 'SI',
      // 23 weitere null — kein einziger Ort war richtig.
      ('Pula (HR)', 44.867, 13.848, 'HR'),
      ('Rovinj (HR)', 45.081, 13.639, 'HR'),
      ('Poreč (HR)', 45.228, 13.594, 'HR'),
      ('Umag (HR)', 45.436, 13.524, 'HR'),
      ('Motovun (HR)', 45.336, 13.828, 'HR'),
      ('Pazin (HR)', 45.240, 13.938, 'HR'),
      ('Buzet (HR)', 45.410, 14.028, 'HR'),
      ('Rijeka (HR)', 45.327, 14.443, 'HR'),
      ('Opatija (HR)', 45.338, 14.305, 'HR'),
      ('Krk (HR)', 45.026, 14.576, 'HR'),
      ('Senj (HR)', 44.990, 14.906, 'HR'),
      ('Delnice (HR)', 45.401, 14.798, 'HR'),
      ('Gospić (HR)', 44.546, 15.374, 'HR'),
      ('Zadar (HR)', 44.119, 15.224, 'HR'),
      ('Knin (HR)', 44.041, 16.199, 'HR'),
      ('Šibenik (HR)', 43.735, 15.895, 'HR'),
      ('Split (HR)', 43.508, 16.440, 'HR'),
      ('Makarska (HR)', 43.297, 17.017, 'HR'),
      ('Ploče (HR)', 43.055, 17.433, 'HR'),
      ('Dubrovnik (HR)', 42.650, 18.092, 'HR'),
      ('Zagreb (HR)', 45.815, 15.978, 'HR'),
      ('Karlovac (HR)', 45.487, 15.548, 'HR'),
      ('Samobor (HR)', 45.803, 15.711, 'HR'),
      ('Sisak (HR)', 45.485, 16.377, 'HR'),
      ('Varaždin (HR)', 46.306, 16.338, 'HR'),
      ('Čakovec (HR)', 46.389, 16.434, 'HR'),
      ('Bjelovar (HR)', 45.898, 16.842, 'HR'),
      ('Slavonski Brod (HR)', 45.160, 18.016, 'HR'),
      ('Vinkovci (HR)', 45.288, 18.805, 'HR'),
      ('Osijek (HR)', 45.555, 18.694, 'HR'),
      ('Vukovar (HR)', 45.351, 19.001, 'HR'),
      // Die slowenische Küste galt bisher als Italien — die IT-Box reichte
      // nach Osten bis lng 13.9.
      ('Koper (SI)', 45.548, 13.730, 'SI'),
      ('Piran (SI)', 45.528, 13.568, 'SI'),
      ('Novo mesto (SI)', 45.804, 15.170, 'SI'),
      // Italien direkt an der Grenze darf NICHT kippen.
      ('Triest (IT)', 45.650, 13.771, 'IT'),
      ('Muggia (IT)', 45.600, 13.767, 'IT'),
      ('Grado (IT)', 45.677, 13.394, 'IT'),
      ('Venedig (IT)', 45.440, 12.316, 'IT'),
    ];

    // Kroatien ist eine Sichel um Bosnien herum. Diese Orte liegen INNERHALB
    // der Umhüllenden und dürfen trotzdem nicht 'HR' ergeben — sonst filtert
    // „Im Land bleiben" für einen Bosnier auf Kroatien.
    const nichtKroatien = <(String, double, double)>[
      ('Sarajevo (BA)', 43.856, 18.413),
      ('Banja Luka (BA)', 44.772, 17.191),
      ('Mostar (BA)', 43.343, 17.808),
      ('Bihać (BA)', 44.815, 15.871),
      ('Tuzla (BA)', 44.538, 18.676),
      ('Zenica (BA)', 44.203, 17.907),
      ('Trebinje (BA)', 42.712, 18.344),
      ('Podgorica (ME)', 42.441, 19.263),
      ('Herceg Novi (ME)', 42.453, 18.537),
      ('Kotor (ME)', 42.424, 18.771),
      ('Belgrad (RS)', 44.787, 20.449),
      ('Novi Sad (RS)', 45.255, 19.845),
      ('Sombor (RS)', 45.774, 19.113),
      ('Pécs (HU)', 46.073, 18.233),
      ('Nagykanizsa (HU)', 46.456, 16.997),
      ('Kaposvár (HU)', 46.359, 17.795),
      ('Szeged (HU)', 46.253, 20.148),
    ];
    for (final (name, lat, lng) in nichtKroatien) {
      test('$name ist NICHT Kroatien', () {
        expect(CountryRegion.classify(lat, lng), isNot('HR'),
            reason: '$name ($lat/$lng)');
      });
    }

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
      // Blockende = erste Zeile, die nur aus einer schliessenden Klammer
      // besteht. In Dart ist sie eingerueckt ('\n  }'), in TypeScript nicht
      // ('\n}'). Mit dem festen '\n}' las die Dart-Seite bis zum KLASSENENDE
      // und zog damit die Baender der naechsten Funktion mit hinein.
      final rest = quelle.substring(start);
      final ende = RegExp(r'\n *\}').firstMatch(rest)!.start;
      final block = rest.substring(0, ende);
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

  test('Client und Edge benutzen dieselben Kroatien-Bandtabellen', () {
    // 2026-08-25: gleiche Falle wie bei der Südgrenze — läuft die Tabelle
    // auseinander, hält der Client eine Route für inländisch, die der Server
    // mit `no_inland_route` abweist.
    List<String> baender(String quelle, String funktion) {
      final start = quelle.indexOf(funktion);
      expect(start, greaterThan(-1), reason: '$funktion nicht gefunden');
      // Blockende = erste Zeile, die nur aus einer schliessenden Klammer
      // besteht. In Dart ist sie eingerueckt ('\n  }'), in TypeScript nicht
      // ('\n}'). Mit dem festen '\n}' las die Dart-Seite bis zum KLASSENENDE
      // und zog damit die Baender der naechsten Funktion mit hinein.
      final rest = quelle.substring(start);
      final ende = RegExp(r'\n *\}').firstMatch(rest)!.start;
      final block = rest.substring(0, ende);
      return RegExp(r'lng < (\d+\.\d+)\) return (\d+\.\d+)')
          .allMatches(block)
          .map((m) => '${m.group(1)}/${m.group(2)}')
          .toList();
    }

    final dartQuelle = File('lib/data/services/country_region.dart')
        .readAsStringSync();
    final tsQuelle = File(
      'supabase/functions/generate-cruise-route-v2/index.ts',
    ).readAsStringSync();

    final nordDart = baender(dartQuelle, 'static double _croatiaNorthLimit(');
    final nordTs = baender(tsQuelle, 'function croatiaNorthLimit(');
    expect(nordDart, isNotEmpty);
    expect(nordDart, nordTs, reason: 'Nordgrenze weicht ab');

    final suedDart = baender(dartQuelle, 'static double _croatiaSouthLimit(');
    final suedTs = baender(tsQuelle, 'function croatiaSouthLimit(');
    expect(suedDart, isNotEmpty);
    expect(suedDart, suedTs, reason: 'Südgrenze weicht ab');
  });
}
