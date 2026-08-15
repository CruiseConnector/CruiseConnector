import 'dart:io';

import 'package:cruise_connect/domain/models/badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-15 (vucko): „bei den gesperrten Badges soll man sehen, was sie
/// machen muessen — z. B. 1000 km fahren — und wenn sie schon 274 gefahren
/// sind, den Fortschritt."
void main() {
  BadgeFortschritt? f(String id, {double km = 274, int level = 8, int rides = 3,
      int group = 0, int posts = 0, double longest = 40, double hours = 6}) =>
      badgeFortschrittFuer(
        badgeId: id,
        level: level,
        totalKm: km,
        totalHours: hours,
        completedRides: rides,
        completedGroupRides: group,
        routePosts: posts,
        createdGroups: 0,
        savedRoutes: 2,
        longestRideKm: longest,
      );

  test('Vuckos Beispiel: 274 von 500 km', () {
    final p = f('badge_06')!;
    expect(p.zahlen, '274 von 500 km');
    expect(p.anteil, closeTo(0.548, 0.001));
    expect(p.anleitung, contains('500 Kilometer'));
  });

  test('Fahrten-Badges zaehlen abgeschlossene Fahrten', () {
    expect(f('badge_17')!.zahlen, '3 von 10 Fahrten');
    expect(f('badge_18')!.zahlen, '3 von 50 Fahrten');
  });

  test('Langstrecke misst die LAENGSTE Fahrt, nicht die Summe', () {
    final p = f('badge_20', km: 900, longest: 40)!;
    expect(p.aktuell, 40);
    expect(p.ziel, 100);
  });

  test('der Anteil ist gedeckelt', () {
    expect(f('badge_02', rides: 7)!.anteil, 1.0);
  });

  test('nicht messbare Badges liefern null', () {
    expect(f(Badge.membershipBadgeId), isNull);
    expect(f(Badge.starterBadgeId), isNull);
  });

  test('jedes Badge mit Sync-Bedingung hat einen Fortschritt', () {
    // Wer in calculateAndSync eine Bedingung hat, muss hier auftauchen —
    // sonst zeigt die Sammlung „Noch gesperrt" ohne Erklaerung.
    final sync = File(
      'lib/data/services/gamification_service.dart',
    ).readAsStringSync();
    final ids = RegExp(r"add\('(badge_\d+)'\)")
        .allMatches(sync)
        .map((m) => m.group(1)!)
        .toSet();
    for (final id in ids) {
      expect(
        f(id),
        isNotNull,
        reason: '$id hat eine Sync-Bedingung, aber keinen Fortschritt',
      );
    }
    expect(ids.length, greaterThanOrEqualTo(15));
  });

  test('Sammlung: Kacheln oeffnen das Overlay', () {
    final page = File(
      'lib/presentation/pages/analytics_page.dart',
    ).readAsStringSync();
    expect(page.contains('onTap: () => _oeffneBadge(badge)'), isTrue);
    expect(page.contains('fortschritt: earned ? null : _fortschrittFuer(badge)'),
        isTrue);
  });
}
