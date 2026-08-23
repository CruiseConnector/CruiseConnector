import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-08-24 — Aufgabe 2.2 „Analytics-Page: Marken-Übersicht mit Drilldown".
///
/// Vucko wörtlich (Aufnahme 2 vom 23.08., 14:54:40):
/// „Und dass man auch wirklich in der Analytics-Page die ganzen Marken sieht,
/// wo vertreten sind. Und dann, wenn man draufklickt, die Leute sieht, wo
/// unter diesen Marken sind. [...] die und die Person hat den BMW, die und
/// die Person hat jetzt einen Skoda [...] Und dass man auch wirklich bei der
/// Analytics-Page dann gruppieren kann: Autos, Motorräder oder alle."
///
/// Die Seite hat 3.400+ Zeilen und hängt an Supabase, Provider und einem
/// TabController. Ein Widget-Test müsste eine halbe App hochfahren und würde
/// vor allem die Attrappen testen. Geprüft wird deshalb die Verdrahtung: dass
/// der Reiter existiert, dass die drei Filterwerte zeichengleich das sind,
/// was die beiden RPCs entgegennehmen, und dass der Filter an BEIDEN
/// Ladepfaden hängt. Genau daran wäre die Umsetzung sonst still gescheitert.
///
/// Gemessen am 24.08. über die RPC get_brand_overview('all'):
///   BMW 30 Personen / 31 Fahrzeuge, Volkswagen 16, Audi 14, Beta 8,
///   Mercedes-Benz 7, Skoda 6. Mit 'car' bleiben 20 Marken übrig.
void main() {
  final seite = File(
    'lib/presentation/pages/analytics_page.dart',
  ).readAsStringSync();
  final migration = File(
    'supabase/migrations/20260824101000_marken_vereinheitlichen.sql',
  ).readAsStringSync();

  group('Der Reiter existiert', () {
    test('Sechs Reiter statt fünf, der sechste heißt Marken', () {
      expect(seite.contains('TabController(length: 6'), isTrue);
      expect(seite.contains("text: 'Marken'"), isTrue);
      expect(seite.contains('_buildMarkenTab()'), isTrue);
      expect(
        seite.contains('case 5:'),
        isTrue,
        reason: 'Ohne den Zweig zeigt der neue Reiter die Badges.',
      );
    });

    test('Kein Admin-Gate: die Seite ist Reiter 3 der normalen Navigation', () {
      final markenTeil = seite.substring(seite.indexOf('_buildMarkenTab'));
      expect(markenTeil.contains('isAdmin'), isFalse);
      expect(markenTeil.contains('is_admin'), isFalse);
    });
  });

  group('Der Filter Autos / Motorräder / Alle', () {
    test('Genau drei Zustände, mit den Beschriftungen aus dem Auftrag', () {
      expect(seite.contains("autos('car', 'Autos')"), isTrue);
      expect(seite.contains("motorraeder('motorcycle', 'Motorräder')"), isTrue);
      expect(seite.contains("alle('all', 'Alle')"), isTrue);
    });

    test('Die drei Werte sind genau die, die die Datenbank kennt', () {
      // Die RPCs mappen alles ausser car/motorcycle auf all. Ein Tippfehler
      // im Client würde also lautlos zu „Alle" werden, statt zu scheitern.
      expect(
        migration.contains("in ('car', 'motorcycle')"),
        isTrue,
        reason: 'Signatur der RPCs hat sich geändert',
      );
      expect(migration.contains("coalesce(p_vehicle_type, 'all')"), isTrue);
    });

    test('Der Filter wirkt auf BEIDE Ansichten, auch nach dem Drilldown', () {
      // Übersicht
      expect(
        seite.contains("'p_vehicle_type': filter.rpcWert"),
        isTrue,
        reason: 'Die Übersicht ignoriert den Filter.',
      );
      // Drilldown
      expect(
        seite.contains("'p_vehicle_type': _fahrzeugFilter.rpcWert"),
        isTrue,
        reason: 'Der Drilldown ignoriert den Filter.',
      );
      // Umschalten lädt beides nach, solange eine Marke offen ist.
      final umschalter = seite.substring(
        seite.indexOf('void _setzeFahrzeugFilter'),
        seite.indexOf('Widget _buildMarkenTab'),
      );
      expect(umschalter.contains('_ladeMarken()'), isTrue);
      expect(umschalter.contains('_ladeMarkenPersonen(offen)'), isTrue);
    });
  });

  group('Die zwei Ansichten', () {
    test('Beide RPCs werden mit genau ihrem Namen gerufen', () {
      expect(seite.contains("rpc(\n        'get_brand_overview'"), isTrue);
      expect(seite.contains("rpc(\n        'get_brand_members'"), isTrue);
    });

    test('Gruppiert wird serverseitig, nicht im Client', () {
      // Der Client hat die Gruppierung bis zum 24.08. selbst geraten. Genau
      // daran sind „BMW" und „Bmw" zu zwei Marken geworden.
      final ladeteil = seite.substring(
        seite.indexOf('Future<void> _ladeMarken('),
        seite.indexOf('Future<void> _ladeMarkenPersonen('),
      );
      expect(ladeteil.contains('toUpperCase()'), isFalse);
      expect(ladeteil.contains('toLowerCase()'), isFalse);
    });

    test('Der Drilldown zeigt Person UND Fahrzeug', () {
      // „die und die Person hat den BMW, die und die Person hat jetzt einen
      // Skoda" — eine reine Namensliste erfüllt das nicht.
      expect(seite.contains('String get fahrzeugZeile'), isTrue);
      expect(seite.contains('person.fahrzeugZeile'), isTrue);
      expect(seite.contains('person.anzeigeName'), isTrue);
    });

    test('Tap auf eine Person öffnet das fremde Profil', () {
      final zeile = seite.substring(
        seite.indexOf('Widget _buildMarkenPersonZeile'),
      );
      expect(zeile.contains('UserProfilePage('), isTrue);
      expect(zeile.contains('userId: person.userId'), isTrue);
    });

    test('Tap auf eine Marke öffnet den Drilldown', () {
      expect(seite.contains('onTap: () => _oeffneMarke(eintrag.marke)'), isTrue);
      expect(seite.contains('void _schliesseMarke()'), isTrue);
    });

    test('Skelett statt Kreis-Spinner (Projektregel)', () {
      final markenTeil = seite.substring(seite.indexOf('Widget _buildMarkenTab'));
      expect(markenTeil.contains('_MarkenSkelett()'), isTrue);
      expect(markenTeil.contains('CircularProgressIndicator'), isFalse);
    });
  });

  group('Deutsche Texte', () {
    test('Echte Umlaute, keine ue/oe/ae in sichtbaren Texten', () {
      for (final text in [
        "'Motorräder'",
        "'Alle Motorradmarken in der Community.'",
        "'Noch kein Motorrad in der Garage.'",
      ]) {
        expect(seite.contains(text), isTrue, reason: text);
      }
      expect(seite.contains("'Motorraeder'"), isFalse);
    });
  });
}
