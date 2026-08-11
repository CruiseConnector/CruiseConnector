import 'dart:io';

import 'package:cruise_connect/data/services/social_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-11 (vucko): „mir wird den ganzen Tag nur EINE Person angezeigt ...
/// wir sind schon 93 Personen, und es kann nicht sein, dass mir eine Person
/// vorgeschlagen wird. Wenn man sie wegklickt, sollen wie bei Instagram neue
/// dazukommen."
///
/// Drei Ursachen, drei Regeln:
///  1. Der Freunde-von-Freunden-Pfad kehrte mit auch nur EINEM Treffer zurueck
///     und liess den Fallback nie laufen.
///  2. Weggeklickte blieben FUER IMMER ausgeschlossen — bei 93 Nutzern
///     erschoepfte sich der Pool in Tagen.
///  3. Der Entdecken-Tab entfernte nur lokal und fuellte nie nach.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wegklicken verfaellt (Regel 2)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('frisch Weggeklickte sind ausgeschlossen', () async {
      await SocialService.dismissSuggestedUser('u1');
      final ids = await SocialService.getDismissedSuggestionIds();
      expect(ids, contains('u1'));
    });

    test('nach 14 Tagen tauchen sie wieder auf', () async {
      final vor15Tagen = DateTime.now()
          .subtract(const Duration(days: 15))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'suggested_users_dismissed_v1': <String>['alt|$vor15Tagen'],
      });
      final ids = await SocialService.getDismissedSuggestionIds();
      expect(
        ids,
        isNot(contains('alt')),
        reason: 'sonst erschoepft sich der Pool bei 93 Nutzern fuer immer',
      );
    });

    test('Alt-Eintraege ohne Zeitstempel bleiben erst mal ausgeschlossen', () async {
      // Bestandsgeraete haben Eintraege im alten Format (nur die ID). Die
      // duerfen nicht schlagartig alle wiederkommen — die Uhr beginnt beim
      // ersten Lesen zu laufen.
      SharedPreferences.setMockInitialValues({
        'suggested_users_dismissed_v1': <String>['legacy_id'],
      });
      final ids = await SocialService.getDismissedSuggestionIds();
      expect(ids, contains('legacy_id'));

      // Und beim zweiten Lesen sind sie migriert (Format id|zeit).
      final prefs = await SharedPreferences.getInstance();
      final roh = prefs.getStringList('suggested_users_dismissed_v1')!;
      expect(roh.single, startsWith('legacy_id|'));
    });
  });

  group('Struktur-Regeln in der Quelle (Regeln 1 und 3)', () {
    late String socialQuelle;
    late String communityQuelle;

    setUpAll(() {
      socialQuelle = File(
        'lib/data/services/social_service.dart',
      ).readAsStringSync();
      communityQuelle = File(
        'lib/presentation/pages/community_page.dart',
      ).readAsStringSync();
    });

    test('Freunde-von-Freunden fuellt auf statt allein zurueckzukehren', () {
      final start = socialQuelle.indexOf('mutual_count');
      final rumpf = socialQuelle.substring(start, start + 1400);
      expect(
        rumpf.contains('ergebnis[sid] = suggestions[sid]!'),
        isTrue,
        reason: 'FoF-Treffer muessen gesammelt werden',
      );
      expect(
        RegExp(r'return taken\.map').hasMatch(socialQuelle),
        isFalse,
        reason:
            'die alte Fruehrueckkehr wuerde bei einem duennen Netz wieder nur '
            'eine Person liefern',
      );
    });

    test('der Auffueller bevorzugt Landsleute', () {
      expect(socialQuelle.contains('country_code'), isTrue);
      expect(
        socialQuelle.contains('meinLand'),
        isTrue,
        reason: 'vucko: „mehr Profile in der Umgebung"',
      );
    });

    test('Entdecken fuellt nach dem Wegklicken nach', () {
      expect(
        communityQuelle.contains('_fuelleVorschlaegeNach'),
        isTrue,
      );
      // Beide Wege muessen nachfuellen: Wegklicken UND angenommenes Folgen.
      final treffer = RegExp(
        r'unawaited\(_fuelleVorschlaegeNach\(\)\)',
      ).allMatches(communityQuelle).length;
      expect(
        treffer,
        greaterThanOrEqualTo(2),
        reason: 'Wegklicken und Folgen muessen beide nachfuellen',
      );
    });
  });
}
