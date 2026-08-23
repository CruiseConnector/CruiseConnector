import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';

/// SCHLUESSEL-GESCHICHTE: v1 war das alte 10-Schritte-Tutorial. Mit dem
/// interaktiven Neubau (2026-08-14) wurde der Schluessel auf v2 gehoben -
/// dadurch gilt das neue Tutorial fuer ALLE als ungesehen und startet beim
/// naechsten App-Start einmal automatisch, auch fuer Bestandsnutzer (vucko:
/// "dass auf der neuesten Version das Onboarding auf meinem Account simuliert
/// wird"). Ueberspringen bleibt jederzeit moeglich.
class AppTutorialService {
  AppTutorialService._();

  static const String completedKey = 'app_tutorial_v2_completed';

  // 2026-08-14 (vucko Tutorial-Belohnung): 125 XP einmalig für den ECHTEN
  // Tutorial-Abschluss (nicht fürs Überspringen, nicht für Replays).
  static const int completionXp = 125;
  static const String rewardClaimedKey = 'app_tutorial_reward_claimed_v1';

  static final ValueNotifier<int> replayRequests = ValueNotifier<int>(0);

  /// 2026-08-24 (Aufgabe 4.6). Vucko: „moechte ich wirklich, dass beim
  /// Onboarding kurz die Ansicht so wie das alte Homescreen ist, und dann,
  /// nachdem die Aufgabe abgeschlossen ist, es wieder zum vorherigen wird -
  /// also wie es der Nutzer selber eingestellt hat."
  ///
  /// Solange das hier `true` ist, ZEIGT die Startseite die Standard-Kacheln.
  /// Gespeichert wird dabei nichts: die eigene Anordnung liegt unangetastet
  /// in den Preferences und wird beim Umschalten auf `false` wieder
  /// hergestellt. Der Schalter haengt am Tutorial-Status, weil genau das das
  /// Onboarding ist: solange es nicht abgeschlossen oder uebersprungen wurde,
  /// laeuft es.
  static final ValueNotifier<bool> onboardingAnsichtAktiv =
      ValueNotifier<bool>(false);

  /// Der kontogebundene Schluessel (Nebenfund 1 der Aufgabe 4.6): ein zweites
  /// Konto auf demselben Handy erbte bisher den Tutorial-Status des ersten
  /// und bekam deshalb gar kein Onboarding.
  static Future<String> _completedKeyFuerKonto(SharedPreferences prefs) =>
      NutzerPrefsSchluessel.vorbereitet(prefs, completedKey);

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _completedKeyFuerKonto(prefs);
    return prefs.getBool(key) ?? false;
  }

  /// Setzt [onboardingAnsichtAktiv] auf den Stand der Dinge. Auf Web laeuft
  /// kein Tutorial (`home_page.dart` blockt es mit `kIsWeb`) - dort duerfte
  /// die Standard-Ansicht sonst fuer immer haengenbleiben.
  static Future<void> pruefeOnboardingAnsicht() async {
    if (kIsWeb) {
      onboardingAnsichtAktiv.value = false;
      return;
    }
    onboardingAnsichtAktiv.value = !await hasCompleted();
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _completedKeyFuerKonto(prefs);
    await prefs.setBool(key, true);
    // „nachdem die Aufgabe abgeschlossen ist, [wird] es wieder zum
    // vorherigen" - Abschliessen UND Ueberspringen laufen beide hier durch.
    onboardingAnsichtAktiv.value = false;
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _completedKeyFuerKonto(prefs);
    await prefs.remove(key);
    // Der alte kontolose Wert MUSS mit weg: sonst wuerde ihn der naechste
    // Aufruf sofort wieder ins Konto uebernehmen und das Tutorial waere
    // wieder „gesehen", bevor es das zweite Mal laufen konnte.
    await prefs.remove(completedKey);
  }

  static Future<void> requestReplay() async {
    await reset();
    if (!kIsWeb) onboardingAnsichtAktiv.value = true;
    replayRequests.value += 1;
  }

  /// Schreibt die 125 XP als Drive-Session-Zeile (distance 0, xp 125) — der
  /// einzige XP-Pfad der App. Duplikat-Schutz ZWEISTUFIG:
  ///
  /// 1. Lokales SharedPreferences-Flag als Schnellpfad (kein Netz nötig).
  /// 2. Supabase-Query VOR dem Insert: existiert schon eine Session des
  ///    Nutzers mit xp_awarded=125 und distance_km=0 (z.B. Replay über die
  ///    Einstellungen, Neuinstallation, zweites Gerät), wird NICHT erneut
  ///    vergeben — nur das lokale Flag nachgezogen.
  ///
  /// Gibt true zurück, wenn die XP JETZT vergeben wurden.
  static Future<bool> claimCompletionReward() async {
    final prefs = await SharedPreferences.getInstance();
    // Kontogebunden (Aufgabe 4.6, Nebenfund 1): sonst blockt das Flag des
    // ersten Kontos die 125 XP des zweiten Kontos auf demselben Handy.
    final claimKey = await NutzerPrefsSchluessel.vorbereitet(
      prefs,
      rewardClaimedKey,
    );
    if (prefs.getBool(claimKey) ?? false) return false;

    final db = Supabase.instance.client;
    final userId = db.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final existing = await db
          .from('user_drive_sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('xp_awarded', completionXp)
          .eq('distance_km', 0)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        await prefs.setBool(claimKey, true);
        return false;
      }

      // completedAtEnd bewusst false: die Belohnungszeile darf NICHT als
      // „abgeschlossene Fahrt" zählen (sonst gäbe es badge_02 „Erste Fahrt"
      // fürs Tutorial). distanceKm 0 + xpAwarded 125 passiert den Guard in
      // recordDriveSession (distanceKm<=0 && xpAwarded<=0 → nur dann Abbruch).
      final session = await GamificationService.recordDriveSession(
        distanceKm: 0,
        durationSeconds: 0,
        completedAtEnd: false,
        source: 'tutorial',
        xpAwarded: completionXp,
      );
      if (session == null) return false;

      await prefs.setBool(claimKey, true);
      return true;
    } catch (e) {
      debugPrint('[Tutorial] Abschluss-Belohnung fehlgeschlagen: $e');
      return false;
    }
  }
}
