import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/poi_settings_service.dart';
import 'package:cruise_connect/data/services/route_poi_service.dart';

/// 2026-07-27 (vucko „ausgeschaltete POIs bleiben manchmal auf der Karte"):
///
/// Die Karte raeumte abgewaehlte Marker erst weg, NACHDEM eine neue
/// Overpass-Abfrage zurueckkam. Lief gerade schon eine, wurde die neue
/// verworfen — die Tankstellen blieben dann liegen, bis man ein zweites Mal
/// umschaltete. Der Fix haengt an zwei Zusicherungen dieses Dienstes:
///
///   1. Ein Umschalten meldet sich SOFORT bei den Hoerern
///      (`CruiseModePage` filtert daraufhin synchron, ohne Netzwerk).
///   2. `enabledTypes` spiegelt den neuen Stand sofort wider
///      (die Zeichenroutine filtert bei JEDEM Frame dagegen).
///
/// Faellt eine der beiden weg, kommt der alte Fehler zurueck.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PoiSettingsService — Grundlage des sofortigen Ausblendens', () {
    test('Ausschalten meldet sich sofort und entfernt den Typ', () async {
      final service = PoiSettingsService.instance;
      await service.load();
      await service.setFuel(true);

      expect(
        service.enabledTypes,
        contains(PoiType.fuel),
        reason: 'Vorbedingung: Tankstellen sind an',
      );

      var meldungen = 0;
      void hoerer() => meldungen++;
      service.addListener(hoerer);
      addTearDown(() => service.removeListener(hoerer));

      await service.setFuel(false);

      expect(meldungen, greaterThan(0),
          reason: 'Ohne Benachrichtigung erfaehrt die Karte nichts vom '
              'Ausschalten und behaelt die alten Marker');
      expect(service.enabledTypes, isNot(contains(PoiType.fuel)),
          reason: 'Der Zeichen-Filter muss den Typ sofort als aus sehen');
    });

    test('andere Kategorien bleiben beim Ausschalten unberuehrt', () async {
      final service = PoiSettingsService.instance;
      await service.load();
      await service.setFuel(true);
      await service.setRestaurant(true);

      await service.setFuel(false);

      expect(service.enabledTypes, isNot(contains(PoiType.fuel)));
      expect(service.enabledTypes, contains(PoiType.restaurant),
          reason: 'Nur die abgewaehlte Kategorie darf verschwinden');
      expect(service.anyEnabled, isTrue);
    });

    test('letzte Kategorie aus: anyEnabled wird false', () async {
      final service = PoiSettingsService.instance;
      await service.load();
      for (final setter in <Future<void> Function(bool)>[
        service.setFuel,
        service.setRestaurant,
        service.setCafe,
        service.setRepair,
        service.setFastFood,
        service.setPub,
        service.setParking,
        service.setToilets,
      ]) {
        await setter(false);
      }
      expect(service.anyEnabled, isFalse);
      expect(service.enabledTypes, isEmpty,
          reason: 'Dann muss die Karte alle POI-Marker abwerfen');
    });
  });
}
