import 'package:cruise_connect/core/cruise_ui_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cruiseFabColumnHidden', () {
    test(
      'REGRESSION 2026-07-27: waehrend der Fahrt IMMER sichtbar, egal wie das '
      'Setup-Flag steht',
      () {
        // Genau dieser Fall war der Bug: beim Fahrt-Resume und als Startwert
        // steht _configCollapsed auf false, obwohl es waehrend der Navigation
        // gar kein Setup-Sheet gibt. Die Schnellzugriff-Spalte (POI-Filter,
        // Stimme, Kamera-Lock, Melde-Button) verschwand dadurch mitten in der
        // Fahrt.
        expect(
          cruiseFabColumnHidden(
            hasRoute: true,
            waypointRailActive: false,
            configCollapsed: false,
          ),
          isFalse,
          reason: 'Spalte muss waehrend der Fahrt sichtbar bleiben',
        );
        expect(
          cruiseFabColumnHidden(
            hasRoute: true,
            waypointRailActive: false,
            configCollapsed: true,
          ),
          isFalse,
        );
      },
    );

    test('vor der Route: hochgezogenes Setup-Sheet blendet aus', () {
      // Vuckos Wunsch vom 2026-07-25 bleibt erhalten.
      expect(
        cruiseFabColumnHidden(
          hasRoute: false,
          waypointRailActive: false,
          configCollapsed: false,
        ),
        isTrue,
      );
    });

    test('vor der Route: heruntergewischtes Sheet zeigt die Spalte', () {
      expect(
        cruiseFabColumnHidden(
          hasRoute: false,
          waypointRailActive: false,
          configCollapsed: true,
        ),
        isFalse,
      );
    });

    test('Wegpunkte-Modus blendet immer aus (sonst zwei Spalten uebereinander)',
        () {
      for (final hasRoute in [true, false]) {
        for (final collapsed in [true, false]) {
          expect(
            cruiseFabColumnHidden(
              hasRoute: hasRoute,
              waypointRailActive: true,
              configCollapsed: collapsed,
            ),
            isTrue,
            reason: 'hasRoute=$hasRoute collapsed=$collapsed',
          );
        }
      }
    });
  });
}
