import 'package:cruise_connect/presentation/widgets/app_tutorial_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-14 (vucko Tutorial-Umbau): Deckt die INTERAKTIVEN Pflicht-Schritte
/// und den Abschluss-Schritt ab. Beitrittsdatum und Belohnungspfad werden
/// injiziert — kein Supabase im Widget-Test, keine echte XP-Vergabe.
void main() {
  // Schritt-Indizes im 7er-Fluss (Willkommen=0 … Abschluss=6).
  const routeSearchStep = 1;
  const favoriteStep = 5;
  const completionStep = 6;

  Future<void> pumpOverlay(WidgetTester tester, {required int step}) async {
    SharedPreferences.setMockInitialValues({});

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(393, 852);
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF05070B),
          body: AppTutorialOverlay(
            onTabChange: (_) {},
            loadMemberSince: () async => DateTime(2026, 3, 14),
            claimReward: () async {},
            initialStepIndex: step,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton weiterButton(WidgetTester tester) {
    return tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
  }

  group('Interaktiver Schritt: Routensuche', () {
    testWidgets('blockiert Weiter, bis die Suche gestartet wurde', (
      tester,
    ) async {
      await pumpOverlay(tester, step: routeSearchStep);

      // Vor der Aktion: Weiter gesperrt.
      expect(weiterButton(tester).onPressed, isNull);

      await tester.tap(find.text('Route suchen'));
      await tester.pumpAndSettle();

      // Lade-Animation durchgelaufen → Route gefunden → Weiter frei.
      expect(find.textContaining('Route gefunden'), findsOneWidget);
      expect(weiterButton(tester).onPressed, isNotNull);
    });
  });

  group('Interaktiver Schritt: Favoriten', () {
    testWidgets('blockiert Weiter, bis Adresse angetippt UND gemerkt ist', (
      tester,
    ) async {
      await pumpOverlay(tester, step: favoriteStep);

      expect(weiterButton(tester).onPressed, isNull);
      // Der Stern erscheint erst NACH dem Antippen der Adresse.
      expect(find.byIcon(CupertinoIcons.star), findsNothing);

      await tester.tap(find.text('Feldkirch, Vorarlberg'));
      await tester.pumpAndSettle();

      // Adresse allein reicht nicht — Weiter bleibt gesperrt.
      expect(weiterButton(tester).onPressed, isNull);

      await tester.tap(find.byIcon(CupertinoIcons.star));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gemerkt!'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.star_fill), findsWidgets);
      expect(weiterButton(tester).onPressed, isNotNull);
    });
  });

  group('Abschluss-Schritt', () {
    testWidgets('zeigt 125 XP und das Dabei-seit-Datum aus dem Profil', (
      tester,
    ) async {
      await pumpOverlay(tester, step: completionStep);

      expect(find.text('Du bist startklar!'), findsWidgets);
      // Zähler-Animation ist durchgelaufen → Endwert steht.
      expect(find.text('+125 XP'), findsOneWidget);
      // Gemocktes Beitrittsdatum (2026-03-14) → deutscher Monatsname.
      expect(find.text('Dabei seit März 2026'), findsOneWidget);
      expect(find.text('Gründungszeit'), findsOneWidget);
    });
  });
}
