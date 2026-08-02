import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistente Kamera-Einstellungen für die Fahransicht.
///
/// 2026-07-28 (vucko „Kameradrehen als Modus, den man ein- und ausschalten
/// kann"): Im freien Kameramodus dreht sich die Karte in Blickrichtung mit
/// (Kompass bei Stillstand, Fahrtrichtung beim Fahren). Das ist Geschmackssache
/// und kostet zudem Akku, weil dafür der Magnetometer läuft. Deshalb ein
/// Schalter in den Einstellungen.
///
/// Default AN — das ist das gewohnte Google-Maps-Verhalten und war bisher
/// fest eingebaut; ein stiller Verhaltenswechsel für bestehende Nutzer wäre
/// die schlechtere Voreinstellung.
///
/// Gilt AUSSCHLIESSLICH für den freien Modus. Ist die Kamera gelockt (normale
/// Navigation), dreht weiterhin die Routen-Tangente — davon ist dieser
/// Schalter unberührt.
class CameraSettingsService extends ChangeNotifier {
  CameraSettingsService._();
  static final CameraSettingsService instance = CameraSettingsService._();

  static const _keyAutoRotate = 'camera_free_auto_rotate_v1';

  bool _loaded = false;
  bool _autoRotateFreeCam = true;

  bool get isLoaded => _loaded;

  /// Dreht die Karte im freien Modus automatisch in Blickrichtung mit?
  bool get autoRotateFreeCam => _autoRotateFreeCam;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _autoRotateFreeCam = p.getBool(_keyAutoRotate) ?? true;
    } catch (e) {
      debugPrint('[CameraSettings] Laden fehlgeschlagen: $e');
    }
    _loaded = true;
    notifyListeners();
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
    _autoRotateFreeCam = true;
  }
}
