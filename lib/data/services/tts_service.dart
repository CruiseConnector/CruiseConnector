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
  Future<void>? _initFuture;
  int _speechEpoch = 0;
  String? _lastSpoken;
  DateTime? _lastSpokenAt;

  Future<void> _initIfNeeded() async {
    if (_initialized) return;
    final runningInit = _initFuture;
    if (runningInit != null) {
      await runningInit;
      return;
    }
    _initFuture = _configure();
    try {
      await _initFuture!;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _configure() async {
    try {
      // 2026-06-05 (vucko Task #6): iOS-Audiosession konfigurieren. OHNE diese
      // wird die ERSTE Ansage im Fahrbetrieb von laufender Musik/anderem Audio
      // verschluckt oder kommt verspätet (Session schläft). playback +
      // duckOthers/mixWithOthers = andere Audioquellen werden während der Ansage
      // leiser, die Navi-Stimme spielt zuverlässig.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            // 2026-06-24 (vucko Voice-zu-leise): duckOthers senkt Musik/Medien
            // während der Ansage stark ab (NICHT pausieren, danach wiederher-
            // gestellt) — wie Google/Apple Maps. KEIN mixWithOthers (das ließ die
            // Stimme gleichrangig neben der Musik laufen → bei lauter Musik kaum
            // hörbar).
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            // 2026-06-25 (vucko Voice noch lauter durchsetzen): der von Apple für
            // Turn-by-Turn-Navi empfohlene Begleiter zu duckOthers. Pausiert
            // FREMDE Sprach-Audios (Podcast/Hörbuch) während der Ansage, damit die
            // Navi-Stimme nicht gegen anderes Gerede anredet. Musik bleibt nur
            // geduckt (nicht pausiert).
            IosTextToSpeechAudioCategoryOptions
                .interruptSpokenAudioAndMixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
        await _tts.setSharedInstance(true);
      }
      // 2026-06-25 (vucko Voice lauter/Ducking): Android hatte bisher KEINE
      // Audio-Attribute → flutter_tts spielte als normales Medien-Audio, das
      // laufende Musik kaum absenkt (genau das „zu leise"-Gefühl). Mit
      // setAudioAttributesForNavigation läuft die Stimme als USAGE_ASSISTANCE_
      // NAVIGATION_GUIDANCE → das System duckt Musik/Medien während der Ansage
      // spürbar (wie Google Maps), die Navi-Stimme wird klar dominant.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _tts.setAudioAttributesForNavigation();
        } catch (e) {
          debugPrint('[TtsService] navAudioAttributes failed: $e');
        }
      }
      await _tts.setLanguage('de-DE');
      await _tts.setSpeechRate(0.50); // 0.5 = natürlich, motorradtauglich
      await _tts.setPitch(1.0);
      // 2026-06-23 (vucko Voice-Lautstärke): aus den Einstellungen statt fix 0.95.
      await _tts.setVolume(VoiceSettingsService.instance.volume);
      await _tts.awaitSpeakCompletion(false); // don't block
      _initialized = true;
    } catch (e) {
      debugPrint('[TtsService] init failed: $e');
    }
  }

  /// Initialisiert Engine + iOS-Audiosession vor der ersten echten Ansage.
  Future<void> prepare() async {
    if (!_shouldSpeak(isImportant: true)) return;
    await _initIfNeeded();
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
    final epoch = interrupt ? ++_speechEpoch : _speechEpoch;
    await _initIfNeeded();
    if (epoch != _speechEpoch) return;
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
    final epoch = _speechEpoch;
    await _initIfNeeded();
    if (epoch != _speechEpoch) return;
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
      _speechEpoch++;
      await _tts.stop();
    } catch (_) {}
  }

  /// 2026-06-23 (vucko Voice-Lautstärke): Lautstärke LIVE auf die Engine
  /// anwenden (während der Nutzer den Slider zieht).
  Future<void> applyVolume(double volume) async {
    final v = volume.isFinite ? volume.clamp(0.0, 1.0).toDouble() : 0.95;
    try {
      await _initIfNeeded();
      await _tts.setVolume(v);
    } catch (e) {
      debugPrint('[TtsService] applyVolume failed: $e');
    }
  }

  /// 2026-06-23 (vucko Voice-Lautstärke): Test-Ansage für den Lautstärke-Dialog —
  /// spricht UNABHÄNGIG vom Modus-Gate (der Nutzer stellt gerade erst ein) in der
  /// übergebenen Lautstärke, bricht eine laufende Test-Ansage hart ab.
  Future<void> speakPreview(String text, {required double volume}) async {
    try {
      await _initIfNeeded();
      _speechEpoch++; // laufende (Test-)Ansage abbrechen
      await _tts.stop();
      await _tts.setVolume(volume.isFinite ? volume.clamp(0.0, 1.0) : 0.95);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TtsService] speakPreview failed: $e');
    }
  }
}
