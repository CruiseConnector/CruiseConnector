import 'package:cruise_connect/data/services/camera_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-08-12 (vucko): „Das Kameradrehen ist automatisch an — das umgehend
/// immer als AUS nach dem Update und nach einer Installation machen. Die User
/// müssen das selber machen."
///
/// Zwei Wege sind noetig, und nur beide zusammen erfuellen den Auftrag:
///
///  * Frische Installation: Es liegt nichts gespeichert, der Vorgabewert
///    greift. Ein umgestellter Vorgabewert allein reicht dafuer.
///
///  * Nach einem Update: Auf dem Geraet liegt der ALTE Wert `true`. Ein
///    Vorgabewert aendert daran nichts — `getBool` findet ja etwas. Deshalb
///    wird bei jedem Versionswechsel einmal aktiv auf `false` gesetzt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dienst = CameraSettingsService.instance;

  setUp(() => dienst.resetForTests());
  tearDown(() => CameraSettingsService.versionsLeser = null);

  test('frische Installation: aus', () async {
    SharedPreferences.setMockInitialValues({});
    CameraSettingsService.versionsLeser = () async => '1.5.13+95';

    await dienst.load();
    expect(dienst.autoRotateFreeCam, isFalse);
  });

  test('nach einem Update wird ein gespeichertes AN auf AUS gesetzt', () async {
    SharedPreferences.setMockInitialValues({
      'camera_free_auto_rotate_v1': true, // so stand es vor dem Update
      'camera_auto_rotate_reset_version_v1': '1.5.12+94',
    });
    CameraSettingsService.versionsLeser = () async => '1.5.13+95';

    await dienst.load();
    expect(
      dienst.autoRotateFreeCam,
      isFalse,
      reason: 'genau das ist der Kern des Auftrags',
    );

    // Und es ist auch wirklich gespeichert, nicht nur im Arbeitsspeicher.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('camera_free_auto_rotate_v1'), isFalse);
    expect(
      prefs.getString('camera_auto_rotate_reset_version_v1'),
      '1.5.13+95',
    );
  });

  test('innerhalb derselben Version bleibt die Wahl des Nutzers stehen',
      () async {
    SharedPreferences.setMockInitialValues({
      'camera_free_auto_rotate_v1': true,
      'camera_auto_rotate_reset_version_v1': '1.5.13+95',
    });
    CameraSettingsService.versionsLeser = () async => '1.5.13+95';

    await dienst.load();
    expect(
      dienst.autoRotateFreeCam,
      isTrue,
      reason:
          'wer es in DIESER Version eingeschaltet hat, darf es behalten — '
          'sonst waere der Schalter beim naechsten App-Start wirkungslos',
    );
  });

  test('einschalten wirkt sofort und wird gemerkt', () async {
    SharedPreferences.setMockInitialValues({});
    CameraSettingsService.versionsLeser = () async => '1.5.13+95';
    await dienst.load();
    expect(dienst.autoRotateFreeCam, isFalse);

    var gemeldet = 0;
    void hoerer() => gemeldet++;
    dienst.addListener(hoerer);
    addTearDown(() => dienst.removeListener(hoerer));

    await dienst.setAutoRotateFreeCam(true);
    expect(dienst.autoRotateFreeCam, isTrue);
    expect(gemeldet, 1, reason: 'die Karte muss sofort reagieren');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('camera_free_auto_rotate_v1'), isTrue);
  });

  test('ohne lesbare Version bleibt die gespeicherte Wahl erhalten', () async {
    // Sonst wuerde die Einstellung bei JEDEM App-Start verworfen — schlimmer
    // als ein einmal verpasstes Zuruecksetzen.
    SharedPreferences.setMockInitialValues({
      'camera_free_auto_rotate_v1': true,
      'camera_auto_rotate_reset_version_v1': '1.5.13+95',
    });
    CameraSettingsService.versionsLeser = () async =>
        throw Exception('PackageInfo nicht verfuegbar');

    await dienst.load();
    expect(dienst.autoRotateFreeCam, isTrue);
  });

  test('die Vorgabe ist aus', () {
    expect(CameraSettingsService.vorgabeAutoRotate, isFalse);
  });
}
