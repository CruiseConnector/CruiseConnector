import 'dart:io';

import 'package:cruise_connect/data/services/tutorial_ziel_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08-15 (vucko, Screenshots 17:14): „Beim Tutorial sind die markierten
/// Bereiche wie Feed oder sonstige inakkurat positioniert — schau, dass es auf
/// jedem Handy schoen positioniert ist."
///
/// AM SCREENSHOT BELEGT: Der Spotlight-Ring sass bei „Fahrten" (3/7) und
/// „Feed" (4/7) genau eine Zeile UNTER dem Reiter.
///
/// URSACHE: `Offset(width * xFactor, 143)` — die Y-Position war eine feste
/// Zahl. Auf einem Geraet richtig, auf jedem anderen (Statusleiste, Notch,
/// Textskalierung) falsch.
///
/// JETZT: Reiter und Cruise-Knopf tragen GlobalKeys, die Registry liefert
/// die ECHTE Bildschirmposition. Der Schaetzwert bleibt nur als Rueckfall.
void main() {
  testWidgets('die Registry liefert die echte Position eines Widgets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 123),
              Row(
                children: [
                  const SizedBox(width: 40),
                  SizedBox(
                    key: TutorialZielRegistry.key(
                      TutorialZielRegistry.communityFeed,
                    ),
                    width: 90,
                    height: 46,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final rect = TutorialZielRegistry.rect(
      TutorialZielRegistry.communityFeed,
      aufblasen: 0,
    );
    expect(rect, isNotNull);
    expect(rect!.top, 123);
    expect(rect.left, 40);
    expect(rect.width, 90);
    expect(rect.height, 46);
  });

  testWidgets('nicht gebaute Ziele liefern null (Rueckfall greift)', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(
      TutorialZielRegistry.rect('gibt_es_nicht'),
      isNull,
      reason: 'dann faellt der Painter auf den alten Schaetzwert zurueck',
    );
  });

  group('Verdrahtung', () {
    test('die Reiter und der Cruise-Knopf tragen Keys', () {
      final community = File(
        'lib/presentation/pages/community_page.dart',
      ).readAsStringSync();
      final home = File('lib/presentation/pages/home_page.dart')
          .readAsStringSync();
      for (final ziel in [
        'communityFeed',
        'communityRides',
        'communityChats',
        'communityDiscover',
      ]) {
        expect(
          community.contains('TutorialZielRegistry.$ziel'),
          isTrue,
          reason: 'Reiter $ziel ohne Key → Spotlight muss wieder raten',
        );
      }
      expect(home.contains('TutorialZielRegistry.cruiseKnopf'), isTrue);
    });

    test('der Painter fragt zuerst die Registry', () {
      final overlay = File(
        'lib/presentation/widgets/app_tutorial_overlay.dart',
      ).readAsStringSync();
      final start = overlay.indexOf('Rect? _spotlightFor(');
      expect(start, greaterThan(0));
      final rumpf = overlay.substring(start, start + 2200);
      expect(rumpf.contains('TutorialZielRegistry.rect('), isTrue);
      // Reihenfolge: gemessen ?? Schaetzwert — nicht andersherum.
      final gemessen = rumpf.indexOf('gemessen(TutorialZielRegistry.communityFeed)');
      final schaetzung = rumpf.indexOf('communityTabTarget(0.125, 90)');
      expect(gemessen, greaterThan(0));
      expect(gemessen, lessThan(schaetzung));
    });

    test('nach dem Tab-Wechsel wird nachgezeichnet', () {
      final overlay = File(
        'lib/presentation/widgets/app_tutorial_overlay.dart',
      ).readAsStringSync();
      final start = overlay.indexOf('Future<void> _syncTab()');
      final rumpf = overlay.substring(start, start + 900);
      expect(
        rumpf.contains('addPostFrameCallback'),
        isTrue,
        reason:
            'sonst zeichnet der Spotlight mit der Position VOR dem Tab-Wechsel',
      );
    });
  });
}
