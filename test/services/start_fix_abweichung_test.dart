import 'package:flutter_test/flutter_test.dart';

import 'package:cruise_connect/data/services/navigation_guidance_utils.dart';

/// 2026-08-04 (vucko): „Manchmal kommt GPS ist zu alt. Das macht gar keinen
/// Sinn, wenn man dauerhaft die GPS-Freigabe gegeben hat. Ich möchte, dass man
/// immer eine Route suchen kann ohne diesen Fehler."
///
/// Vorher brach `_acquireFreshStartFix` mit einer Ausnahme ab, sobald kein Fix
/// zugleich jünger als 10 s und genauer als 50 m war — die Suche war blockiert,
/// mit einem Zielort im Feld und ohne Knopf zum Wiederholen.
///
/// Jetzt nimmt sie den besten vorhandenen Fix. „Bester" ist der mit der
/// kleinsten möglichen Abweichung, und die berechnet [possibleOffsetMeters].
/// Diese Zahl entscheidet außerdem, ob der Nutzer einen Hinweis bekommt
/// (ab 60 m).
///
/// Wichtig für spätere Sitzungen: Die strenge 10-s-/50-m-Schwelle ist NICHT
/// aufgeweicht worden. Sie entscheidet weiterhin, welcher Fix bevorzugt wird —
/// nur ihr Scheitern ist kein Abbruch mehr.
void main() {
  group('Die Abweichung setzt sich aus beiden Fehlerquellen zusammen', () {
    test('im Stand zählt allein die Genauigkeit', () {
      expect(
        possibleOffsetMeters(
          accuracyMeters: 12,
          speedMetersPerSecond: 0,
          age: const Duration(seconds: 30),
        ),
        12,
        reason: 'Wer steht, bewegt sich auch in 30 s keinen Meter',
      );
    });

    test('bei Tempo zählt das Alter mit', () {
      // 100 km/h = 27,8 m/s, 10 s alt = rund 278 m Versatz.
      final abweichung = possibleOffsetMeters(
        accuracyMeters: 8,
        speedMetersPerSecond: 27.8,
        age: const Duration(seconds: 10),
      );
      expect(abweichung, closeTo(286, 1));
    });

    test('ein negatives Alter (Uhr-Sprung) kippt das Ergebnis nicht', () {
      final abweichung = possibleOffsetMeters(
        accuracyMeters: 10,
        speedMetersPerSecond: 20,
        age: const Duration(seconds: -5),
      );
      expect(
        abweichung,
        closeTo(110, 0.1),
        reason: 'Der Betrag zählt, sonst käme eine kleinere Abweichung heraus '
            'als in Wirklichkeit',
      );
    });
  });

  group('Fehlende Angaben dürfen nicht als perfekt durchgehen', () {
    test('Genauigkeit 0 wird als unbekannt behandelt, nicht als exakt', () {
      expect(
        possibleOffsetMeters(
          accuracyMeters: 0,
          speedMetersPerSecond: 0,
          age: Duration.zero,
        ),
        100,
        reason: 'Sonst gewänne ein Fix ohne Genauigkeitsangabe jeden Vergleich',
      );
    });

    test('unendliche Werte fallen auf den Ersatzwert zurück', () {
      expect(
        possibleOffsetMeters(
          accuracyMeters: double.infinity,
          speedMetersPerSecond: double.nan,
          age: const Duration(seconds: 5),
        ),
        100,
      );
    });

    test('negatives Tempo wird ignoriert statt abgezogen', () {
      expect(
        possibleOffsetMeters(
          accuracyMeters: 20,
          speedMetersPerSecond: -8,
          age: const Duration(seconds: 10),
        ),
        20,
      );
    });
  });

  group('Die Auswahl trifft die richtige Entscheidung', () {
    /// Bildet `_besterVerfuegbarerFix` ab: kleinste Abweichung gewinnt.
    double besteAbweichung(List<({double acc, double speed, int alterS})> k) {
      return k
          .map(
            (e) => possibleOffsetMeters(
              accuracyMeters: e.acc,
              speedMetersPerSecond: e.speed,
              age: Duration(seconds: e.alterS),
            ),
          )
          .reduce((a, b) => a < b ? a : b);
    }

    test('ein ungenauer frischer Fix schlägt einen genauen uralten', () {
      // Genau das ist der Fall aus dem Screenshot: getCurrentPosition liefert
      // drinnen einen 80-m-Fix, getLastKnownPosition einen 5-m-Fix von der
      // Fahrt vor zwei Stunden. Der alte wäre kilometerweit daneben.
      final gewaehlt = besteAbweichung([
        (acc: 80, speed: 0, alterS: 1), // gerade eben, drinnen
        (acc: 5, speed: 25, alterS: 7200), // top genau, aber von gestern
      ]);
      expect(gewaehlt, 80);
    });

    test('im Stand gewinnt der genauere Fix', () {
      final gewaehlt = besteAbweichung([
        (acc: 45, speed: 0, alterS: 3),
        (acc: 12, speed: 0, alterS: 8),
      ]);
      expect(gewaehlt, 12);
    });

    test('60-m-Schwelle: darunter kein Hinweis, darüber schon', () {
      const hinweisAb = 60.0;
      final gut = possibleOffsetMeters(
        accuracyMeters: 35,
        speedMetersPerSecond: 0,
        age: const Duration(seconds: 4),
      );
      final schlecht = possibleOffsetMeters(
        accuracyMeters: 90,
        speedMetersPerSecond: 0,
        age: const Duration(seconds: 4),
      );
      expect(gut, lessThan(hinweisAb));
      expect(schlecht, greaterThan(hinweisAb));
    });
  });
}
