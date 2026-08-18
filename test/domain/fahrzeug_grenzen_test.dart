import 'dart:io';

import 'package:cruise_connect/domain/fahrzeug_grenzen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Defekt 4 aus dem Produktionsbericht): „Das PS-Feld nimmt jede
/// Zahl an." Gemessen: Skoda Fabia, 1.100 PS, 0-100 in 1,2 s, eingetragen am
/// 17.08. um 22:03. Abnahmekriterium: genau diese Eingabe lässt sich nicht
/// mehr speichern, und der Nutzer sieht warum.
void main() {
  // ── Wichtig zum Auftrag ──────────────────────────────────────────────
  // Der Auftrag nennt zwei Dinge, die sich widersprechen: „PS: 1 bis 1500"
  // UND „eine Eingabe von 1.100 PS lässt sich nicht mehr speichern".
  // 1.100 liegt innerhalb von 1 bis 1500. Eine reine Zahlengrenze kann
  // „1.100 PS in einem Fabia" nicht erkennen — dazu müsste sie das Modell
  // kennen. Umgesetzt sind die im Auftrag genannten Grenzen; der echte
  // Eintrag scheitert trotzdem, nämlich an den 1,2 Sekunden auf 100.
  group('Leistung', () {
    test('1.100 PS liegt innerhalb der beauftragten Grenze 1 bis 1500', () {
      expect(FahrzeugGrenzen.pruefeLeistung('1100'), isNull);
    });
    test('95 PS ist in Ordnung', () {
      expect(FahrzeugGrenzen.pruefeLeistung('95'), isNull);
    });
    test('Grenzen selbst sind erlaubt, ein Schritt darüber nicht', () {
      expect(FahrzeugGrenzen.pruefeLeistung('1500'), isNull);
      expect(FahrzeugGrenzen.pruefeLeistung('1501'), isNotNull);
      expect(FahrzeugGrenzen.pruefeLeistung('1'), isNull);
      expect(FahrzeugGrenzen.pruefeLeistung('0'), isNotNull);
    });
    test('Leeres Feld bleibt erlaubt', () {
      expect(FahrzeugGrenzen.pruefeLeistung(''), isNull);
      expect(FahrzeugGrenzen.pruefeLeistung(null), isNull);
    });
  });

  group('Höchstgeschwindigkeit', () {
    test('900 km/h wird abgelehnt, 340 bleibt erlaubt', () {
      expect(FahrzeugGrenzen.pruefeTopSpeed('900'), isNotNull);
      // Die drei Fahrzeuge über 300 km/h aus dem Bericht sind plausible
      // Supersportler und sollen NICHT verschwinden.
      expect(FahrzeugGrenzen.pruefeTopSpeed('340'), isNull);
      expect(FahrzeugGrenzen.pruefeTopSpeed('400'), isNull);
      expect(FahrzeugGrenzen.pruefeTopSpeed('401'), isNotNull);
    });
  });

  group('0 auf 100', () {
    test('1,2 Sekunden wird abgelehnt (der echte Eintrag)', () {
      expect(FahrzeugGrenzen.pruefeNullAufHundert('1,2'), isNotNull);
    });
    test('10,6 Sekunden ist in Ordnung, Punkt wie Komma', () {
      expect(FahrzeugGrenzen.pruefeNullAufHundert('10,6'), isNull);
      expect(FahrzeugGrenzen.pruefeNullAufHundert('10.6'), isNull);
    });
    test('Grenzen', () {
      expect(FahrzeugGrenzen.pruefeNullAufHundert('1,5'), isNull);
      expect(FahrzeugGrenzen.pruefeNullAufHundert('1,4'), isNotNull);
      expect(FahrzeugGrenzen.pruefeNullAufHundert('30'), isNull);
      expect(FahrzeugGrenzen.pruefeNullAufHundert('31'), isNotNull);
    });
  });

  group('Markenschreibweise', () {
    test('audi, Audi und  AUDI  werden dieselbe Marke', () {
      const erwartet = 'Audi';
      for (final roh in ['audi', 'Audi', '  AUDI  ', 'aUdI']) {
        expect(FahrzeugGrenzen.normalisiereMarke(roh), erwartet, reason: roh);
      }
    });
    test('Abkürzungen bleiben groß', () {
      expect(FahrzeugGrenzen.normalisiereMarke('bmw'), 'BMW');
      expect(FahrzeugGrenzen.normalisiereMarke('vw'), 'VW');
      expect(FahrzeugGrenzen.normalisiereMarke('ktm'), 'KTM');
    });
    test('Bindestrich- und Mehrwortnamen', () {
      expect(
        FahrzeugGrenzen.normalisiereMarke('mercedes-benz'),
        'Mercedes-Benz',
      );
      expect(FahrzeugGrenzen.normalisiereMarke('alfa   romeo'), 'Alfa Romeo');
    });
    test('Leer bleibt leer', () {
      expect(FahrzeugGrenzen.normalisiereMarke('   '), '');
    });
  });

  group('Fahrzeuge, die gerade nicht im Formular sichtbar sind', () {
    test('unplausibler Entwurf wird beim Speichern gefunden', () {
      final fehler = FahrzeugGrenzen.ersterFehlerImEntwurf({
        'brand': 'Skoda',
        'horsepower': 1600,
      });
      expect(fehler, isNotNull);
      expect(fehler, contains('Skoda'));
    });

    test('Der echte Fabia-Eintrag vom 17.08. ist nicht mehr speicherbar', () {
      // Genau die Zeile, die am 18.08. in der Produktivdatenbank stand.
      final fehler = FahrzeugGrenzen.ersterFehlerImEntwurf({
        'brand': 'Skoda',
        'model': 'Fabia',
        'horsepower': 1100,
        'zero_to_hundred_seconds': 1.2,
      });
      expect(fehler, isNotNull, reason: 'Abnahmekriterium aus dem Auftrag');
      expect(fehler, contains('Sekunden'));
    });
    test('sauberer Entwurf meldet nichts', () {
      expect(
        FahrzeugGrenzen.ersterFehlerImEntwurf({
          'brand': 'Skoda',
          'horsepower': 95,
          'zero_to_hundred_seconds': 10.6,
        }),
        isNull,
      );
    });
  });

  group('Verdrahtung', () {
    test('Die drei Felder haben einen validator und das Formular prüft', () {
      final seite = File(
        'lib/presentation/pages/edit_profile_page.dart',
      ).readAsStringSync();
      expect(seite.contains('validator: FahrzeugGrenzen.pruefeLeistung'), isTrue);
      expect(seite.contains('validator: FahrzeugGrenzen.pruefeTopSpeed'), isTrue);
      expect(
        seite.contains('validator: FahrzeugGrenzen.pruefeNullAufHundert'),
        isTrue,
      );
      expect(seite.contains('_garageFormKey.currentState?.validate()'), isTrue);
      expect(
        seite.contains('FahrzeugGrenzen.normalisiereMarke(_carBrandController.text)'),
        isTrue,
      );
    });

    test('Die Datenbank hat dieselben Grenzen', () {
      final sql = File(
        'supabase/migrations/20260818130000_fahrzeug_plausibilitaet.sql',
      ).readAsStringSync();
      expect(sql.contains('horsepower >= 1 and horsepower <= 1500'), isTrue);
      expect(sql.contains('top_speed >= 1 and top_speed <= 400'), isTrue);
      expect(
        sql.contains(
          'zero_to_hundred_seconds >= 1.5 and zero_to_hundred_seconds <= 30',
        ),
        isTrue,
      );
    });
  });
}
