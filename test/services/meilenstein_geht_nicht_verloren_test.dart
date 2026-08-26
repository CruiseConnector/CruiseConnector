import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';

/// 2026-08-26 (vucko, Aufgabe 7): „Ich habe die 1000-Kilometer-Marke erreicht,
/// aber die Animation dazu ist leider nicht gekommen. Sehr frustrierend, weil
/// ich einen Meilenstein erreicht habe und nicht mitbekomme, dass ich ihn
/// erreicht habe."
///
/// Am Video belegt: Bei Fahrtende standen 992 km, beim Oeffnen der Auswertung
/// 1007 km. Das Abzeichen wurde also beim Abgleich der AUSWERTUNG faellig — und
/// die kannte keine Feier. Danach stand es im Profil und galt nie wieder als
/// neu.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Die Warteschlange verliert keinen Meilenstein', () {
    test('vorgemerkt wird, was neu ist', () async {
      await OffeneAuszeichnungen.merken(['badge_km_1000']);
      expect(await OffeneAuszeichnungen.offene(), ['badge_km_1000']);
    });

    test('doppeltes Vormerken erzeugt keine doppelte Feier', () async {
      await OffeneAuszeichnungen.merken(['badge_km_1000']);
      await OffeneAuszeichnungen.merken(['badge_km_1000']);
      await OffeneAuszeichnungen.merken(['badge_km_1000', 'badge_nacht']);
      expect(
        await OffeneAuszeichnungen.offene(),
        ['badge_km_1000', 'badge_nacht'],
      );
    });

    test('quittiert wird erst nach der Feier, und nur das Gefeierte', () async {
      await OffeneAuszeichnungen.merken(['a', 'b', 'c']);
      await OffeneAuszeichnungen.quittieren(['a', 'c']);
      expect(await OffeneAuszeichnungen.offene(), ['b']);
    });

    test('leere Listen tun nichts', () async {
      await OffeneAuszeichnungen.merken(const []);
      expect(await OffeneAuszeichnungen.offene(), isEmpty);
      await OffeneAuszeichnungen.quittieren(const []);
      expect(await OffeneAuszeichnungen.offene(), isEmpty);
    });

    test('gemerkt wird plattenfest und kontogebunden', () {
      // Nicht im Arbeitsspeicher: ein App-Neustart darf einen Meilenstein
      // nicht schlucken. Und zwei Konten auf einem Handy duerfen sich die
      // Warteschlange nicht teilen.
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      final start = quelle.indexOf('class OffeneAuszeichnungen');
      expect(start, greaterThan(-1));
      final block = quelle.substring(start, start + 2600);
      expect(block.contains('SharedPreferences'), isTrue);
      expect(block.contains('NutzerPrefsSchluessel.fuer'), isTrue);
    });
  });

  group('Quelltext-Waechter', () {
    test('der Abgleich merkt jedes neue Abzeichen vor', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      expect(
        quelle.contains('OffeneAuszeichnungen.merken(newBadges)'),
        isTrue,
        reason: 'sonst geht ein Abzeichen aus einem stillen Abgleich verloren',
      );
    });

    test('die Auswertung holt die Feier nach', () {
      // Genau der Bildschirm, auf dem die 1000 km untergingen.
      final quelle = File(
        'lib/presentation/pages/analytics_page.dart',
      ).readAsStringSync();
      expect(quelle.contains('zeigeOffeneAuszeichnungen'), isTrue);
    });

    test('keine Feier haengt mehr allein an newBadges', () {
      for (final p in const [
        'lib/presentation/pages/cruise_mode_page.dart',
        'lib/presentation/pages/home_content_page.dart',
        'lib/presentation/pages/create_post_page.dart',
        'lib/presentation/pages/community_page.dart',
      ]) {
        final q = File(p).readAsStringSync();
        expect(
          q.contains('badges: gamResult.newBadges') ||
              q.contains('badges: result.newBadges'),
          isFalse,
          reason:
              '$p feiert noch direkt aus dem Ergebnis statt aus der '
              'Warteschlange — dann geht ein stiller Abgleich wieder verloren',
        );
      }
    });
  });
}
