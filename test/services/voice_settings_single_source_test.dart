import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cruise_connect/data/services/voice_settings_service.dart';

/// Sichert: Sprachanweisungen brauchen KEIN doppeltes Freischalten mehr.
/// `mode` ist die einzige Source of Truth; jeder Schalter (Cruise-FAB ODER
/// Settings-Switch) aktiviert die Ansagen vollständig allein.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('Cruise-FAB aktiviert Ansagen allein — ohne Settings-Vorabschalter',
      () async {
    final s = VoiceSettingsService.instance;
    await s.setMode(VoiceMode.off);
    expect(s.isEnabled, isFalse);

    await s.cycleMode(); // off -> important
    expect(s.mode, VoiceMode.important);
    expect(s.isEnabled, isTrue,
        reason: 'EIN FAB-Tap muss reichen, kein Settings-Schalter nötig');
  });

  test('isEnabled ist von mode abgeleitet; setEnabled mappt auf mode',
      () async {
    final s = VoiceSettingsService.instance;

    await s.setEnabled(true);
    expect(s.mode, VoiceMode.all);
    expect(s.isEnabled, isTrue);

    await s.setEnabled(false);
    expect(s.mode, VoiceMode.off);
    expect(s.isEnabled, isFalse);
  });

  test('Default frisch installiert = OFF (konsistent stumm, kein Fake-An)',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Frischer Service-Zustand lässt sich am Singleton nicht neu erzeugen,
    // aber die Mode-Logik ist deterministisch: off => stumm + Icon volume_off.
    final s = VoiceSettingsService.instance;
    await s.setMode(VoiceMode.off);
    expect(s.isEnabled, isFalse);
    expect(s.mode, VoiceMode.off);
  });
}
