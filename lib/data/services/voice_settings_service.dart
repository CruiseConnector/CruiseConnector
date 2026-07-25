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

  // 2026-07-25: Der MODUS wird bewusst nicht mehr persistiert (siehe load()) —
  // die alten Keys werden beim Laden nur noch aufgeräumt.
  static const _keyModeLegacy = 'voice_navigation_mode_v1';
  static const _keyEnabledLegacy = 'voice_navigation_enabled_v1';
  // 2026-06-23 (vucko Voice-Lautstärke): persistierte Ansage-Lautstärke 0..1.
  static const _keyVolume = 'voice_navigation_volume_v1';

  /// 2026-07-25 (vucko „Navi auch bei leise gestellt laut genug"): Untergrenze
  /// der Ansage-Lautstärke — Source of Truth für Service UND Regler-UI. Die
  /// Lautstärke regelt nur die Stimme selbst, nicht die Ducking-Tiefe der
  /// Musik (die ist systemseitig fix); zu tief eingestellt geht die Ansage im
  /// Restpegel der Musik unter. Ein bereits gespeicherter kleinerer Wert wird
  /// beim Laden hochgezogen.
  static const double minVolume = 0.65;

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
  ///
  /// 2026-07-25 (vucko „vor jedem Start der App soll die Sprachnavigation
  /// deaktiviert sein"): Der Modus wird BEWUSST NICHT mehr aus den Prefs
  /// wiederhergestellt — jeder App-Start beginnt stumm, der Nutzer schaltet
  /// die Ansagen pro Fahrt bewusst ein. Grund: ein von der letzten Nutzung
  /// „hängengebliebener" An-Zustand führte zu Ansagen, die nicht mehr sauber
  /// liefen. Die LAUTSTÄRKE bleibt weiterhin gemerkt, damit die einmal
  /// eingestellte Vorliebe erhalten bleibt.
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _mode = VoiceMode.off;
    // Altlasten entfernen, damit kein toter Zustand liegen bleibt.
    await prefs.remove(_keyModeLegacy);
    await prefs.remove(_keyEnabledLegacy);
    final vol = prefs.getDouble(_keyVolume);
    if (vol != null && vol.isFinite) _volume = vol.clamp(minVolume, 1.0);
    _loaded = true;
    notifyListeners();
  }

  /// Setzt die Ansage-Lautstärke (0..1), persistiert + benachrichtigt.
  Future<void> setVolume(double v) async {
    final clamped = v.isFinite ? v.clamp(minVolume, 1.0).toDouble() : _volume;
    if ((clamped - _volume).abs() < 0.001) return;
    _volume = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVolume, clamped);
  }

  /// Nur Session-State — bewusst NICHT persistiert (siehe load()).
  Future<void> setMode(VoiceMode m) async {
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
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
