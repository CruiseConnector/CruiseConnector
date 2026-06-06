import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';

/// Singleton-Wrapper um flutter_tts.
/// Respektiert VoiceSettingsService (off / important / all).
///
/// Wichtige Manöver = ≤300m vor Abbiegung + Re-Route + Ziel erreicht.
/// Alles andere = Cruise-Status, Speed-Warning, etc.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  String? _lastSpoken;
  DateTime? _lastSpokenAt;

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    try {
      // 2026-06-05 (vucko Task #6): iOS-Audiosession konfigurieren. OHNE diese
      // wird die ERSTE Ansage im Fahrbetrieb von laufender Musik/anderem Audio
      // verschluckt oder kommt verspätet (Session schläft). playback +
      // duckOthers/mixWithOthers = andere Audioquellen werden während der Ansage
      // leiser, die Navi-Stimme spielt zuverlässig.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      await _tts.setLanguage('de-DE');
      await _tts.setSpeechRate(0.50);  // 0.5 = natürlich, motorradtauglich
      await _tts.setPitch(1.0);
      await _tts.setVolume(0.95);
      await _tts.awaitSpeakCompletion(false);  // don't block
      _initialized = true;
    } catch (e) {
      debugPrint('[TtsService] init failed: $e');
    }
  }

  bool _shouldSpeak({required bool isImportant}) {
    // 2026-06-06 (vucko): EINZIGES Gate = mode. Früher zusätzlich `isEnabled`
    // verlangt → man musste Ansagen erst in den Einstellungen freischalten,
    // bevor der Cruise-Schalter wirkte. Jetzt steuert der Modus (off/important/
    // all) allein, egal über welchen Schalter er gesetzt wurde.
    final s = VoiceSettingsService.instance;
    if (s.mode == VoiceMode.off) return false;
    if (s.mode == VoiceMode.important && !isImportant) return false;
    return true;
  }

  bool _isDuplicate(String text) {
    if (_lastSpoken != text) return false;
    final age = _lastSpokenAt == null
        ? Duration.zero
        : DateTime.now().difference(_lastSpokenAt!);
    return age < const Duration(seconds: 8);
  }

  /// Wichtige Ansagen (Manöver, Re-Route, Ziel-erreicht).
  ///
  /// [interrupt] = laufende Ansage hart abbrechen. NUR für echte Prioritäts-
  /// Interrupts (Reroute, Ziel erreicht). Für normale Manöver-Ansagen `false`
  /// (Default) → aufeinanderfolgende Ansagen queuen/laufen aus, statt sich
  /// gegenseitig mitten im Satz abzuwürgen (das war das hörbare „Abhacken").
  Future<void> speakImportant(String text, {bool interrupt = false}) async {
    if (!_shouldSpeak(isImportant: true)) return;
    if (_isDuplicate(text)) return;
    await _initIfNeeded();
    try {
      if (interrupt) {
        await _tts.stop();
      }
      _lastSpoken = text;
      _lastSpokenAt = DateTime.now();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TtsService] speak failed: $e');
    }
  }

  /// Optionale Ansagen (Status, Speed, etc.) — nur im "all" Modus.
  Future<void> speakOptional(String text) async {
    if (!_shouldSpeak(isImportant: false)) return;
    if (_isDuplicate(text)) return;
    await _initIfNeeded();
    try {
      _lastSpoken = text;
      _lastSpokenAt = DateTime.now();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TtsService] speakOptional failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
