// 2026-06-10 (vucko ERSTOPEN-CRASH-FIX-Verifikation, v2 — PRÄZISE):
// Der 9×-byte-identische SIGABRT entstand beim Setup der frischen MLNMapView
// (mbgl-LatLng-domain_error aus der Mercator-Unprojektion bei View-Größe 0 —
// Fix: Size-Gate + Kamera-Sanity). Dieser Test mountet das Karten-Widget
// DIREKT (ohne App-Boot/Login — der Crash-Pfad ist die reine Map-Erstellung):
// jeder Lauf = frischer Prozess + frische native Map = exakter Erstopen-Repro.
// Crasht die native Seite, stirbt der Testprozess → `flutter test` rot.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:cruise_connect/presentation/widgets/cruise/cruise_maplibre_map.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Frische MLNMapView überlebt das Setup (kein LatLng-SIGABRT)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CruiseMapLibreMap(
            initialCenter: ll.LatLng(47.5031, 9.7471), // Bregenz
            initialZoom: 13,
          ),
        ),
      ),
    );
    // Kritisches Fenster: Style-Load + native View + erstes Layout + Kamera.
    // (Historischer Crash: 50 ms nach Map-Init.) 25 s echte Zeit, live gepumpt.
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
    }
    // Beweis: die NATIVE MapLibre-View wurde wirklich gebaut (nicht nur die
    // Style-Lade-Platzhalter-Box) — sonst wäre der Crash-Pfad nie betreten.
    final nativeMap = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'MapLibreMap',
    );
    // ignore: avoid_print
    print('PROBE nativeMapInTree=${nativeMap.evaluate().length}');
    expect(
      nativeMap.evaluate().isNotEmpty,
      isTrue,
      reason: 'native MapLibreMap muss im Tree sein (Crash-Pfad betreten)',
    );
    expect(WidgetsBinding.instance.isRootWidgetAttached, isTrue);
  });
}
