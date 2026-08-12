import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistente Kamera-Einstellungen für die Fahransicht.
///
/// 2026-07-28 (vucko „Kameradrehen als Modus, den man ein- und ausschalten
/// kann"): Im freien Kameramodus dreht sich die Karte in Blickrichtung mit
/// (Kompass bei Stillstand, Fahrtrichtung beim Fahren). Das ist Geschmackssache
/// und kostet zudem Akku, weil dafür der Magnetometer läuft. Deshalb ein
/// Schalter in den Einstellungen.
///
/// 2026-08-12 (vucko, ausdrücklich): „Das Kameradrehen ist automatisch an —
/// das umgehend immer als AUS nach dem Update und nach einer Installation
/// machen. Die User müssen das selber machen."
///
/// Damit ist die Voreinstellung AUS, und zwar auf zwei Wegen, die beide nötig
/// sind:
///   * Frische Installation: Es liegt nichts gespeichert, der Vorgabewert
///     greift.
///   * Nach einem Update: Auf dem Gerät liegt der alte Wert `true`, ein
///     Vorgabewert allein würde daran nichts ändern. Deshalb wird bei jedem
///     Versionswechsel EINMAL auf `false` zurückgesetzt.
///
/// Wer das Drehen mag, schaltet es in den Einstellungen wieder ein — bis zum
/// nächsten Update. Das ist Vuckos ausdrückliche Entscheidung und keine
/// Nachlässigkeit: Die Drehung war der häufigste Grund für „die Karte dreht
/// sich wild", und wer sie bewusst will, findet den Schalter.
///
/// Gilt AUSSCHLIESSLICH für den freien Modus. Ist die Kamera gelockt (normale
/// Navigation), dreht weiterhin die Routen-Tangente — davon ist dieser
/// Schalter unberührt.
class CameraSettingsService extends ChangeNotifier {
  CameraSettingsService._();
  static final CameraSettingsService instance = CameraSettingsService._();

  static const _keyAutoRotate = 'camera_free_auto_rotate_v1';

  /// Version, bei der zuletzt auf „aus" zurückgesetzt wurde.
  static const _keyResetVersion = 'camera_auto_rotate_reset_version_v1';

  /// Die Voreinstellung. Bewusst AUS, siehe Klassenkommentar.
  static const bool vorgabeAutoRotate = false;

  bool _loaded = false;
  bool _autoRotateFreeCam = vorgabeAutoRotate;

  /// Nur für Tests: ersetzt die Versionsermittlung.
  @visibleForTesting
  static Future<String> Function()? versionsLeser;

  bool get isLoaded => _loaded;

  /// Dreht die Karte im freien Modus automatisch in Blickrichtung mit?
  bool get autoRotateFreeCam => _autoRotateFreeCam;

  static Future<String> _version() async {
    final leser = versionsLeser;
    if (leser != null) return leser();
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (await _setzeBeiNeuerVersionZurueck(p)) {
        _autoRotateFreeCam = vorgabeAutoRotate;
      } else {
        _autoRotateFreeCam = p.getBool(_keyAutoRotate) ?? vorgabeAutoRotate;
      }
    } catch (e) {
      debugPrint('[CameraSettings] Laden fehlgeschlagen: $e');
      // Im Zweifel die Vorgabe — nicht das alte Verhalten.
      _autoRotateFreeCam = vorgabeAutoRotate;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Schaltet bei einem Versionswechsel EINMAL auf die Vorgabe zurück.
  ///
  /// Gibt `true` zurück, wenn zurückgesetzt wurde.
  ///
  /// Scheitert die Versionsermittlung, wird NICHT zurückgesetzt und der
  /// gespeicherte Wert gilt weiter — sonst würde die Einstellung des Nutzers
  /// bei jedem einzelnen App-Start verworfen, was schlimmer wäre als ein
  /// verpasstes Zurücksetzen.
  Future<bool> _setzeBeiNeuerVersionZurueck(SharedPreferences p) async {
    try {
      final version = await _version();
      if (p.getString(_keyResetVersion) == version) return false;
      await p.setString(_keyResetVersion, version);
      await p.setBool(_keyAutoRotate, vorgabeAutoRotate);
      debugPrint('[CameraSettings] Kameradrehen für $version auf aus gesetzt');
      return true;
    } catch (e) {
      debugPrint('[CameraSettings] Versions-Rücksetzung nicht möglich: $e');
      return false;
    }
  }

  Future<void> setAutoRotateFreeCam(bool value) async {
    if (_autoRotateFreeCam == value) return;
    _autoRotateFreeCam = value;
    // Zuerst melden, dann speichern: die Karte soll sofort reagieren und nicht
    // auf die Platte warten (gleiche Reihenfolge wie in PoiSettingsService).
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_keyAutoRotate, value);
    } catch (e) {
      debugPrint('[CameraSettings] Speichern fehlgeschlagen: $e');
    }
  }

  /// Nur für Tests.
  @visibleForTesting
  void resetForTests() {
    _loaded = false;
    _autoRotateFreeCam = vorgabeAutoRotate;
  }
}
