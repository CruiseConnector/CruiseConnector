import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cruise_connect/application/providers/app_accent_provider.dart';
import 'package:cruise_connect/data/services/tts_service.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';

/// 2026-06-23 (vucko Voice-Lautstärke): Ästhetisches Bottom-Sheet zum Einstellen
/// der Ansage-Lautstärke. Wird gezeigt, wenn der Nutzer die Sprachansagen nach
/// komplettem Ausschalten WIEDER einschaltet. Bei jeder Änderung sagt eine
/// Test-Stimme „Navigation aktiviert" in der neuen Lautstärke, damit man sie
/// kalibrieren kann (vorher fix + zu leise). Schließt sich nicht von selbst,
/// stört also nicht — der Nutzer tippt „Fertig".
Future<void> showVoiceVolumeSheet(BuildContext context) {
  // 2026-07-02 (vucko Geräte-Video Voice-Chaos): Solange das Sheet offen ist,
  // keine Navigations-Ansagen — die Test-Stimme und echte Manöver-Ansagen
  // queuten sich sonst gegenseitig („fünf verschiedene Sachen nach Start").
  TtsService.instance.navSuppressed = true;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _VoiceVolumeSheet(),
  ).whenComplete(() => TtsService.instance.navSuppressed = false);
}

/// Untergrenze des Reglers — selbst „leise" bleibt klar hörbar.
///
/// 2026-07-25 (vucko „Navi auch bei leise gestellt laut genug hören"): 0.4 → 0.65,
/// und die Grenze liegt jetzt im [VoiceSettingsService] (Source of Truth), damit
/// auch ein BEREITS gespeicherter kleinerer Wert beim Laden hochgezogen wird —
/// sonst hätte der Fix für bestehende Installationen gar nicht gegriffen.
/// Grund für die Anhebung: Diese Lautstärke regelt NUR die Sprachausgabe selbst
/// und vertieft das Ducking der Musik nicht (die Ducking-Tiefe ist systemseitig
/// fix und per API nicht verstärkbar).
const double _kMinVolume = VoiceSettingsService.minVolume;

class _VoiceVolumeSheet extends StatefulWidget {
  const _VoiceVolumeSheet();

  @override
  State<_VoiceVolumeSheet> createState() => _VoiceVolumeSheetState();
}

class _VoiceVolumeSheetState extends State<_VoiceVolumeSheet> {
  late double _volume;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _volume = VoiceSettingsService.instance.volume.clamp(_kMinVolume, 1.0);
    // Sofort eine Test-Ansage in der aktuellen Lautstärke, damit der Nutzer
    // gleich hört, wie laut es ist.
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakTest());
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  void _speakTest() {
    unawaited(
      TtsService.instance.speakPreview('Navigation aktiviert', volume: _volume),
    );
  }

  void _onChanged(double v) {
    setState(() => _volume = v);
    // Live an die Engine geben (für den Fall, dass gerade eine Ansage läuft).
    unawaited(TtsService.instance.applyVolume(v));
  }

  /// Schnellwahl (Leise / Mittel / Laut) — setzt + persistiert + spricht eine
  /// Test-Ansage, damit der Unterschied der Stufen sofort hörbar ist.
  void _setPreset(double v) {
    setState(() => _volume = v);
    unawaited(VoiceSettingsService.instance.setVolume(v));
    unawaited(TtsService.instance.applyVolume(v));
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 60), _speakTest);
  }

  void _onChangeEnd(double v) {
    unawaited(VoiceSettingsService.instance.setVolume(v));
    // Kurz entprellt, damit beim Loslassen genau EINE Test-Ansage kommt.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 120), _speakTest);
  }

  Widget _presetChip(String label, double value, Color accent) {
    final selected = (_volume - value).abs() < 0.03;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setPreset(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? accent
                  : Colors.white.withValues(alpha: 0.10),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccentColors.accent;
    final pct = (_volume * 100).round();
    final icon = _volume <= 0.01
        ? Icons.volume_mute_rounded
        : _volume < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2028),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Sprachansagen an',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Lautstärke einstellen — du hörst jede Änderung',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                      thumbColor: accent,
                      overlayColor: accent.withValues(alpha: 0.18),
                      trackHeight: 5,
                    ),
                    child: Slider(
                      value: _volume.clamp(_kMinVolume, 1.0),
                      // 2026-06-24 (vucko Voice-zu-leise): Boden bei 0.4, damit
                      // selbst „leise" noch klar hörbar ist; volle Stufe = 1.0
                      // (Maximum). Stufen (divisions) machen den Unterschied
                      // zwischen leise/mittel/laut deutlich fühlbar.
                      min: _kMinVolume,
                      max: 1.0,
                      divisions: 6,
                      onChanged: _onChanged,
                      onChangeEnd: _onChangeEnd,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$pct%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Klare Schnellstufen — der Nutzer hört sofort den Unterschied.
            Row(
              children: [
                _presetChip('Leise', 0.70, accent),
                const SizedBox(width: 8),
                _presetChip('Mittel', 0.85, accent),
                const SizedBox(width: 8),
                _presetChip('Laut', 1.0, accent),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _speakTest,
                  icon: Icon(Icons.replay_rounded, color: accent, size: 18),
                  label: Text(
                    'Nochmal testen',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    unawaited(
                      VoiceSettingsService.instance.setVolume(_volume),
                    );
                    unawaited(TtsService.instance.stop());
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Fertig',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
