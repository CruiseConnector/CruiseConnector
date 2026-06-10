// 2026-06-10 (vucko ERSTOPEN-CRASH-FIX-Verifikation): Repro-Harness für den
// MapLibre-SIGABRT beim ersten Cruise-Page-Open pro Prozess (9 byte-identische
// Crashes; Root Cause: mbgl-LatLng-domain_error aus der Mercator-Unprojektion
// bei View-Größe 0 — Fix: Size-Gate + Kamera-Sanity in cruise_maplibre_map).
//
// Jeder Lauf = frischer App-Prozess + echter Erstopen des Cruise-Tabs — exakt
// das Crash-Muster. Crasht die native Seite (SIGABRT), stirbt der Test-Prozess
// und `flutter test` schlägt fehl. Grün = dieser Erstopen war crashfrei.
// Treibt die App über die Flutter-Engine (kein Maus-Event nötig).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cruise_connect/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Erstopen des Cruise-Tabs überlebt (kein MapLibre-SIGABRT)',
      (tester) async {
    app.main();
    // App-Boot + Session-Restore + Home-Aufbau (echte Wanduhr-Zeit).
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(seconds: 12),
        ));
    await tester.pump();

    // Cruise-Tab öffnen: der rote FAB sitzt mittig in der Bottom-Nav.
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width / 2, size.height - 60));
    await tester.pump();

    // Kritisches Fenster: MLNMapView-Init + erstes Layout + Style-Load.
    // Der historische Crash kam ~50ms nach Map-Init; wir geben 20s echte Zeit.
    await tester.runAsync(() => Future<void>.delayed(
          const Duration(seconds: 20),
        ));
    await tester.pump();

    // Überleben = Erfolg. (Bei SIGABRT erreicht der Test diese Zeile nie.)
    expect(WidgetsBinding.instance.isRootWidgetAttached, isTrue);
  });
}
