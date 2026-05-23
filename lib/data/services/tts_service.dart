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
    final s = VoiceSettingsService.instance;
    if (!s.isEnabled || s.mode == VoiceMode.off) return false;
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
  Future<void> speakImportant(String text) async {
    if (!_shouldSpeak(isImportant: true)) return;
    if (_isDuplicate(text)) return;
    await _initIfNeeded();
    try {
      await _tts.stop();  // unterbreche aktuelle Ansage für Wichtiges
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
