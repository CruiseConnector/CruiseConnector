import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Globale Voice-Navigation-Einstellung.
///
/// 2026-06-06 (vucko): EINE Source of Truth = [mode] (off / important / all).
/// Früher gab es zwei getrennte Flags (`enabled` UND `mode`), und TTS sprach nur
/// wenn BEIDE passten. Dadurch musste man die Ansagen erst in den Einstellungen
/// freischalten, bevor der Cruise-Mode-Schalter überhaupt wirkte — unlogisch.
/// Jetzt steuert JEDER der beiden Schalter (Settings-Switch ODER Cruise-FAB)
/// die Ansagen vollständig allein. `isEnabled` ist nur noch abgeleitet.
///
/// Persistiert via SharedPreferences. Default: OFF (Ansagen aus, bis der User
/// sie mit EINEM Tap aktiviert — kein doppeltes Freischalten mehr).
enum VoiceMode { off, important, all }

class VoiceSettingsService extends ChangeNotifier {
  VoiceSettingsService._();
  static final VoiceSettingsService instance = VoiceSettingsService._();

  static const _keyMode = 'voice_navigation_mode_v1';
  // Nur noch für die Migration alter Installationen gelesen (siehe load()).
  static const _keyEnabledLegacy = 'voice_navigation_enabled_v1';
  // 2026-06-23 (vucko Voice-Lautstärke): persistierte Ansage-Lautstärke 0..1.
  static const _keyVolume = 'voice_navigation_volume_v1';

  bool _loaded = false;
  VoiceMode _mode = VoiceMode.off;
  // 2026-06-23: Standard 1.0 (laut) — vorher fix 0.95 und nicht einstellbar; der
  // Nutzer empfand die Ansagen als zu leise. Jetzt per Slider regelbar.
  double _volume = 1.0;

  /// Abgeleitet: Ansagen aktiv = Modus ist nicht „off". Kein separates Flag mehr.
  bool get isEnabled => _mode != VoiceMode.off;
  bool get isLoaded => _loaded;
  VoiceMode get mode => _mode;

  /// Ansage-Lautstärke 0..1 (an FlutterTts.setVolume durchgereicht).
  double get volume => _volume;

  /// Beim App-Start einmal aufrufen.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final modeIdx = prefs.getInt(_keyMode);
    if (modeIdx != null) {
      _mode = VoiceMode.values[modeIdx.clamp(0, 2)];
    } else if (prefs.getBool(_keyEnabledLegacy) ?? false) {
      // Migration: wer früher den Settings-Schalter „an" hatte → volle Ansagen.
      _mode = VoiceMode.all;
    } else {
      _mode = VoiceMode.off;
    }
    final vol = prefs.getDouble(_keyVolume);
    if (vol != null && vol.isFinite) _volume = vol.clamp(0.0, 1.0);
    _loaded = true;
    notifyListeners();
  }

  /// Setzt die Ansage-Lautstärke (0..1), persistiert + benachrichtigt.
  Future<void> setVolume(double v) async {
    final clamped = v.isFinite ? v.clamp(0.0, 1.0).toDouble() : _volume;
    if ((clamped - _volume).abs() < 0.001) return;
    _volume = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolume, clamped);
  }

  Future<void> setMode(VoiceMode m) async {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMode, m.index);
  }

  /// Master-An/Aus (z. B. Settings-Switch): an → „Alle Ansagen", aus → stumm.
  Future<void> setEnabled(bool value) =>
      setMode(value ? VoiceMode.all : VoiceMode.off);

  Future<void> toggle() => setMode(isEnabled ? VoiceMode.off : VoiceMode.all);

  /// 3-Phasen-Cycle (Cruise-FAB): off → important → all → off.
  Future<void> cycleMode() async {
    final next = switch (_mode) {
      VoiceMode.off => VoiceMode.important,
      VoiceMode.important => VoiceMode.all,
      VoiceMode.all => VoiceMode.off,
    };
    await setMode(next);
  }
}
