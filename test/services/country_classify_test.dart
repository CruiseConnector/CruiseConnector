import 'package:flutter_test/flutter_test.dart';
import 'package:cruise_connect/data/services/country_region.dart';

/// 2026-06-08 (vucko DACH-Test): sichert die AT/DE-Grenzklassifikation für die
/// gezackten Alpenorte ab (vorher labelte die flache 47.70-Linie deutsche Orte
/// südlich davon fälschlich als AT → „Im Land bleiben" aufs falsche Land).
void main() {
  void expectCountry(String name, double lat, double lng, String expected) {
    expect(CountryRegion.classify(lat, lng), expected, reason: name);
  }

  test('DE/AT-Alpengrenze korrekt klassifiziert', () {
    // Deutschland (südliche Ausbuchtungen)
    expectCountry('Garmisch-Partenkirchen', 47.4917, 11.0954, 'DE');
    expectCountry('Mittenwald', 47.4436, 11.2600, 'DE');
    expectCountry('Füssen', 47.5710, 10.7020, 'DE');
    expectCountry('Kiefersfelden', 47.6170, 12.1880, 'DE');
    expectCountry('Freilassing', 47.8370, 12.9760, 'DE');
    expectCountry('Lindau', 47.5459, 9.6845, 'DE'); // Halbinsel im Bodensee
    expectCountry('München', 48.1372, 11.5755, 'DE');
    expectCountry('Kempten', 47.7333, 10.3167, 'DE');
    // Österreich (nördliche Ausbuchtungen / Tirol)
    expectCountry('Reutte', 47.4900, 10.7180, 'AT');
    expectCountry('Scharnitz', 47.3900, 11.2670, 'AT');
    expectCountry('Innsbruck', 47.2692, 11.4041, 'AT');
    expectCountry('Kufstein', 47.5830, 12.1690, 'AT');
    expectCountry('Lochau', 47.5350, 9.7550, 'AT'); // AT, südöstl. von Lindau
    expectCountry('Bregenz', 47.5031, 9.7471, 'AT'); // südl. von Lindau
    expectCountry('Salzburg', 47.8000, 13.0450, 'AT');
    expectCountry('Wien', 48.2082, 16.3738, 'AT');
    // Schweiz / weitere
    expectCountry('Zürich', 47.3769, 8.5417, 'CH');
    expectCountry('Andermatt', 46.6340, 8.5940, 'CH');
  });
}
