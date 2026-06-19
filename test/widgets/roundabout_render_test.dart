import 'package:cruise_connect/domain/models/route_maneuver.dart';
import 'package:cruise_connect/presentation/widgets/cruise/cruise_maneuver_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-06-16 (vucko O9): Golden-Abdeckung für das Kreisverkehr-Symbol — die
/// 1:1-Portierung des Figma-Designs (RoundaboutIcons.tsx). Deckt JEDE Situation
/// aus dem Design-Katalog ab. Die Einfahrt wird im Symbol immer nach unten
/// gedreht (Heading-up); deshalb werden die Manöver mit entry=180 (= unten)
/// gebaut, übrige Winkel relativ dazu — dann ist die Geo→Design-Umrechnung die
/// Identität und das Golden entspricht exakt der Figma-Vorlage.
void main() {
  RouteManeuver ra({
    required double entry,
    required double exit,
    required List<double> arms,
    double? islandScale,
    bool arrival = false,
  }) {
    return RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: 5,
      icon: Icons.roundabout_right,
      announcement: 'Im Kreisverkehr',
      instruction: 'Im Kreisverkehr',
      maneuverType: ManeuverType.roundabout,
      roundaboutEntryBearing: entry,
      roundaboutExitBearing: exit,
      roundaboutArmBearings: arms,
      roundaboutIslandScale: islandScale,
      roundaboutIsArrival: arrival,
    );
  }

  // Großes Standalone-Symbol (240px) — so prüft man Form/Stil mit dem Auge.
  Widget big(RouteManeuver m) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D0D0F),
          body: Center(child: RoundaboutSymbol(maneuver: m, size: 240)),
        ),
      );

  // Banner wie in der Navi-Ansicht (50px Symbol in der Karte).
  Widget banner(RouteManeuver m) => MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0D0D0F),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CruiseManeuverIndicator(
                maneuver: m,
                distanceToManeuverMeters: 220,
              ),
            ),
          ),
        ),
      );

  const cardinal = [0.0, 90.0, 180.0, 270.0];

  // ── Design-Katalog (entspricht SECTIONS aus RoundaboutIcons.tsx) ──────────
  final cases = <String, RouteManeuver>{
    // Standard 4-armig
    'std_exit1_rechts': ra(entry: 180, exit: 90, arms: cardinal),
    'std_exit2_gerade': ra(entry: 180, exit: 0, arms: cardinal),
    'std_exit3_links': ra(entry: 180, exit: 270, arms: cardinal),
    'std_umkehren': ra(entry: 180, exit: 188, arms: cardinal),
    // Wenige Arme: T-Kreisel & Mini
    't_kreisel_rechts': ra(entry: 180, exit: 90, arms: [90, 180, 270]),
    't_kreisel_links': ra(entry: 180, exit: 270, arms: [90, 180, 270]),
    'mini_rechts': ra(entry: 180, exit: 90, arms: cardinal, islandScale: 0.5),
    'mini_gerade': ra(entry: 180, exit: 0, arms: cardinal, islandScale: 0.5),
    // Viele Arme
    'fuenf_armig': ra(entry: 180, exit: 108, arms: [180, 252, 324, 36, 108]),
    'sechs_armig':
        ra(entry: 180, exit: 300, arms: [0, 60, 120, 180, 240, 300]),
    // Asymmetrisch / krumm
    'asym_spitz': ra(entry: 165, exit: 35, arms: [165, 35, 295, 245]),
    'asym_enge_gabel': ra(entry: 180, exit: 145, arms: [180, 145, 60, 290]),
    // Verschiedene Einfahrtrichtungen (werden heading-up nach unten gedreht)
    'einfahrt_links': ra(entry: 270, exit: 0, arms: cardinal),
    'einfahrt_oben': ra(entry: 0, exit: 90, arms: cardinal),
    // Größe & Arm-Länge
    'grosser_kreisel':
        ra(entry: 180, exit: 90, arms: cardinal, islandScale: 1.45),
    // Spezial: Ankunft direkt am Kreisel
    'ankunft_am_kreisel':
        ra(entry: 180, exit: 90, arms: cardinal, arrival: true),
    // Fallback: keine OSM-Topologie → sauberer Kreisel, aber der Ausfahrts-Pfeil
    // bleibt am ECHTEN Winkel (95°) statt auf 90° zu rasten (2026-06-19, Apple-
    // Ansatz: der Pfeil muss exakt zur gefahrenen Ausfahrt passen).
    'fallback_synth_echter_winkel': RouteManeuver(
      latitude: 47.4,
      longitude: 9.7,
      routeIndex: 5,
      icon: Icons.roundabout_right,
      announcement: 'Im Kreisverkehr',
      instruction: 'Im Kreisverkehr',
      maneuverType: ManeuverType.roundabout,
      roundaboutExitNumber: 1,
      roundaboutEntryBearing: 180,
      roundaboutExitBearing: 95, // bleibt 95° (kein Cardinal-Snap mehr)
      // roundaboutArmBearings: null  → Fallback-Pfad (synthetische Arme)
    ),
  };

  cases.forEach((name, m) {
    testWidgets('symbol $name', (tester) async {
      await tester.pumpWidget(big(m));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RoundaboutSymbol),
        matchesGoldenFile('goldens/ra_$name.png'),
      );
    });
  });

  testWidgets('banner standard 1. Ausfahrt', (tester) async {
    await tester.pumpWidget(banner(cases['std_exit1_rechts']!));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(CruiseManeuverIndicator),
      matchesGoldenFile('goldens/ra_banner_exit1.png'),
    );
  });
}
