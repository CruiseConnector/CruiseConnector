import 'package:cruise_connect/core/app_changelog.dart';
import 'package:cruise_connect/data/services/changelog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final aktuell = AppChangelog.eintraege.first.version;

  tearDown(() => ChangelogService.versionsLeser = null);

  // 2026-08-11 (vucko, ausdrueckliche Entscheidung): Der Hinweis kommt AUCH
  // bei frischer Installation. Die erste Fassung unterdrueckte ihn dort — mit
  // der Folge, dass auch das allererste Update mit dieser Funktion wie eine
  // Erstinstallation aussah und der Hinweis nie erschien, bei niemandem.
  test('auch die Erstinstallation zeigt den Hinweis — genau einmal', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ChangelogService.versionsLeser = () async => aktuell;

    final eintrag = await ChangelogService.instance.faelligerEintrag();
    expect(eintrag, isNotNull);
    expect(eintrag!.version, aktuell);

    await ChangelogService.instance.markiereGesehen(eintrag.version);
    expect(await ChangelogService.instance.faelligerEintrag(), isNull);
  });

  test('Nach einem Update kommt der Hinweis genau einmal', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'changelog_gesehene_version': '1.0.0',
    });
    ChangelogService.versionsLeser = () async => aktuell;

    final eintrag = await ChangelogService.instance.faelligerEintrag();
    expect(eintrag, isNotNull);
    expect(eintrag!.version, aktuell);

    // home_page markiert direkt nach dem Anzeigen — danach ist Ruhe.
    await ChangelogService.instance.markiereGesehen(eintrag.version);
    expect(await ChangelogService.instance.faelligerEintrag(), isNull);
  });

  test('Version ohne gepflegten Eintrag haengt nicht ewig nach', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'changelog_gesehene_version': '1.0.0',
    });
    ChangelogService.versionsLeser = () async => '9.9.9';

    expect(await ChangelogService.instance.faelligerEintrag(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('changelog_gesehene_version'), '9.9.9');
  });

  test('Jeder Eintrag hat Titel und mindestens einen Punkt', () {
    for (final e in AppChangelog.eintraege) {
      expect(e.version.trim(), isNotEmpty);
      expect(e.titel.trim(), isNotEmpty);
      expect(e.punkte, isNotEmpty, reason: 'Version ${e.version} ist leer');
    }
  });
}
