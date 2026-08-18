import 'dart:io';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 6): „die Badges sollen mehr werden
/// (10 bis 15) im bestehenden Design, antippbar mit Overlay, gesperrte
/// zeigen Bedingung und Fortschritt."
UserDriveSession _s({
  required DateTime ende,
  double km = 20,
  int sek = 1800,
  bool fertig = true,
  String? stil,
  String? typ,
}) =>
    UserDriveSession(
      id: 'x',
      userId: 'u',
      distanceKm: km,
      durationSeconds: sek,
      xpAwarded: 0,
      completedAtEnd: fertig,
      createdAt: ende,
      routeStyle: stil,
      routeType: typ,
    );

void main() {
  test('vierzehn neue Badges 23–36 mit Emblem-Datei', () {
    final neue = Badge.all.where((b) {
      final n = int.tryParse(b.id.split('_').last) ?? 0;
      return n >= 23 && n <= 36;
    }).toList();
    expect(neue, hasLength(14));
    for (final b in neue) {
      expect(b.assetPath, isNotNull, reason: b.id);
      expect(File(b.assetPath!).existsSync(), isTrue, reason: b.assetPath);
      expect(b.description.length, lessThanOrEqualTo(110), reason: b.id);
    }
    // Keine doppelten IDs in der ganzen Liste.
    expect(Badge.all.map((b) => b.id).toSet().length, Badge.all.length);
  });

  group('SessionKennzahlen', () {
    test('Fruehstarter: Start (Ende minus Dauer) vor 8 Uhr, mind. 5 km', () {
      final k = GamificationService.sessionKennzahlen([
        // Ende 8:20, 45 min → Start 7:35 → zaehlt.
        _s(ende: DateTime(2026, 8, 10, 8, 20), sek: 45 * 60),
        // Ende 8:20, 10 min → Start 8:10 → zaehlt nicht.
        _s(ende: DateTime(2026, 8, 11, 8, 20), sek: 10 * 60),
        // Frueh, aber nur 2 km → zaehlt nicht.
        _s(ende: DateTime(2026, 8, 12, 6, 0), km: 2),
      ]);
      expect(k.fruehFahrten, 1);
    });

    test('Nachtschwaermer: nach 22 Uhr oder vor 4 Uhr', () {
      final k = GamificationService.sessionKennzahlen([
        _s(ende: DateTime(2026, 8, 10, 22, 30)),
        _s(ende: DateTime(2026, 8, 11, 0, 30)),
        _s(ende: DateTime(2026, 8, 12, 21, 0), sek: 600),
      ]);
      expect(k.nachtFahrten, 2);
    });

    test('Wochenende/Kurvenjagd/Stile/Rundkurs/A→B nur fuer beendete Fahrten', () {
      final k = GamificationService.sessionKennzahlen([
        _s(ende: DateTime(2026, 8, 15, 12), stil: 'Kurvenjagd', typ: 'ROUND_TRIP'), // Samstag
        _s(ende: DateTime(2026, 8, 16, 12), stil: 'Sport Mode', typ: 'POINT_TO_POINT'), // Sonntag
        _s(ende: DateTime(2026, 8, 17, 12), stil: 'Abendrunde', typ: 'ROUND_TRIP'), // Montag
        _s(ende: DateTime(2026, 8, 18, 12), stil: 'Entdecker', typ: 'ROUND_TRIP', fertig: false),
      ]);
      expect(k.wochenendFahrten, 2);
      expect(k.kurvenjagdFahrten, 1);
      expect(k.gefahreneStile, 3, reason: 'Entdecker-Fahrt war nicht beendet');
      expect(k.rundkurse, 2);
      expect(k.aNachBFahrten, 1);
    });

    test('laengste Serie zaehlt aufeinanderfolgende Fahrtage in der Historie', () {
      final tage = [1, 2, 3, 5, 6, 7, 8, 9, 20];
      final serie = GamificationService.laengsteFahrSerie([
        for (final t in tage) _s(ende: DateTime(2026, 7, t, 10)),
        // zwei Fahrten am selben Tag zaehlen einmal
        _s(ende: DateTime(2026, 7, 6, 18)),
      ]);
      expect(serie, 5);
      expect(GamificationService.laengsteFahrSerie(const []), 0);
    });
  });

  group('Fortschritt der neuen Badges', () {
    BadgeFortschritt? f(String id, {int frueh = 0, int serie = 0, int stile = 0, double km = 0}) =>
        badgeFortschrittFuer(
          badgeId: id,
          level: 1,
          totalKm: km,
          totalHours: 0,
          completedRides: 0,
          completedGroupRides: 0,
          routePosts: 0,
          createdGroups: 0,
          savedRoutes: 0,
          longestRideKm: 0,
          fruehFahrten: frueh,
          besteSerieTage: serie,
          gefahreneStile: stile,
        );

    test('Vuckos Beispiel: 274 von 1000 km', () {
      final p = f('badge_31', km: 274)!;
      expect(p.zahlen, '274 von 1000 km');
      expect(p.anteil, closeTo(0.274, 1e-9));
    });

    test('Serie 4 von 7 Tagen, Stile 3 von 4', () {
      expect(f('badge_26', serie: 4)!.zahlen, '4 von 7 Tage');
      expect(f('badge_28', stile: 3)!.zahlen, '3 von 4 Stile');
      expect(f('badge_23', frueh: 1)!.anteil, 1.0);
    });

    test('jedes neue Badge hat einen Fortschritt', () {
      for (var i = 23; i <= 36; i++) {
        expect(f('badge_$i'), isNotNull, reason: 'badge_$i');
      }
    });
  });

  test('Sync bindet die Kennzahlen an (Quelle: sessionKennzahlen)', () {
    final g = File('lib/data/services/gamification_service.dart').readAsStringSync();
    expect(g.contains('final kz = sessionKennzahlen(sessions);'), isTrue);
    // 2026-08-18 (Aufgabe 4.2): Die Freischaltung steht nicht mehr als
    // einzelne if-Zeilen im Dienst, sondern in der Tabelle [badgeFamilien].
    // Geprueft wird deshalb, dass jede der vierzehn IDs dort eine Schwelle
    // hat und der Dienst diese Tabelle auswertet.
    expect(g.contains('erfuellteBadgeIds(metriken)'), isTrue);
    for (var i = 23; i <= 36; i++) {
      expect(badgeBedingungFuer('badge_$i'), isNotNull, reason: 'badge_$i');
    }
    final a = File('lib/presentation/pages/analytics_page.dart').readAsStringSync();
    expect(a.contains('besteSerieTage: g.besteSerieTage'), isTrue);
  });
}
