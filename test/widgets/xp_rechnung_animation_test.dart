import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_completion_dialog.dart';
import 'package:cruise_connect/presentation/widgets/cruise/xp_rechnung_animation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    Duration? bonusRestlaufzeit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: bewegungReduziert),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: SingleChildScrollView(
                child: XpRechnungAnimation(
                  basisXp: auf.baseXp,
                  multiplikator: auf.multiplier,
                  gesamtXp: auf.totalXp,
                  streakTage: auf.streakDays,
                  doppelXpAktiv: doppelXpAktiv,
                  bonusRestlaufzeit: bonusRestlaufzeit,
                ),
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

  // ------------------------------------------------------------------
  // 2026-08-24 (Aufgabe 4.4): Die Animation sagte zwei von drei Sachen nicht.
  // ------------------------------------------------------------------
  //
  // vucko woertlich am 23.08.: „wenn man eine coole Animation hat dann nach
  // der Fahrt, dass halt irgendwie angezeigt werden kann, dass man durch den
  // Boost die sieben Tage einen doppelten Boost hat und halt auf dem aufbauen
  // kann."
  //
  // Drei Dinge. Die Verdopplung sagte sie schon. Die SIEBEN TAGE und das
  // AUFBAUEN sagte sie NICHT — vor dieser Aenderung waere jede Erwartung in
  // dieser Gruppe rot.
  group('Die Animation sagt alle drei Dinge', () {
    setUp(() => StarterAufgabenService.instance.resetForTests());

    RouteXpBreakdown mitBonus() =>
        GamificationService.calculateRouteXpBreakdown(
          distanceKm: 12.0,
          curves: 0,
          style: 'CRUISE',
          streakDays: 3,
          doppelXpAktiv: true,
        );

    testWidgets('1. die Verdopplung, 2. die sieben Tage, 3. das Aufbauen', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      final auf = mitBonus();
      await zeigeRechnung(
        tester,
        auf,
        doppelXpAktiv: true,
        bonusRestlaufzeit: const Duration(days: 5, hours: 3),
      );
      await tester.pumpAndSettle();

      // 1. Die Verdopplung: unveraendert, die Zahl kommt aus der Rechnung.
      expect(find.text('×2,30'), findsOneWidget);
      expect(find.text('= 276 XP'), findsOneWidget);

      // 2. Sieben Tage, mit Restlaufzeit.
      expect(find.textContaining('sieben Tagen'), findsOneWidget);
      expect(find.textContaining('5 Tage 3 Stunden'), findsOneWidget);

      // 3. Aufbauen: der Wert von morgen ist der heutige plus ein Tag.
      expect(find.textContaining('aufbauen'), findsOneWidget);
      expect(find.textContaining('×2,40'), findsOneWidget);
    });

    testWidgets('ohne durchgereichte Restlaufzeit steht die Sieben trotzdem da', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      // Kein Wert durchgereicht UND kein Bonus im Dienst: die Leiste darf
      // trotzdem nicht behaupten, es liefen noch X Tage.
      await zeigeRechnung(tester, mitBonus(), doppelXpAktiv: true);
      await tester.pumpAndSettle();

      expect(find.textContaining('sieben Tage lang'), findsOneWidget);
      expect(find.textContaining('noch'), findsNothing);
      expect(find.textContaining('×2,40'), findsOneWidget);
    });

    // Der Weg von der Fahrt bis hierher fuehrt ueber cruise_mode_page.dart und
    // cruise_completion_dialog.dart. Beide gehoeren einem anderen
    // Arbeitsbereich und reichen die Restlaufzeit (noch) nicht durch. Ohne
    // diesen Rueckfall saehe Vucko nach seiner Fahrt keine Restlaufzeit.
    testWidgets('ohne Durchreichung holt sie die Restlaufzeit selbst', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      SharedPreferences.setMockInitialValues({
        'starter_paket_vergeben_v1': true,
        'starter_bonus_ende_v1': DateTime.now()
            .add(const Duration(days: 4, hours: 2))
            .toIso8601String(),
      });
      await StarterAufgabenService.instance.load();
      expect(StarterAufgabenService.instance.doppelXpAktiv, isTrue);

      await zeigeRechnung(tester, mitBonus(), doppelXpAktiv: true);
      await tester.pumpAndSettle();

      expect(find.textContaining('noch 4 Tage'), findsOneWidget);
      expect(find.textContaining('von sieben Tagen'), findsOneWidget);
    });

    testWidgets('am letzten Tag verspricht sie kein ×2,40 mehr', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      await zeigeRechnung(
        tester,
        mitBonus(),
        doppelXpAktiv: true,
        // Morgen ist die Woche vorbei: die Basis faellt von 2,0 auf 1,0.
        // „Morgen schon ×2,40" waere dann gelogen.
        bonusRestlaufzeit: const Duration(hours: 5),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Letzter Tag'), findsOneWidget);
      expect(find.textContaining('×2,40'), findsNothing);
      // Die gebuchte Zahl bleibt unberuehrt.
      expect(find.text('= 276 XP'), findsOneWidget);
    });

    testWidgets('ohne Bonuswoche gibt es die Leiste nicht', (tester) async {
      setzeFlaeche(tester, const Size(430, 1000));
      final auf = GamificationService.calculateRouteXpBreakdown(
        distanceKm: 12.0,
        curves: 0,
        style: 'CRUISE',
        streakDays: 3,
        doppelXpAktiv: false,
      );
      await zeigeRechnung(tester, auf, doppelXpAktiv: false);
      await tester.pumpAndSettle();

      expect(find.textContaining('sieben'), findsNothing);
      expect(find.textContaining('aufbauen'), findsNothing);
      expect(find.text('= 156 XP'), findsOneWidget);
    });

    testWidgets('Bewegung reduzieren: auch die Leiste steht sofort', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      await zeigeRechnung(
        tester,
        mitBonus(),
        doppelXpAktiv: true,
        bewegungReduziert: true,
        bonusRestlaufzeit: const Duration(days: 5, hours: 3),
      );
      await tester.pump();

      expect(find.text('= 276 XP'), findsOneWidget);
      expect(find.textContaining('sieben Tagen'), findsOneWidget);
      expect(find.textContaining('×2,40'), findsOneWidget);
    });

    // Die drei ersten Stufen duerfen durch die vierte nicht langsamer werden.
    testWidgets('die gewohnte Rechnung laeuft weiter in 1500 ms', (
      tester,
    ) async {
      setzeFlaeche(tester, const Size(430, 1000));
      await zeigeRechnung(
        tester,
        mitBonus(),
        doppelXpAktiv: true,
        bonusRestlaufzeit: const Duration(days: 5, hours: 3),
      );
      await tester.pump();
      expect(find.text('= 276 XP'), findsNothing);
      // Nach 1500 ms steht das Ergebnis, die Leiste baut sich noch auf.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('= 276 XP'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.textContaining('×2,40'), findsOneWidget);
    });
  });

  group('Die Texte der Bonus-Leiste', () {
    test('Restlaufzeit nennt immer die sieben Tage', () {
      expect(
        bonusLaufzeitText(const Duration(days: 6, hours: 3)),
        'Doppel-XP-Woche · noch 6 Tage 3 Stunden von sieben Tagen',
      );
      expect(
        bonusLaufzeitText(const Duration(days: 1, hours: 1)),
        'Doppel-XP-Woche · noch 1 Tag 1 Stunde von sieben Tagen',
      );
      expect(
        bonusLaufzeitText(const Duration(hours: 2, minutes: 5)),
        'Doppel-XP-Woche · noch 2 Stunden 5 Minuten von sieben Tagen',
      );
      expect(bonusLaufzeitText(null), 'Doppel-XP-Woche · sieben Tage lang');
      expect(
        bonusLaufzeitText(Duration.zero),
        'Doppel-XP-Woche · sieben Tage lang',
      );
    });

    test('kein Gedankenstrich in den Nutzertexten', () {
      final texte = [
        bonusLaufzeitText(const Duration(days: 6, hours: 3)),
        bonusLaufzeitText(null),
        aufbauText(morgen: 2.4),
        aufbauText(morgen: 2.4, restlaufzeit: const Duration(hours: 3)),
      ];
      for (final t in texte) {
        expect(t.contains('—'), isFalse, reason: 'Gedankenstrich in "$t"');
        expect(t.contains('–'), isFalse, reason: 'Gedankenstrich in "$t"');
      }
    });

    test('der Balken zeigt, wie viel der Woche weg ist', () {
      // Frisch vergeben: nichts verbraucht.
      expect(bonusFortschritt(const Duration(days: 7)), closeTo(0.0, 0.01));
      // Halbzeit.
      expect(
        bonusFortschritt(const Duration(days: 3, hours: 12)),
        closeTo(0.5, 0.01),
      );
      // Unbekannt: der Balken behauptet nichts.
      expect(bonusFortschritt(null), 0);
    });
  });
}
