import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Globale Voice-Navigation-Einstellung.
///
/// Wird persistiert via SharedPreferences. Aktuell noch nicht mit
/// flutter_tts verkoppelt — die UI-Toggles sind aber bereits da, damit
/// User die Option überall (Settings + In-Route) sehen können.
///
/// Default: OFF — TTS wird erst aktiviert wenn die Implementierung
/// gegen alle Manöver-Codes/Sprachen getestet ist.
class VoiceSettingsService extends ChangeNotifier {
  VoiceSettingsService._();
  static final VoiceSettingsService instance = VoiceSettingsService._();

  static const _key = 'voice_navigation_enabled_v1';
  bool _loaded = false;
  bool _enabled = false;

  bool get isEnabled => _enabled;
  bool get isLoaded => _loaded;

  /// Beim App-Start einmal aufrufen.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_key) ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  Future<void> toggle() => setEnabled(!_enabled);
}
