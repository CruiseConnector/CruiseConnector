import 'package:cruise_connect/presentation/widgets/cruise/umleitung_entscheidung_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-26 (vucko): „Beim A nach B Modus oder Trip Modus soll bei der
/// Meldung oben kommen: X Baustellen auf dem Weg, Umleitung nehmen oder mit
/// den Baustellen? Und wie lange der Umweg kosten wuerde an Zeit oder Zeit
/// erspart normalerweise."
///
/// Die Zahl ist der Kern: ohne sie ist die Frage nicht beantwortbar.
void main() {
  String zeit(int direktSek, int umleitungSek) =>
      UmleitungEntscheidung.zeitUnterschiedText(
        Duration(seconds: direktSek),
        Duration(seconds: umleitungSek),
      );

  String weg(double direkt, double umleitung) =>
      UmleitungEntscheidung.wegUnterschiedText(direkt, umleitung);

  group('Zeitunterschied in Worten', () {
    test('Umleitung dauert laenger', () {
      expect(zeit(600, 780), '3 Minuten länger');
      expect(zeit(600, 660), '1 Minute länger');
    });

    test('Umleitung ist schneller — kommt vor, wenn die Baustelle bremst', () {
      expect(zeit(900, 780), '2 Minuten schneller');
    });

    test('unter einer Dreiviertelminute wird nicht gerundet behauptet', () {
      expect(zeit(600, 630), 'ungefähr gleich lang');
      expect(zeit(600, 600), 'ungefähr gleich lang');
      expect(zeit(600, 570), 'ungefähr gleich lang');
    });

    test('Einzahl und Mehrzahl stimmen', () {
      expect(zeit(600, 655), '1 Minute länger');
      expect(zeit(600, 720), '2 Minuten länger');
    });
  });

  group('Wegunterschied in Worten', () {
    test('Meter unter einem Kilometer, auf zehn gerundet', () {
      expect(weg(10000, 10400), '400 Meter mehr');
      expect(weg(10000, 9600), '400 Meter weniger');
    });

    test('ab einem Kilometer in Kilometern', () {
      expect(weg(10000, 11200), '1.2 km mehr');
    });

    test('unter hundert Metern ist gleich weit', () {
      expect(weg(10000, 10050), 'gleich weit');
      expect(weg(10000, 10000), 'gleich weit');
    });
  });

  test('keine Striche in den Nutzertexten', () {
    final texte = <String>[
      zeit(600, 780),
      zeit(900, 780),
      zeit(600, 630),
      weg(10000, 10400),
      weg(10000, 11200),
      weg(10000, 10050),
    ];
    for (final t in texte) {
      expect(t.contains('-'), isFalse, reason: 'Strich in "$t"');
      expect(t.contains('—'), isFalse, reason: 'Gedankenstrich in "$t"');
    }
  });
}
