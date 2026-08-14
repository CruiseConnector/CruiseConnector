import 'dart:io';

import 'package:cruise_connect/data/services/app_tutorial_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-14 (vucko Tutorial-Belohnung): Quell-Wachen für die Abschluss-
/// Belohnung (badge_15 „Gründungszeit" + 125 XP).
///
/// Warum QUELLTEXT-Tests: calculateAndSync und claimCompletionReward hängen
/// komplett an Supabase — ein Unit-Test müsste den Client so weit nachbauen,
/// dass er am Ende die Nachbildung prüft. Diese Wachen lesen stattdessen die
/// zwei Eigenschaften direkt ab, an denen alles hängt: (1) badge_15 wird OHNE
/// Bedingung qualifiziert (sonst kriegen Bestandsnutzer nie ihr Update-Badge),
/// (2) der Duplikat-Schutz steht VOR dem XP-Insert (sonst vergibt ein Replay
/// die 125 XP doppelt).
void main() {
  group('badge_15 Gründungszeit (Modell)', () {
    test('existiert in Badge.all mit Kategorie membership', () {
      final badge = Badge.getById(Badge.membershipBadgeId);
      expect(badge, isNotNull, reason: 'badge_15 fehlt in Badge.all');
      expect(badge!.category, 'membership');
      expect(badge.name, 'Gründungszeit');
      expect(
        badge.description.contains(Badge.membershipDatePlaceholder),
        isTrue,
        reason:
            'Die Beschreibung braucht den Datums-Platzhalter — er wird beim '
            'Rendern durch den Beitrittsmonat ersetzt.',
      );
    });

    test('resolveDescription setzt das Datum deutsch ein', () {
      final badge = Badge.getById(Badge.membershipBadgeId)!;
      final text = Badge.resolveDescription(
        badge,
        memberSince: DateTime(2026, 8, 1),
      );
      expect(text, contains('Dabei seit August 2026'));
      expect(text.contains(Badge.membershipDatePlaceholder), isFalse);
    });

    test('resolveDescription lässt andere Badges unangetastet', () {
      final other = Badge.getById('badge_02')!;
      expect(
        Badge.resolveDescription(other, memberSince: DateTime(2026, 8, 1)),
        other.description,
      );
    });

    test('die Abschluss-Belohnung beträgt 125 XP', () {
      expect(AppTutorialService.completionXp, 125);
    });
  });

  group('Quell-Wache: calculateAndSync qualifiziert badge_15 IMMER', () {
    late String rumpf;
    late String quelle;

    setUpAll(() {
      final datei = File('lib/data/services/gamification_service.dart');
      expect(datei.existsSync(), isTrue, reason: 'Service nicht gefunden');
      quelle = datei.readAsStringSync();

      final start = quelle.indexOf(
        'static Future<GamificationResult> calculateAndSync()',
      );
      expect(
        start,
        greaterThan(-1),
        reason: 'calculateAndSync umbenannt — diese Wache muss mit.',
      );
      final ende = quelle.indexOf('previousBadges', start);
      expect(ende, greaterThan(-1));
      rumpf = quelle.substring(start, ende);
    });

    test('badge_15 wird im Badge-Abschnitt qualifiziert', () {
      expect(
        rumpf.contains('currentlyQualifiedBadges.add(Badge.membershipBadgeId)'),
        isTrue,
        reason:
            'badge_15 muss in calculateAndSync qualifiziert werden — sonst '
            'bekommt niemand das Gründungszeit-Badge.',
      );
    });

    test('die Qualifizierung steht OHNE Bedingung da', () {
      // Die Zeile mit dem Add darf kein `if` tragen — jeder registrierte
      // Nutzer qualifiziert sich, auch Bestandsnutzer nach dem Update.
      final zeile = rumpf
          .split('\n')
          .firstWhere(
            (line) => line.contains(
              'currentlyQualifiedBadges.add(Badge.membershipBadgeId)',
            ),
            orElse: () => '',
          );
      expect(zeile, isNotEmpty);
      expect(
        zeile.trimLeft().startsWith('if'),
        isFalse,
        reason:
            'badge_15 hängt an KEINER Bedingung — wer hier ein if einbaut, '
            'nimmt Bestandsnutzern das Update-Badge.',
      );
      expect(zeile.contains('if ('), isFalse);
    });
  });

  group('Quell-Wache: Duplikat-Schutz der 125-XP-Vergabe', () {
    late String rumpf;

    setUpAll(() {
      final datei = File('lib/data/services/app_tutorial_service.dart');
      expect(datei.existsSync(), isTrue, reason: 'Service nicht gefunden');
      final quelle = datei.readAsStringSync();

      final start = quelle.indexOf('claimCompletionReward()');
      expect(
        start,
        greaterThan(-1),
        reason: 'claimCompletionReward umbenannt — diese Wache muss mit.',
      );
      rumpf = quelle.substring(start);
    });

    test('lokales Flag als Schnellpfad VOR allem anderen', () {
      final flagCheck = rumpf.indexOf('rewardClaimedKey');
      final dbQuery = rumpf.indexOf("from('user_drive_sessions')");
      expect(flagCheck, greaterThan(-1));
      expect(dbQuery, greaterThan(-1));
      expect(
        flagCheck,
        lessThan(dbQuery),
        reason: 'Das SharedPreferences-Flag muss vor dem Netz-Query stehen.',
      );
    });

    test('Supabase-Query auf bestehende Vergabe steht VOR dem Insert', () {
      final query = rumpf.indexOf("eq('xp_awarded', completionXp)");
      final insert = rumpf.indexOf('recordDriveSession');
      expect(
        query,
        greaterThan(-1),
        reason:
            'Vor dem Insert muss per Query geprüft werden, ob schon eine '
            'Session mit xp_awarded=125 und distance 0 existiert.',
      );
      expect(rumpf.contains("eq('distance_km', 0)"), isTrue);
      expect(insert, greaterThan(-1));
      expect(
        query,
        lessThan(insert),
        reason:
            'Query nach dem Insert wäre wirkungslos — ein Replay würde die '
            '125 XP doppelt vergeben.',
      );
    });

    test('die Belohnungszeile zählt NICHT als abgeschlossene Fahrt', () {
      expect(
        rumpf.contains('completedAtEnd: false'),
        isTrue,
        reason:
            'completedAtEnd: true würde badge_02 („Erste Fahrt") fürs '
            'Tutorial vergeben.',
      );
    });
  });
}
