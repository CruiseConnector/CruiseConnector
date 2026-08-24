import 'dart:async';

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
///
/// 2026-08-24: Der Abschluss haengt seitdem am KONTO und nicht mehr nur am
/// Geraet — siehe [spalteAbschluss]. Der Geraete-Merker bleibt als
/// Schnellpfad bestehen (kein Netzweg im Normalfall), aber er ist nicht mehr
/// die Wahrheit. Wer die App loescht und neu holt, spielt die Tour nicht
/// noch einmal.
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

  /// 2026-08-24 (Aufgabe 1). Vucko: „aber nicht das wenn man die app loescht
  /// und sie nochmal holt das man wieder das tutorial spielen kann das
  /// tutorial bzw. das onboarding soll einmal pro account absolviert werden".
  ///
  /// Die Spalte auf `profiles`, in der genau das steht (Migration
  /// 20260824150000). NULL heisst „laeuft noch", ein Zeitstempel heisst
  /// „durch" — abgeschlossen ODER uebersprungen, beides beendet die Tour.
  ///
  /// WARUM NICHT `starter_aufgaben`: Die Starter-Aufgabe „tutorial" wird nur
  /// beim ECHTEN Abschluss gesetzt (app_tutorial_overlay.dart, _complete).
  /// Wer ueberspringt, hinterlaesst dort nichts und saehe die Tour nach jeder
  /// Neuinstallation wieder — genau der Fall, den Vucko ausgeschlossen hat.
  /// Und die Aufgabenliste haengt am Boost; sie fuers Onboarding umzuschalten
  /// haette das einmalige Zuruecksetzen durch die Boost-Rechnung gezogen.
  ///
  /// WARUM NICHT `onboarding_completed`: Das ist der Namens-Assistent nach der
  /// Anmeldung (PostAuthGate), nicht diese Tour. GEMESSEN am 24.08.: 168 von
  /// 183 Profilen stehen dort auf true.
  static const String spalteAbschluss = 'tutorial_abgeschlossen_am';

  /// Wie lange auf die Antwort des Servers gewartet wird, bevor „noch nicht
  /// abgeschlossen" gilt. Der Wert ist bewusst grosszuegig: Vucko wollte
  /// ausdruecklich NICHT, dass das Tutorial losspringt, bevor die Antwort da
  /// ist („sonst sieht der Nutzer es kurz und es verschwindet wieder").
  /// Gewartet wird nur, solange lokal nichts steht — also einmal nach einer
  /// Neuinstallation, nicht bei jedem Start.
  static const Duration kontoAbfrageGeduld = Duration(seconds: 8);

  /// 2026-08-24 (Aufgabe 2). Vucko: „lass jeden account mit der neuen version
  /// vorerst das tutorial durchspielen ich muss es testen".
  ///
  /// Das ist ein EINMALIGER Vorgang, kein Dauerzustand — sonst widerspraeche
  /// er dem Satz aus Aufgabe 1. Die Zahl steht in den Preferences; ist der
  /// gespeicherte Stand kleiner, wird der Geraete-Merker EIN Mal geloescht und
  /// der Stand hochgezogen. Danach greift es nie wieder, auch nicht bei der
  /// naechsten Version — dafuer muesste jemand diese Konstante bewusst erhoehen.
  ///
  /// Die Serverseite braucht dafuer kein UPDATE: [spalteAbschluss] ist neu und
  /// damit fuer alle 183 Profile NULL. Beides zusammen ergibt „einmal fuer
  /// alle".
  ///
  /// WAS DABEI NICHT ANGERUEHRT WIRD (Vucko: „darf NICHT den Boost oder die
  /// schon erledigten anderen Aufgaben mitreissen"): die Starter-Aufgaben,
  /// `starter_bonus_ende`, die Abzeichen und der Merker fuer die 125 XP. Hier
  /// faellt ausschliesslich `app_tutorial_v2_completed`.
  static const int ruecksetzGeneration = 1;
  static const String ruecksetzGenerationKey =
      'app_tutorial_ruecksetz_generation';

  /// Laeuft gerade eine ausdrueckliche Wiederholung (Einstellungen oder
  /// Starter-Karte)? Dann darf die Konto-Antwort das Tutorial NICHT wieder
  /// wegdruecken — der Server sagt ja voellig zu Recht „schon abgeschlossen".
  static const String wiederholungKey = 'app_tutorial_wiederholung_v1';

  /// Die Antwort des Servers, gemerkt fuer die Laufzeit der App. `hasCompleted`
  /// wird waehrend der Fahrt im Sekundentakt abgefragt (cruise_mode_page); ohne
  /// dieses Gedaechtnis waere das jedes Mal ein Netzweg.
  static String? _kontoAntwortFuer;
  static bool _kontoAntwort = false;
  static Future<bool>? _laufendeKontoAbfrage;

  /// Ersetzbar, damit Tests ohne Supabase auskommen. Bekommt die Nutzerkennung
  /// und liefert, ob dieses KONTO das Onboarding hinter sich hat.
  @visibleForTesting
  static Future<bool> Function(String nutzerId)? kontoLeserFuerTests;

  /// Ersetzbar, damit Tests ohne Supabase auskommen.
  @visibleForTesting
  static Future<void> Function(String nutzerId)? kontoSchreiberFuerTests;

  /// Nur fuer Tests: verwirft das Laufzeit-Gedaechtnis der Konto-Antwort.
  @visibleForTesting
  static void resetKontoGedaechtnisFuerTests() {
    _kontoAntwortFuer = null;
    _kontoAntwort = false;
    _laufendeKontoAbfrage = null;
  }

  /// Hat das Onboarding auf diesem Geraet ODER auf diesem Konto stattgefunden?
  ///
  /// REIHENFOLGE, und die ist der ganze Punkt: Steht lokal schon „ja", wird
  /// nichts gefragt — der haeufige Fall kostet keinen Netzweg. Steht lokal
  /// nichts, WARTET diese Methode auf den Server, bevor sie `false` liefert.
  /// Sonst startet das Tutorial im ersten Moment nach der Neuinstallation und
  /// verschwindet, sobald die Antwort eintrifft.
  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await _stelleEinmaligeRuecksetzungSicher(prefs);
    final key = await _completedKeyFuerKonto(prefs);
    if (prefs.getBool(key) ?? false) return true;

    // Eine ausdrueckliche Wiederholung schlaegt den Server. Sonst waere
    // „Tutorial nochmal ansehen" ab heute eine tote Schaltflaeche: der Server
    // sagt „abgeschlossen", und das Overlay ginge sofort wieder zu.
    if (prefs.getBool(NutzerPrefsSchluessel.fuer(wiederholungKey)) ?? false) {
      return false;
    }

    if (!await _kontoHatAbgeschlossen()) return false;
    // Einmal gelernt, nie wieder gefragt — auch nicht ohne Netz.
    await prefs.setBool(key, true);
    return true;
  }

  /// Loescht den Geraete-Merker GENAU EIN MAL, siehe [ruecksetzGeneration].
  static Future<void> _stelleEinmaligeRuecksetzungSicher(
    SharedPreferences prefs,
  ) async {
    final generationKey = NutzerPrefsSchluessel.fuer(ruecksetzGenerationKey);
    if ((prefs.getInt(generationKey) ?? 0) >= ruecksetzGeneration) return;
    // ZUERST hochschreiben: Bricht danach etwas ab, laeuft der Vorgang
    // trotzdem nicht ein zweites Mal. Ein verpasstes Zuruecksetzen ist
    // harmlos, ein wiederkehrendes waere genau der Fehler aus Aufgabe 1.
    await prefs.setInt(generationKey, ruecksetzGeneration);
    await prefs.remove(await _completedKeyFuerKonto(prefs));
    await prefs.remove(completedKey);
    debugPrint('[Tutorial] Einmalige Ruecksetzung auf Generation '
        '$ruecksetzGeneration ausgefuehrt.');
  }

  /// Fragt das Konto — hoechstens einmal pro Sitzung und pro Kennung.
  static Future<bool> _kontoHatAbgeschlossen() {
    final nutzerId = NutzerPrefsSchluessel.aktuelleNutzerId();
    if (nutzerId == null || nutzerId.isEmpty) return Future.value(false);
    if (_kontoAntwortFuer == nutzerId) return Future.value(_kontoAntwort);
    return _laufendeKontoAbfrage ??= _frageKonto(nutzerId);
  }

  static Future<bool> _frageKonto(String nutzerId) async {
    try {
      final leser = kontoLeserFuerTests;
      final bool ergebnis;
      if (leser != null) {
        ergebnis = await leser(nutzerId);
      } else {
        final zeile = await Supabase.instance.client
            .from('profiles')
            .select(spalteAbschluss)
            .eq('id', nutzerId)
            .maybeSingle()
            .timeout(kontoAbfrageGeduld);
        ergebnis = zeile != null && zeile[spalteAbschluss] != null;
      }
      _kontoAntwortFuer = nutzerId;
      _kontoAntwort = ergebnis;
      return ergebnis;
    } catch (e) {
      // BEWUSST NICHT GEMERKT: Beim naechsten Aufruf wird wieder gefragt. Ein
      // Netzausfall darf einem Bestandskonto das Onboarding nicht dauerhaft
      // aufdraengen — und einem neuen Konto nicht dauerhaft vorenthalten.
      debugPrint('[Tutorial] Konto-Abfrage fehlgeschlagen: $e');
      return false;
    } finally {
      _laufendeKontoAbfrage = null;
    }
  }

  /// Schreibt den Abschluss ans Konto. Der Waechter
  /// `trg_guard_tutorial_abschluss` macht den Wert schreib-einmalig und setzt
  /// den Zeitpunkt selbst — hier reicht deshalb ein schlichtes UPDATE.
  static Future<void> _schreibeKontoAbschluss() async {
    final nutzerId = NutzerPrefsSchluessel.aktuelleNutzerId();
    if (nutzerId == null || nutzerId.isEmpty) return;
    try {
      final schreiber = kontoSchreiberFuerTests;
      if (schreiber != null) {
        await schreiber(nutzerId);
        return;
      }
      await Supabase.instance.client
          .from('profiles')
          .update({spalteAbschluss: DateTime.now().toUtc().toIso8601String()})
          .eq('id', nutzerId);
    } catch (e) {
      // Der lokale Merker steht bereits. Beim naechsten Abschluss oder beim
      // naechsten Geraet wird es erneut versucht.
      debugPrint('[Tutorial] Konto-Abschluss schreiben fehlgeschlagen: $e');
    }
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
    // Die Wiederholung ist vorbei — ab jetzt darf die Konto-Antwort wieder
    // gelten.
    await prefs.remove(NutzerPrefsSchluessel.fuer(wiederholungKey));
    // „nachdem die Aufgabe abgeschlossen ist, [wird] es wieder zum
    // vorherigen" - Abschliessen UND Ueberspringen laufen beide hier durch.
    onboardingAnsichtAktiv.value = false;

    // 2026-08-24 (Aufgabe 1): Ab jetzt weiss es auch das KONTO. Ueberspringen
    // laeuft absichtlich hier mit durch: „einmal pro account absolviert" meint
    // die Tour, nicht die Belohnung. Die 125 XP und das Abzeichen haengen
    // weiterhin am echten Abschluss (siehe _complete im Overlay).
    final nutzerId = NutzerPrefsSchluessel.aktuelleNutzerId();
    if (nutzerId != null && nutzerId.isNotEmpty) {
      _kontoAntwortFuer = nutzerId;
      _kontoAntwort = true;
    }
    unawaited(_schreibeKontoAbschluss());
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _completedKeyFuerKonto(prefs);
    await prefs.remove(key);
    // Der alte kontolose Wert MUSS mit weg: sonst wuerde ihn der naechste
    // Aufruf sofort wieder ins Konto uebernehmen und das Tutorial waere
    // wieder „gesehen", bevor es das zweite Mal laufen konnte.
    await prefs.remove(completedKey);
    // 2026-08-24 (Aufgabe 1): Und der Server MUSS ueberstimmt werden. Er sagt
    // ab dem ersten Abschluss „durch" — ohne diesen Merker waere „Tutorial
    // nochmal ansehen" wirkungslos. Der Merker liegt in den Preferences und
    // nicht nur im Speicher, damit eine Wiederholung auch einen App-Neustart
    // uebersteht.
    await prefs.setBool(NutzerPrefsSchluessel.fuer(wiederholungKey), true);
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
