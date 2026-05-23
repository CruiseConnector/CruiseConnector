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
enum VoiceMode { off, important, all }

class VoiceSettingsService extends ChangeNotifier {
  VoiceSettingsService._();
  static final VoiceSettingsService instance = VoiceSettingsService._();

  static const _keyEnabled = 'voice_navigation_enabled_v1';
  static const _keyMode = 'voice_navigation_mode_v1';
  bool _loaded = false;
  bool _enabled = false;
  VoiceMode _mode = VoiceMode.all;

  bool get isEnabled => _enabled;
  bool get isLoaded => _loaded;
  VoiceMode get mode => _mode;

  /// Beim App-Start einmal aufrufen.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_keyEnabled) ?? false;
    final modeIdx = prefs.getInt(_keyMode) ?? 2;
    _mode = VoiceMode.values[modeIdx.clamp(0, 2)];
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
  }

  Future<void> setMode(VoiceMode m) async {
    if (_mode == m) return;
    _mode = m;
    if (m != VoiceMode.off) _enabled = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, m.index);
    await prefs.setBool(_keyEnabled, _enabled);
  }

  Future<void> toggle() => setEnabled(!_enabled);

  /// 3-Phasen-Cycle: off → important → all → off.
  Future<void> cycleMode() async {
    final next = switch (_mode) {
      VoiceMode.off => VoiceMode.important,
      VoiceMode.important => VoiceMode.all,
      VoiceMode.all => VoiceMode.off,
    };
    await setMode(next);
  }
}
