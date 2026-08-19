import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/xp_rechnung_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-19 (vucko woertlich): „ich moechte das es bei der post route page
/// eine gute animation gibt wenn man den multiplikator bekommt oder eine
/// streak hat die zeit normale xp fuer die fahrt + die xp = und dann die basis
/// xp multipliziert"
///
/// Und der gemessene Fehler desselben Tages: „Gebucht 204, angezeigt +102."
/// Deshalb steht hier vor allem EINE Pruefung: die Zahl am Ende der Animation
/// ist woertlich die Zahl aus der Aufschluesselung, die gebucht wird.
void main() {
  void setzeFlaeche(WidgetTester tester, Size groesse) {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> zeigeRechnung(
    WidgetTester tester,
    RouteXpBreakdown auf, {
    required bool doppelXpAktiv,
    bool bewegungReduziert = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: bewegungReduziert),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: XpRechnungAnimation(
                basisXp: auf.baseXp,
                multiplikator: auf.multiplier,
                gesamtXp: auf.totalXp,
                streakTage: auf.streakDays,
                doppelXpAktiv: doppelXpAktiv,
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Die Rechnung zeigt genau das, was gebucht wird', () {
    testWidgets('Bonuswoche + 3 Tage Streak: 120 wird zu 276', (tester) async {
      setzeFlaeche(tester, const Size(430, 900));
      // Genau die Rechnung, die auch `user_drive_sessions.xp_awarded` fuellt.
      final auf = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 12.0,
        curves: 0,
        style: 'CRUISE',
        streakDays: 3,
        doppelXpAktiv: true,
      );
      // Belegt die neue Regel schwarz auf weiss: BASIS 2,0 plus 3 * 0,1.
      expect(auf.baseXp, 120);
      expect(auf.multiplier, closeTo(2.30, 0.0001));
      expect(auf.totalXp, 276);

      await zeigeRechnung(tester, auf, doppelXpAktiv: true);
      await tester.pumpAndSettle();

      expect(find.text('= 276 XP'), findsOneWidget);
      expect(find.text('120 XP'), findsOneWidget);
      expect(find.text('×2,30'), findsOneWidget);
      expect(
        find.text('2,00 Doppel-XP-Woche + 0,30 für 3 Tage Streak'),
        findsOneWidget,
      );
    });

    testWidgets('Ohne Bonuswoche, 3 Tage Streak: 120 wird zu 156', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 900));
      final auf = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 12.0,
        curves: 0,
        style: 'CRUISE',
        streakDays: 3,
        doppelXpAktiv: false,
      );
      expect(auf.multiplier, closeTo(1.30, 0.0001));
      expect(auf.totalXp, 156);

      await zeigeRechnung(tester, auf, doppelXpAktiv: false);
      await tester.pumpAndSettle();

      expect(find.text('= 156 XP'), findsOneWidget);
      expect(find.text('×1,30'), findsOneWidget);
      expect(find.text('3 Tage Streak · 0,30 extra'), findsOneWidget);
      expect(find.textContaining('Doppel-XP'), findsNothing);
    });

    testWidgets('Ohne Streak und ohne Bonus bleibt die Rechnung weg', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 900));
      final auf = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 12.0,
        curves: 0,
        style: 'CRUISE',
        streakDays: 0,
        doppelXpAktiv: false,
      );
      expect(auf.multiplier, closeTo(1.0, 0.0001));
      expect(auf.totalXp, 120);

      await zeigeRechnung(tester, auf, doppelXpAktiv: false);
      await tester.pumpAndSettle();

      // Eine Rechnung „120 × 1,00 = 120" waere albern. Nur die Zahl.
      expect(find.text('120 XP'), findsOneWidget);
      expect(find.text('XP für diese Fahrt'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
      expect(find.textContaining('='), findsNothing);
      expect(find.textContaining('Streak'), findsNothing);
    });
  });

  testWidgets('Bewegung reduzieren: Endzahl sofort, ohne Aufbau', (
    tester,
  ) async {
    setzeFlaeche(tester, const Size(430, 900));
    final auf = GamificationService.calculateRouteXpBreakdown(
      distanceKm: 12.0,
      curves: 0,
      style: 'CRUISE',
      streakDays: 3,
      doppelXpAktiv: true,
    );

    await zeigeRechnung(
      tester,
      auf,
      doppelXpAktiv: true,
      bewegungReduziert: true,
    );
    // EIN Frame, kein pumpAndSettle: Wer „Bewegung reduzieren" gesetzt hat,
    // sieht das Ergebnis sofort.
    await tester.pump();

    expect(find.text('= 276 XP'), findsOneWidget);
    expect(find.text('120 XP'), findsOneWidget);
  });

  testWidgets('Ohne die Einstellung zaehlt es sichtbar hoch', (tester) async {
    setzeFlaeche(tester, const Size(430, 900));
    final auf = GamificationService.calculateRouteXpBreakdown(
      distanceKm: 12.0,
      curves: 0,
      style: 'CRUISE',
      streakDays: 3,
      doppelXpAktiv: true,
    );

    await zeigeRechnung(tester, auf, doppelXpAktiv: true);
    await tester.pump();
    // Erster Frame: die Endzahl darf noch NICHT dastehen, sonst gibt es
    // nichts zu sehen.
    expect(find.text('= 276 XP'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('= 276 XP'), findsOneWidget);
  });

  testWidgets('Abschluss-Sheet: Kachel und Rechnung nennen dieselbe Zahl', (
    tester,
  ) async {
    setzeFlaeche(tester, const Size(430, 1400));
    final auf = GamificationService.calculateRouteXpBreakdown(
      distanceKm: 12.0,
      curves: 0,
      style: 'CRUISE',
      streakDays: 3,
      doppelXpAktiv: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CruiseCompletionDialog(
            distanceKm: 12.0,
            durationText: '24 min',
            curves: 9,
            // Genau der gebuchte Wert — nicht der unverdoppelte.
            xpEarned: auf.totalXp,
            baseXp: auf.baseXp,
            streakDays: auf.streakDays,
            xpMultiplier: auf.multiplier,
            doppelXpAktiv: true,
            routeCoordinates: const [
              [9.7471, 47.5162],
              [9.75, 47.52],
              [9.7471, 47.5162],
            ],
            onSave: (rating, tags, title, photoBytes, publish) {},
            onDiscard: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Die Kachel zeigt die nackte Zahl, die Rechnung dieselbe mit Einheit.
    expect(find.text('276'), findsOneWidget);
    expect(find.text('= 276 XP'), findsOneWidget);
    // Multiplikator deutsch mit Komma, nicht „x2.30".
    expect(find.text('XP ×2,30'), findsOneWidget);
  });
}
