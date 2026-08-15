import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/gamification_service.dart';

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

  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(completedKey) ?? false;
  }

  static Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(completedKey, true);
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(completedKey);
  }

  static Future<void> requestReplay() async {
    await reset();
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
    if (prefs.getBool(rewardClaimedKey) ?? false) return false;

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
        await prefs.setBool(rewardClaimedKey, true);
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

      await prefs.setBool(rewardClaimedKey, true);
      return true;
    } catch (e) {
      debugPrint('[Tutorial] Abschluss-Belohnung fehlgeschlagen: $e');
      return false;
    }
  }
}
