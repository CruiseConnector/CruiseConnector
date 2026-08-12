import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cruise_connect/data/services/camera_settings_service.dart';

/// 2026-07-28 (vucko): „Kameradrehen als Modus hinzufügen, den man ein- und
/// ausschalten kann."
///
/// 2026-08-12 (vucko, ausdrücklich UMGEDREHT): „Das Kameradrehen ist
/// automatisch an — das umgehend immer als AUS nach dem Update und nach einer
/// Installation machen. Die User müssen das selber machen."
///
/// Die frühere Fassung dieser Datei hielt das Gegenteil fest („Voreinstellung
/// ist AN, ein stiller Verhaltenswechsel wäre die schlechtere
/// Voreinstellung"). Das war damals richtig und ist es jetzt nicht mehr — die
/// Entscheidung hat sich geändert, nicht der Code hat sich verirrt.
///
/// Das Zusammenspiel mit dem Zurücksetzen bei jedem Versionswechsel steht in
/// kamera_drehen_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CameraSettingsService.instance.resetForTests();
    // Feste Version, damit das Zurücksetzen hier nicht mit hineinspielt.
    CameraSettingsService.versionsLeser = () async => '1.5.13+95';
  });

  tearDown(() => CameraSettingsService.versionsLeser = null);

  test('Voreinstellung ist AUS', () async {
    await CameraSettingsService.instance.load();
    expect(
      CameraSettingsService.instance.autoRotateFreeCam,
      isFalse,
      reason:
          'vucko: „Die User müssen das selber machen" — wer das Mitdrehen '
          'will, schaltet es in den Einstellungen ein',
    );
  });

  test('Umschalten meldet sich sofort', () async {
    await CameraSettingsService.instance.load();
    var meldungen = 0;
    void hoerer() => meldungen++;
    CameraSettingsService.instance.addListener(hoerer);
    addTearDown(() => CameraSettingsService.instance.removeListener(hoerer));

    await CameraSettingsService.instance.setAutoRotateFreeCam(true);

    expect(
      meldungen,
      greaterThan(0),
      reason: 'Ohne Meldung erfährt die Fahransicht nichts vom Einschalten',
    );
    expect(CameraSettingsService.instance.autoRotateFreeCam, isTrue);
  });

  test('gleicher Wert loest keine unnoetige Meldung aus', () async {
    await CameraSettingsService.instance.load();
    var meldungen = 0;
    void hoerer() => meldungen++;
    CameraSettingsService.instance.addListener(hoerer);
    addTearDown(() => CameraSettingsService.instance.removeListener(hoerer));

    await CameraSettingsService.instance.setAutoRotateFreeCam(false); // schon aus
    expect(meldungen, 0);
  });

  test('Einstellung ueberlebt den Neustart derselben Version', () async {
    await CameraSettingsService.instance.load();
    await CameraSettingsService.instance.setAutoRotateFreeCam(true);

    // Neustart simulieren: Dienst zuruecksetzen, aber die Platte behalten.
    CameraSettingsService.instance.resetForTests();
    await CameraSettingsService.instance.load();

    expect(
      CameraSettingsService.instance.autoRotateFreeCam,
      isTrue,
      reason:
          'innerhalb derselben Version bleibt die Wahl stehen — sonst waere '
          'der Schalter beim naechsten Start wirkungslos',
    );
  });
}
