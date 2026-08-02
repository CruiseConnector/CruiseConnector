import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/camera_settings_service.dart';

/// 2026-07-28 (vucko): „Kameradrehen als Modus hinzufügen, den man ein- und
/// ausschalten kann."
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CameraSettingsService.instance.resetForTests();
  });

  test('Voreinstellung ist AN (bisheriges Verhalten bleibt)', () async {
    await CameraSettingsService.instance.load();
    expect(
      CameraSettingsService.instance.autoRotateFreeCam,
      isTrue,
      reason: 'Ein stiller Verhaltenswechsel für bestehende Nutzer wäre die '
          'schlechtere Voreinstellung',
    );
  });

  test('Umschalten meldet sich sofort', () async {
    await CameraSettingsService.instance.load();
    var meldungen = 0;
    void hoerer() => meldungen++;
    CameraSettingsService.instance.addListener(hoerer);
    addTearDown(() => CameraSettingsService.instance.removeListener(hoerer));

    await CameraSettingsService.instance.setAutoRotateFreeCam(false);

    expect(meldungen, greaterThan(0),
        reason: 'Ohne Meldung erfährt die Fahransicht nichts vom Ausschalten');
    expect(CameraSettingsService.instance.autoRotateFreeCam, isFalse);
  });

  test('gleicher Wert loest keine unnoetige Meldung aus', () async {
    await CameraSettingsService.instance.load();
    var meldungen = 0;
    void hoerer() => meldungen++;
    CameraSettingsService.instance.addListener(hoerer);
    addTearDown(() => CameraSettingsService.instance.removeListener(hoerer));

    await CameraSettingsService.instance.setAutoRotateFreeCam(true); // schon an
    expect(meldungen, 0);
  });

  test('Einstellung ueberlebt den Neustart', () async {
    await CameraSettingsService.instance.load();
    await CameraSettingsService.instance.setAutoRotateFreeCam(false);

    // Neustart simulieren: Dienst zuruecksetzen, aber die Platte behalten.
    CameraSettingsService.instance.resetForTests();
    await CameraSettingsService.instance.load();

    expect(CameraSettingsService.instance.autoRotateFreeCam, isFalse);
  });
}
