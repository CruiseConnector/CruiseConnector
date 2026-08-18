import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-18 (Aufgabe 4.1, Vucko-Sprachnachricht 08 vom 16.08.):
/// „Gründungs-Badge: Runterschrauben, dass man es nur einmal bekommt und nicht
/// alle fünf Minuten."
///
/// Ursache war keine fehlende Bedingung im Client, sondern eine hartkodierte
/// Whitelist in der Datenbank: `normalize_badge_ids` kannte nur badge_01 bis
/// badge_10, badge_13 und badge_14. Alles darüber wurde beim Speichern still
/// weggeworfen. Gemessen am 18.08. in der Produktivdatenbank: 0 von 151
/// Profilen hatten badge_15 — obwohl die App es bei jedem Sync bedingungslos
/// vergibt. Beim nächsten Sync fehlte es also wieder, galt erneut als „neu",
/// und das Verleih-Popup ging wieder auf. Jeder Tab-Wechsel auf die Startseite
/// löst einen Sync aus; das ist Vuckos „alle fünf Minuten".
///
/// Die Whitelist ist durch eine Musterprüfung ersetzt (Migration
/// 20260818230000). Damit gibt es keine zweite Liste mehr, die man beim
/// Anlegen eines Badges vergessen kann. Dieser Test hält fest, dass jede
/// Badge-ID im Dart-Modell diesem Muster genügt — sonst wäre sie in der
/// Datenbank wieder unsichtbar.
void main() {
  /// Exakt das Muster aus der SQL-Funktion: `id ~ '^badge_[0-9]{2}$'`
  final dbMuster = RegExp(r'^badge_[0-9]{2}$');

  group('Badge-IDs passen zur Datenbank', () {
    test('jede ID im Modell erfüllt das Muster der Datenbank', () {
      final verstoesse = Badge.all
          .map((b) => b.id)
          .where((id) => !dbMuster.hasMatch(id))
          .toList();
      expect(
        verstoesse,
        isEmpty,
        reason:
            'Diese IDs würde die Datenbank beim Speichern still verwerfen und '
            'das Verleih-Popup ginge bei jedem Sync erneut auf: $verstoesse',
      );
    });

    test('das Gründungs-Badge ist dabei', () {
      expect(dbMuster.hasMatch(Badge.membershipBadgeId), isTrue);
      expect(
        Badge.all.any((b) => b.id == Badge.membershipBadgeId),
        isTrue,
        reason: 'badge_15 muss im Katalog stehen',
      );
    });

    test('keine doppelten IDs', () {
      final ids = Badge.all.map((b) => b.id).toList();
      expect(ids.length, ids.toSet().length, reason: 'IDs müssen eindeutig sein');
    });

    test('die Migration prüft per Muster, nicht per Liste', () {
      final sql = File(
        'supabase/migrations/20260818230000_badge_whitelist_ohne_pflege.sql',
      ).readAsStringSync();
      expect(
        sql.contains(r"id ~ '^badge_[0-9]{2}$'"),
        isTrue,
        reason:
            'Wer hier wieder eine Aufzählung einbaut, holt sich die '
            'Doppelpflege und damit den Dauer-Popup-Fehler zurück',
      );
      expect(
        sql.contains('badge_15'),
        isTrue,
        reason: 'Der Nachzug für die Bestandsprofile muss drinbleiben',
      );
    });
  });

  group('Der Client feiert nur, was wirklich ankam', () {
    test('die Rücklese-Sicherung steht im Dienst', () {
      final quelle = File(
        'lib/data/services/gamification_service.dart',
      ).readAsStringSync();
      expect(
        quelle.contains('bestaetigteBadges'),
        isTrue,
        reason: 'Nach dem Schreiben muss zurückgelesen werden',
      );
      expect(
        quelle.contains(
          'newBadges.removeWhere((b) => !bestaetigteBadges.contains(b));',
        ),
        isTrue,
        reason:
            'Ein Badge, das die Datenbank verschluckt, darf nicht als neu '
            'gemeldet werden — sonst spammt es bei jedem Sync erneut',
      );
    });

    test('normalizeBadgeIds wirft nichts Gültiges weg', () {
      final alle = Badge.all.map((b) => b.id).toList();
      final normalisiert = GamificationService.normalizeBadgeIds(alle);
      expect(
        normalisiert.toSet(),
        alle.toSet(),
        reason: 'Der Client darf keine eigene, engere Whitelist haben',
      );
    });
  });
}
