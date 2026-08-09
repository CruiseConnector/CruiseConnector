import 'package:cruise_connect/core/app_changelog.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Merkt sich, welche Version der Nutzer zuletzt gesehen hat, und entscheidet
/// daraus, ob nach einem Update der Neuerungen-Hinweis faellig ist.
///
/// 2026-08-09 (vucko): „Nach jedem Update soll ein Update-Log kommen."
///
/// Zwei bewusste Entscheidungen:
///  * Wer die App frisch installiert, bekommt KEINEN Update-Hinweis. Fuer den
///    ist alles neu — ein „Das ist neu"-Blatt waere sinnlos und stuende dem
///    Onboarding im Weg. Beim ersten Start wird die aktuelle Version einfach
///    stillschweigend als gesehen vermerkt.
///  * Der Hinweis wird als gesehen markiert, sobald er ANGEZEIGT wurde, nicht
///    erst beim Wegtippen. Sonst kaeme er bei jedem Tab-Wechsel wieder.
class ChangelogService {
  ChangelogService._();

  static const String _gesehenKey = 'changelog_gesehene_version';

  static final ChangelogService instance = ChangelogService._();

  /// Nur fuer Tests: erlaubt es, die Versionsermittlung zu ersetzen.
  @visibleForTesting
  static Future<String> Function()? versionsLeser;

  static Future<String> _aktuelleVersion() async {
    final leser = versionsLeser;
    if (leser != null) return leser();
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Der faellige Eintrag — oder `null`, wenn nichts anzuzeigen ist.
  Future<ChangelogEintrag?> faelligerEintrag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final aktuell = await _aktuelleVersion();
      final gesehen = prefs.getString(_gesehenKey);

      if (gesehen == null) {
        // Erstinstallation (oder erste Version mit dieser Funktion): merken,
        // aber nichts zeigen.
        await prefs.setString(_gesehenKey, aktuell);
        return null;
      }
      if (gesehen == aktuell) return null;

      final eintrag = AppChangelog.fuerVersion(aktuell);
      if (eintrag == null) {
        // Version ohne gepflegten Eintrag: nichts zeigen, aber trotzdem
        // fortschreiben — sonst haengt der Hinweis fuer immer nach.
        await prefs.setString(_gesehenKey, aktuell);
        return null;
      }
      return eintrag;
    } catch (e) {
      debugPrint('[Changelog] Pruefung fehlgeschlagen: $e');
      return null;
    }
  }

  Future<void> markiereGesehen(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gesehenKey, version);
    } catch (e) {
      debugPrint('[Changelog] Konnte Version nicht merken: $e');
    }
  }

  /// Setzt den Stand zurueck, damit der Hinweis erneut erscheint
  /// (Einstellungen → „Neuerungen anzeigen").
  Future<void> zuruecksetzen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_gesehenKey);
  }

  /// Der Eintrag zur laufenden Version, unabhaengig vom Gesehen-Stand.
  Future<ChangelogEintrag?> aktuellerEintrag() async {
    try {
      return AppChangelog.fuerVersion(await _aktuelleVersion());
    } catch (e) {
      debugPrint('[Changelog] Version nicht lesbar: $e');
      return null;
    }
  }
}
