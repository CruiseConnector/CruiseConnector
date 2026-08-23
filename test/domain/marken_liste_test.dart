import 'dart:io';

import 'package:cruise_connect/data/services/vehicle_api_service.dart';
import 'package:cruise_connect/domain/fahrzeug_grenzen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 — Aufgabe 2.1 „Fahrzeug-Marken normalisieren und gruppieren".
///
/// Vucko wörtlich (Aufnahme 2 vom 23.08., 14:54:40):
/// „B-M-W ganz in Caps geschrieben und groß geschrieben soll das Gleiche sein
/// wie B groß, M klein und W klein — oder irgendeine andere Schreibweise.
/// Wichtig ist, dass das [wortident] ist, nicht ob es jetzt groß oder klein
/// geschrieben ist."
///
/// Gemessener Stand am 24.08. in der Produktivdatenbank:
///   profile_vehicles: 77 Zeilen mit Marke, 36 verschiedene Schreibweisen.
///   profiles.car_brand: 128 Zeilen mit Marke, 48 verschiedene Schreibweisen.
///
/// Zuständig ist seit der Migration 20260824101000 die DATENBANK
/// (`public.vehicle_brand_canonical`, aufgerufen von einem Trigger auf beiden
/// Tabellen). Diese Datei prüft, dass der Client nicht mehr dagegenhält.
void main() {
  final quelleGrenzen = File(
    'lib/domain/fahrzeug_grenzen.dart',
  ).readAsStringSync();
  final quelleApi = File(
    'lib/data/services/vehicle_api_service.dart',
  ).readAsStringSync();
  final quelleMigration = File(
    'supabase/migrations/20260824101000_marken_vereinheitlichen.sql',
  ).readAsStringSync();

  group('normalisiereMarke rät nicht mehr', () {
    // Diese drei Fälle waren vor dem 24.08. nachweislich falsch. Sie sind der
    // Grund, warum der Client die Schreibweise nicht mehr bestimmt.
    test('GasGas bleibt GasGas (vorher: Gasgas)', () {
      expect(FahrzeugGrenzen.normalisiereMarke('GasGas'), 'GasGas');
    });
    test('McLaren bleibt McLaren (vorher: Mclaren)', () {
      expect(FahrzeugGrenzen.normalisiereMarke('McLaren'), 'McLaren');
    });
    test('Mini und Seat werden nicht gegen die eigene Liste gedreht', () {
      // Vorher: MINI und SEAT, obwohl die Vorschlagsliste „Mini" und „Seat"
      // anbietet und die Datenbank genau so kanonisiert.
      expect(FahrzeugGrenzen.normalisiereMarke('Mini'), 'Mini');
      expect(FahrzeugGrenzen.normalisiereMarke('Seat'), 'Seat');
    });
    test('Kleingeschriebenes bleibt unangetastet, der Server dreht es', () {
      // Der Trigger auf profile_vehicles.brand macht daraus BMW. Gemessen am
      // 24.08.: vehicle_brand_canonical('bmw') = 'BMW'.
      expect(FahrzeugGrenzen.normalisiereMarke('bmw'), 'bmw');
    });
    test('Leerraum wird weiterhin aufgeräumt', () {
      expect(FahrzeugGrenzen.normalisiereMarke('  BMW  '), 'BMW');
      expect(FahrzeugGrenzen.normalisiereMarke('alfa   romeo'), 'alfa romeo');
      expect(FahrzeugGrenzen.normalisiereMarke('   '), '');
    });
    test('Die Ausnahmeliste _grossgeschrieben ist gelöscht', () {
      expect(
        quelleGrenzen.contains('_grossgeschrieben'),
        isFalse,
        reason:
            'Solange die Liste existiert, gibt es zwei Stellen, die über '
            'Markenschreibweisen entscheiden.',
      );
      expect(quelleGrenzen.contains('vehicle_brand_canonical'), isTrue);
    });
  });

  group('Die gepflegte Liste ist die Quelle der Schreibweise', () {
    test('Sie deckt sich zeichengleich mit vehicle_brand_alias', () {
      // Erste Spalte der VALUES-Liste in der Migration = kanonische Marke.
      final kanonisch = RegExp(r"\('([^']+)','[^']*'\)")
          .allMatches(quelleMigration)
          .map((m) => m.group(1)!)
          .toSet();
      final imClient = VehicleApiService.kuratierteMarken
          .map((m) => m.name)
          .toSet();
      expect(kanonisch, isNotEmpty, reason: 'Migration nicht lesbar');
      expect(
        imClient.difference(kanonisch),
        isEmpty,
        reason:
            'Der Client schlägt eine Schreibweise vor, die der Server nicht '
            'kennt. Dann schreibt die Datenbank etwas anderes, als der '
            'Nutzer angetippt hat.',
      );
      expect(
        kanonisch.difference(imClient),
        isEmpty,
        reason: 'Der Server kennt eine Marke, die niemand vorgeschlagen bekommt.',
      );
    });

    test('Keine Dubletten in der Vorschlagsliste', () {
      final namen = VehicleApiService.kuratierteMarken
          .map((m) => m.name)
          .toList();
      expect(namen.toSet().length, namen.length);
    });

    test('Motorradmarken sind drin — vorher war die Liste reine Autoliste', () {
      final namen = VehicleApiService.kuratierteMarken
          .map((m) => m.name)
          .toSet();
      // Gemessen am 24.08. über get_brand_overview: Beta 8 Personen,
      // Rieju 5, Aprilia 3. Alle drei unter den zehn häufigsten Marken.
      for (final marke in ['Beta', 'Rieju', 'Aprilia', 'KTM', 'Ducati']) {
        expect(namen, contains(marke), reason: marke);
      }
    });

    test('Die gepflegte Liste antwortet ohne Netz und in richtiger Schrift', () {
      String erster(String eingabe) =>
          VehicleApiService.gepflegteTreffer(eingabe).first.name;
      expect(erster('bm'), 'BMW');
      // Die NHTSA liefert alles in Großbuchstaben; „GasGas" und „McLaren"
      // bekäme man von dort nie richtig geschrieben.
      expect(erster('gasg'), 'GasGas');
      expect(erster('mcla'), 'McLaren');
      // Skoda und Seat fehlen in der NHTSA komplett.
      expect(erster('skod'), 'Skoda');
      expect(erster('seat'), 'Seat');
      // Motorrad, vorher gar kein Treffer.
      expect(erster('rieju'), 'Rieju');
    });

    test('Die gepflegte Liste kommt VOR der NHTSA-Abfrage', () {
      final posListe = quelleApi.indexOf('gepflegteTreffer(query)');
      final posNetz = quelleApi.indexOf('await _loadMakes()');
      expect(posListe, greaterThan(-1));
      expect(posNetz, greaterThan(-1));
      expect(
        posListe,
        lessThan(posNetz),
        reason:
            'Die US-Behördenliste darf die gepflegten Schreibweisen nur '
            'ergänzen, nie überschreiben.',
      );
      expect(
        quelleApi.contains('_firmenmuell'),
        isTrue,
        reason: '„102 IRONWORKS, INC." ist keine Marke.',
      );
    });
  });

  group('Verdrahtung im Onboarding', () {
    test('Das blanke Marken-Textfeld hat jetzt Vorschläge', () {
      final wizard = File(
        'lib/presentation/pages/onboarding/onboarding_wizard_page.dart',
      ).readAsStringSync();
      expect(wizard.contains('_markenVorschlaege(accent)'), isTrue);
      expect(wizard.contains('VehicleApiService.kuratierteMarken'), isTrue);
    });
  });
}
