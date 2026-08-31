import 'package:cruise_connect/core/kurven_zaehler.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cruise_connect/data/services/offline_fahrten_warteschlange.dart';
import 'package:cruise_connect/data/services/social_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:cruise_connect/domain/models/badge.dart';
import 'package:cruise_connect/data/services/nutzer_prefs_schluessel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cruise_connect/domain/models/user_drive_session.dart';
import 'package:cruise_connect/domain/models/user_level.dart';

/// Ergebnis der Gamification-Berechnung.
class GamificationResult {
  const GamificationResult({
    required this.level,
    required this.earnedBadgeIds,
    required this.newBadgeIds,
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalHours,
    required this.totalXp,
    this.completedRides = 0,
    this.completedGroupRides = 0,
    this.routePosts = 0,
    this.createdGroups = 0,
    this.savedRoutes = 0,
    this.longestRideKm = 0,
    this.fruehFahrten = 0,
    this.nachtFahrten = 0,
    this.wochenendFahrten = 0,
    this.besteSerieTage = 0,
    this.kurvenjagdFahrten = 0,
    this.gefahreneStile = 0,
    this.rundkurse = 0,
    this.aNachBFahrten = 0,
    this.fahrzeuge = 0,
    this.beitraege = 0,
    this.hashtagBeitraege = 0,
    this.meldungen = 0,
  });

  final UserLevel level;
  final List<String> earnedBadgeIds;
  final List<String> newBadgeIds;
  final int totalRoutes;
  final double totalDistanceKm;
  final double totalHours;
  final int totalXp;

  /// 2026-08-15 (vucko): „bei den gesperrten Badges soll man den Fortschritt
  /// sehen — 274 von 1000 km." Dafuer braucht die Oberflaeche dieselben
  /// Zaehler, aus denen die Freischaltung berechnet wird. Sie liegen im Sync
  /// ohnehin vor; hier werden sie nur mitgeliefert.
  final int completedRides;
  final int completedGroupRides;
  final int routePosts;
  final int createdGroups;
  final int savedRoutes;
  final double longestRideKm;

  /// 2026-08-16 (T6): Zaehler fuer badge_23 … badge_36 (siehe
  /// [SessionKennzahlen]).
  final int fruehFahrten;
  final int nachtFahrten;
  final int wochenendFahrten;
  final int besteSerieTage;
  final int kurvenjagdFahrten;
  final int gefahreneStile;
  final int rundkurse;
  final int aNachBFahrten;

  /// 2026-08-24: Zaehler fuer die vier neuen Familien badge_59 … badge_70
  /// (Garage, Beitraege, Hashtags, Meldungen). Sie liegen im Sync ohnehin vor
  /// und werden hier nur mitgeliefert — dieselbe Begruendung wie oben bei den
  /// Fahr-Kennzahlen: die Sammlung zeigt den Fortschritt aus derselben Zahl,
  /// aus der auch freigeschaltet wird.
  final int fahrzeuge;
  final int beitraege;
  final int hashtagBeitraege;
  final int meldungen;

  List<Badge> get earnedBadges =>
      earnedBadgeIds.map(Badge.getById).whereType<Badge>().toList();

  List<Badge> get newBadges =>
      newBadgeIds.map(Badge.getById).whereType<Badge>().toList();
}

/// Liest die Antwort der RPC `meine_badge_kennzahlen`.
///
/// Eigene Funktion, damit sie ohne Datenbank pruefbar ist. Sie muss robust
/// sein: eine alte App trifft auf eine neue Datenbank und umgekehrt, und eine
/// fehlende Zahl darf nie ein Abzeichen sperren ODER faelschlich vergeben —
/// sie wird zu 0. Negative Werte kann es fachlich nicht geben; sie werden
/// gekappt, statt eine Schwelle zu unterlaufen.
({int hashtagBeitraege, int meldungen}) badgeKennzahlenAusAntwort(
  dynamic antwort,
) {
  // PostgREST liefert bei `returns jsonb` das Objekt direkt; manche
  // Client-Fassungen packen es in eine einelementige Liste.
  final roh = antwort is List
      ? (antwort.isEmpty ? null : antwort.first)
      : antwort;
  if (roh is! Map) return (hashtagBeitraege: 0, meldungen: 0);

  int zahl(String schluessel) {
    final wert = roh[schluessel];
    if (wert is num) return wert.toInt() < 0 ? 0 : wert.toInt();
    if (wert is String) {
      final geparst = int.tryParse(wert.trim()) ?? 0;
      return geparst < 0 ? 0 : geparst;
    }
    return 0;
  }

  return (
    hashtagBeitraege: zahl('hashtag_beitraege'),
    meldungen: zahl('meldungen'),
  );
}

class RouteXpBreakdown {
  const RouteXpBreakdown({
    required this.distanceXp,
    required this.curveXp,
    required this.styleBonus,
    required this.baseXp,
    required this.streakDays,
    required this.multiplier,
    required this.totalXp,
  });

  final int distanceXp;
  final int curveXp;
  final int styleBonus;
  final int baseXp;
  final int streakDays;
  final double multiplier;
  final int totalXp;

  String get multiplierLabel => 'x${multiplier.toStringAsFixed(2)}';
}

class DriveSessionTotals {
  const DriveSessionTotals({
    required this.totalRoutes,
    required this.totalDistanceKm,
    required this.totalSeconds,
    required this.totalXp,
  });

  final int totalRoutes;
  final double totalDistanceKm;
  final double totalSeconds;
  final int totalXp;
}

/// Service für XP-, Level- und Badge-System mit Supabase-Backend.
/// 2026-08-26 (vucko, Aufgabe 7): „Ich habe die 1000-Kilometer-Marke erreicht,
/// aber die Animation dazu ist leider nicht gekommen. Das war sehr
/// frustrierend, weil ich einen Meilenstein erreicht habe und nicht mitbekomme,
/// dass ich ihn erreicht habe."
///
/// URSACHE, am Video und am Quelltext belegt: `calculateAndSync()` laeuft an
/// ZWOELF Stellen, aber nur vier davon zeigen die Verleih-Feier. Wird ein
/// Abzeichen bei einem der stillen Abgleiche freigeschaltet, schreibt der
/// Dienst es ins Profil — und beim naechsten Abgleich gilt es als „schon
/// vorhanden" und ist nie wieder neu. Es ist dann fuer immer stumm vergeben.
///
/// Genau das ist passiert: Bei Fahrtende standen erst 992 km, das Abzeichen war
/// noch nicht faellig. Beim Oeffnen der Auswertung lief der naechste Abgleich,
/// jetzt mit 1007 km — und die Auswertung kennt keine Feier.
///
/// Diese Warteschlange trennt das Freischalten vom Feiern. Freigeschaltet wird,
/// wo es anfaellt; gefeiert wird, sobald ein Bildschirm da ist, der es kann.
/// Nichts geht mehr verloren, und nichts wird doppelt gefeiert.
class OffeneAuszeichnungen {
  OffeneAuszeichnungen._();

  static const String _schluessel = 'offene_auszeichnungen_v1';

  /// Neu freigeschaltete Abzeichen vormerken. Doppelte werden verworfen.
  static Future<void> merken(List<String> badgeIds) async {
    if (badgeIds.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final k = NutzerPrefsSchluessel.fuer(_schluessel);
      final vorhanden = p.getStringList(k) ?? const <String>[];
      final zusammen = <String>{...vorhanden, ...badgeIds}.toList();
      if (zusammen.length == vorhanden.length) return;
      await p.setStringList(k, zusammen);
      debugPrint(
        '[Gamification] Vorgemerkt zum Feiern: ${badgeIds.join(', ')}',
      );
    } catch (e) {
      debugPrint('[Gamification] Vormerken fehlgeschlagen: $e');
    }
  }

  /// Was ist noch zu feiern?
  static Future<List<String>> offene() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(NutzerPrefsSchluessel.fuer(_schluessel)) ??
          const <String>[];
    } catch (e) {
      debugPrint('[Gamification] Offene Auszeichnungen nicht lesbar: $e');
      return const <String>[];
    }
  }

  /// Erst NACH der gezeigten Feier quittieren. Bricht die App vorher ab,
  /// wird beim naechsten Start erneut gefeiert — lieber einmal zu viel als
  /// ein verpasster Meilenstein.
  static Future<void> quittieren(List<String> badgeIds) async {
    if (badgeIds.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final k = NutzerPrefsSchluessel.fuer(_schluessel);
      final rest = (p.getStringList(k) ?? const <String>[])
          .where((b) => !badgeIds.contains(b))
          .toList();
      await p.setStringList(k, rest);
    } catch (e) {
      debugPrint('[Gamification] Quittieren fehlgeschlagen: $e');
    }
  }
}

class GamificationService {
  static SupabaseClient get _db => Supabase.instance.client;

  static const int xpPerDrivenKm = 10;
  static const double minRouteProgressForXp = 0.20;

  /// 2026-08-29 (Vucko: „schau, dass du vielleicht eine Regelung machst, dass
  /// man nicht so weit fahren muss").
  ///
  /// [minRouteProgressForXp] ist ein ANTEIL, und das bestraft lange Routen:
  /// Wer 100 km plant, musste 20 km fahren, damit die Fahrt ueberhaupt
  /// verbucht wird — sonst gab es keine Kilometer, keine XP und keinen
  /// Eintrag. Bei 200 km waren es 40 km. Genau das ist der Grund, warum
  /// abgebrochene Touren wirkten, als haette die App sie nicht wahrgenommen.
  ///
  /// Ab dieser Strecke zaehlt eine Fahrt IMMER, unabhaengig davon, wie lang
  /// die geplante Route war. Die beiden Regeln sind mit ODER verknuepft, die
  /// Huerde wird also nie hoeher: Bei einer 10-km-Route reichen weiterhin die
  /// 2 km aus dem Anteil.
  ///
  /// 2026-08-31 (Vucko: „dass man keine Mindeststrecke fahren muss
  /// beziehungsweise vielleicht 1 km oder so das waere ideal oder 1/2 km"):
  /// von drei auf einen Kilometer gesenkt.
  ///
  /// Ein Kilometer und nicht ein halber, weil die Offline-Warteschlange ihre
  /// Grenze bei genau einem Kilometer zieht
  /// ([OfflineFahrtenWarteschlange.mindestKmOffline]). Waere die Verbuchung
  /// grosszuegiger, entstuende ein Widerspruch: eine 700-Meter-Fahrt zaehlte
  /// online, ginge im Funkloch aber verloren, weil sie gar nicht erst
  /// aufbewahrt wird. Beide Grenzen gehoeren auf denselben Wert.
  ///
  /// Missbrauch entsteht dadurch nicht: die XP richten sich nach der
  /// GEFAHRENEN Strecke, nicht nach der geplanten.
  static const double mindestKmFuerVerbuchung = 1.0;

  /// Zaehlt diese Fahrt fuer Kilometer, XP und Abzeichen?
  ///
  /// Reine Entscheidung, damit Anzeige und Verbuchung nie auseinanderlaufen
  /// koennen — beide fragen hier.
  static bool fahrtZaehlt({
    required double gefahreneKm,
    required double fortschrittAnteil,
  }) {
    if (gefahreneKm <= 0) return false;
    if (gefahreneKm >= mindestKmFuerVerbuchung) return true;
    return fortschrittAnteil >= minRouteProgressForXp;
  }
  static const double minRouteProgressForFullXp = 0.95;
  static const Map<String, String> _legacyBadgeIds = {'route_1': 'badge_02'};

  /// 2026-08-24 (Aufgabe 3, vucko woertlich): „man soll dafuer auch ein badge
  /// bekommen wenn man es abgeschlossen hat wie startklar".
  ///
  /// Die Kennung steht hier als Literal und nicht als `Badge.…`-Konstante,
  /// weil der Katalog-Eintrag aus einer anderen Hand kommt. Bis er in
  /// `Badge.all` steht, verwirft [normalizeBadgeIds] die Kennung STILL — es
  /// wird also nichts Halbes vergeben und nichts geht kaputt. Sobald der
  /// Eintrag da ist, greift die Vergabe von selbst, auch rueckwirkend: sie
  /// haengt am ZUSTAND (Starter-Aufgabe „tutorial") und nicht an einem
  /// Ereignis. Das ist die Lehre aus dem verlorenen Startklar-Abzeichen vom
  /// 19.08.
  ///
  /// 2026-08-25: Umbenannt von `onboardingBadgeId`. Der alte Name behauptete,
  /// das sei das Abzeichen fuer das abgeschlossene Onboarding — das ist seit
  /// heute [Badge.starterBadgeId] „Startklar", zusammen mit 1000 XP und der
  /// Doppel-XP-Woche. Hier haengt das reine Sammler-Abzeichen fuer ALLE zwoelf
  /// Aufgaben, ohne XP und ohne Bonuswoche. Der alte Name bleibt als Alias.
  static const String alleAufgabenBadgeId = 'badge_58';

  /// Alter Name von [alleAufgabenBadgeId]. Siehe dort, warum er gelogen hat.
  static const String onboardingBadgeId = alleAufgabenBadgeId;

  @visibleForTesting
  static List<String> normalizeBadgeIds(Iterable<dynamic> badgeIds) {
    final activeBadgeIds = Badge.all.map((badge) => badge.id).toSet();
    final normalized = <String>{};

    for (final raw in badgeIds) {
      final id = raw?.toString().trim();
      if (id == null || id.isEmpty) continue;
      final mappedId = _legacyBadgeIds[id] ?? id;
      if (activeBadgeIds.contains(mappedId)) {
        normalized.add(mappedId);
      }
    }

    return [
      for (final badge in Badge.all)
        if (normalized.contains(badge.id)) badge.id,
    ];
  }

  @visibleForTesting
  static List<String> mergeBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    return normalizeBadgeIds([...previousBadgeIds, ...currentBadgeIds]);
  }

  @visibleForTesting
  static List<String> newlyQualifiedBadgeIds(
    Iterable<dynamic> previousBadgeIds,
    Iterable<dynamic> currentBadgeIds,
  ) {
    final previousBadgeSet = normalizeBadgeIds(previousBadgeIds).toSet();
    return normalizeBadgeIds(
      currentBadgeIds,
    ).where((badgeId) => !previousBadgeSet.contains(badgeId)).toList();
  }

  /// Berechnet XP für eine einzelne Fahrt.
  /// Quelle ist ausschließlich die tatsächlich gefahrene Distanz: 10 XP/km.
  static int calculateRouteXp({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 0,
    bool? doppelXpAktiv,
  }) {
    return calculateRouteXpBreakdown(
      distanceKm: distanceKm,
      curves: curves,
      style: style,
      streakDays: streakDays,
      doppelXpAktiv: doppelXpAktiv,
    ).totalXp;
  }

  /// 2026-08-19 (vucko): „wenn man es dann vergisst kommt man ganz normal auf
  /// 1,00xp nach dem boost."
  ///
  /// Frueher hob diese Stelle jede Fahrt auf mindestens einen Streak-Tag an
  /// (`math.max(1, streakDays)`), zusaetzlich zur gleichen Anhebung in
  /// [calculateStreakDaysForRide]. Eine Fahrt konnte deshalb NIE die reine
  /// Basis bekommen: 1,10x war das Minimum, 1,00x unerreichbar. Das
  /// widerspricht der neuen Regel, in der die Basis der Ruecksetzwert ist.
  /// Die Anhebung ist deshalb weg — der Wert wird nur noch bei Null
  /// abgeschnitten.
  ///
  /// Praktisch verliert dadurch niemand XP: die Fahrt selbst faellt auf einen
  /// Fahrtag, also liefert [calculateStreakDaysForRide] von sich aus
  /// mindestens 1. Die 1,00x taucht nur dort auf, wo bewusst ohne Serie
  /// gerechnet wird (Vorschau auf der Startseite, Anzeige nach dem Verfall).
  static RouteXpBreakdown calculateRouteXpBreakdown({
    required double distanceKm,
    required int curves,
    required String style,
    int streakDays = 0,
    bool? doppelXpAktiv,
  }) {
    final distanceXp = calculateDriveXp(distanceKm);
    final safeStreakDays = math.max(0, streakDays);
    // 2026-06-15 (vucko): Streak-Multiplikator JETZT echt auf die Distanz-XP
    // anwenden (vorher hart 1.0 = wirkungslos). Aufgerundet, damit der Bonus
    // nie verschluckt wird.
    final multiplier = streakMultiplierForDays(
      safeStreakDays,
      doppelXpAktiv: doppelXpAktiv,
    );
    final totalXp = (distanceXp * multiplier).round();
    return RouteXpBreakdown(
      distanceXp: distanceXp,
      curveXp: 0,
      styleBonus: 0,
      baseXp: distanceXp,
      streakDays: safeStreakDays,
      multiplier: multiplier,
      totalXp: totalXp,
    );
  }

  static int calculateDriveXp(double distanceKm) {
    return (math.max(0, distanceKm) * xpPerDrivenKm).round();
  }

  static double routeProgressRatio({
    required double plannedDistanceKm,
    required double drivenDistanceKm,
  }) {
    if (plannedDistanceKm <= 0 || drivenDistanceKm <= 0) return 0;
    return (drivenDistanceKm / plannedDistanceKm).clamp(0.0, 1.0).toDouble();
  }

  static double completionCreditProgressStep(
    double progressRatio, {
    bool completed = false,
  }) {
    final progress = progressRatio.clamp(0.0, 1.0).toDouble();
    if (completed && progress >= minRouteProgressForFullXp) return 1.0;
    return progress;
  }

  static double creditedDistanceKmForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    bool completed = false,
  }) {
    if (plannedDistanceKm <= 0) return 0;
    final progress = completionCreditProgressStep(
      progressRatio,
      completed: completed,
    );
    if (progress < minRouteProgressForXp) return 0;
    return plannedDistanceKm * progress;
  }

  static RouteXpBreakdown calculateRouteXpBreakdownForProgress({
    required double plannedDistanceKm,
    required double progressRatio,
    required int curves,
    required String style,
    bool completed = false,
    int streakDays = 0,
    bool? doppelXpAktiv,
  }) {
    final creditedDistanceKm = creditedDistanceKmForProgress(
      plannedDistanceKm: plannedDistanceKm,
      progressRatio: progressRatio,
      completed: completed,
    );
    return calculateRouteXpBreakdown(
      distanceKm: creditedDistanceKm,
      curves: creditedDistanceKm > 0 ? curves : 0,
      style: style,
      streakDays: streakDays,
      doppelXpAktiv: doppelXpAktiv,
    );
  }

  /// Basis des Multiplikators OHNE laufende Doppel-XP-Woche.
  static const double basisOhneBonus = 1.0;

  /// Basis des Multiplikators WAEHREND der Doppel-XP-Woche (Starter-Paket).
  static const double basisMitDoppelXp = 2.0;

  /// 2026-08-25 (vucko woertlich): „man soll sehen man bekommt ein badge
  /// 1000 XP + noch einen 2 fach boost der 7 Tage lang aktiv ist".
  ///
  /// GEMESSEN am 25.08. in der Produktivdatenbank, bevor diese Zeile
  /// entstanden ist: `profiles.total_xp` war bei JEDEM der 202 Profile auf die
  /// Einheit genau die Summe von `user_drive_sessions.xp_awarded` — Differenz
  /// null, ohne eine einzige Ausnahme. Die 1000 XP gab es also nirgends. Sie
  /// waren auf der Karte versprochen und wurden nie gebucht.
  ///
  /// DIE EINZIGE STELLE, an der diese Zahl steht. Die Karte liest sie hier,
  /// damit Anzeige und Gutschrift nicht auseinanderlaufen koennen.
  static const int starterPaketBonusXp = 1000;

  /// Die Gesamt-XP eines Nutzers: gefahrene XP plus der einmalige
  /// Starter-Bonus.
  ///
  /// WARUM DAS EINE REINE FUNKTION IST UND KEINE BUCHUNG:
  /// `profiles.total_xp` wird bei JEDEM Sync neu aus den Fahrten berechnet und
  /// ueberschrieben (siehe [calculateAndSync]). Ein einmal addiertes „+1000"
  /// waere beim naechsten Sync wieder weg — und ein Zaehler, der bei jedem
  /// Sync 1000 addiert, waere in einer Woche bei 100.000. Deshalb ist der
  /// Bonus ein ZUSTAND und kein Ereignis, genau wie das Startklar-Abzeichen
  /// seit dem 19.08.: Er ergibt sich aus `paketVerdient` und wird bei jeder
  /// Berechnung neu dazugerechnet. Zweimal ausgefuehrt kommt zweimal dasselbe
  /// heraus.
  ///
  /// WIRD DER BONUS MIT DEM MULTIPLIKATOR VERRECHNET? NEIN. Drei Gruende, und
  /// alle drei zaehlen:
  ///
  ///  1. Der Multiplikator gehoert zur Strecke. Er sitzt in
  ///     [calculateRouteXp] und ist in `user_drive_sessions.xp_awarded`
  ///     eingefroren, sobald eine Fahrt gebucht wird. Der Starter-Bonus ist
  ///     keine Fahrt und hat keine Strecke.
  ///  2. Die Karte verspricht „1000 XP". Mit Multiplikator waeren es je nach
  ///     Serie 2000 bis 3000 — die Anzeige waere gelogen.
  ///  3. Und der wichtigste: Die Verdopplung darf an GENAU EINER Stelle
  ///     passieren, naemlich in der Basis des Streak-Multiplikators
  ///     ([basisMitDoppelXp]). Am 19.08. hat eine zweite Stelle aus 2300 XP
  ///     einmal 2600 gemacht. Ein Bonus, der zusaetzlich verdoppelt wuerde,
  ///     waere genau dieselbe Falle mit einer anderen Zahl. Die beiden
  ///     Waechter in `test/services/streak_multiplikator_test.dart` bleiben
  ///     deshalb unangetastet gueltig.
  ///
  /// [paketVerdient] ist `StarterAufgabenService.paketVerdient`, also dieselbe
  /// Bedingung, an der auch das Startklar-Abzeichen und die Doppel-XP-Woche
  /// haengen: EINE Belohnung fuer EINE Sache.
  @visibleForTesting
  static int gesamtXpMitStarterBonus({
    required int fahrtenXp,
    required bool paketVerdient,
  }) =>
      math.max(0, fahrtenXp) + (paketVerdient ? starterPaketBonusXp : 0);

  /// Zuwachs je Tag der laufenden Serie.
  static const double proStreakTag = 0.1;

  /// 2026-08-19 (vucko): „man soll auf den 2 fachen multiplikator der eine
  /// woche geht aufbauen bspw nach einem tg 2,1 nach dem zweiten tag 2,2 usw.
  /// aber wenn man bei 2,8 oder 3,2x mulitplikator einen tag vergisst, kommt
  /// man bei der anfangswoche zurueck auf 2 solang der double xp multiplikator
  /// laeuft und wenn die 7 tage vorbei sind und man keine double xp mehr hat,
  /// ist die basis 1,00 xp also wenn man es dann vergisst kommt man ganz
  /// normal auf 1,00xp nach dem boost."
  ///
  /// Multiplikator = BASIS + Streak-Tage * 0,1, weiterhin ohne Deckel.
  /// BASIS ist 2,0, solange die Doppel-XP-Woche laeuft, danach 1,0.
  ///
  /// WICHTIG — die Verdopplung steckt jetzt HIER und nirgends sonst. Bis zum
  /// 19.08. verdoppelte `StarterAufgabenService.wendeBonusAn` zusaetzlich die
  /// fertigen XP. Beides zusammen wuerde doppelt rechnen. Nachgerechnet an
  /// Streak 3 in der Bonuswoche, 1000 XP Distanz-Basis:
  ///   alt: 1000 * 1,3 * 2 = 2600 XP
  ///   neu: 1000 * (2,0 + 0,3) = 2300 XP
  /// Der Rueckgang ist beabsichtigt; `wendeBonusAn` reicht seitdem nur noch
  /// durch.
  ///
  /// [doppelXpAktiv] ist bewusst optional: bleibt es offen, fragt die Rechnung
  /// den Starter-Dienst selbst. So bekommen auch die Aufrufer die richtige
  /// Basis, die von der Bonuswoche gar nichts wissen (Abschluss-Sheet,
  /// Startseite, Nachbuchung).
  static double streakMultiplierForDays(int streakDays, {bool? doppelXpAktiv}) {
    final bonusLaeuft =
        doppelXpAktiv ?? StarterAufgabenService.instance.doppelXpAktiv;
    final basis = bonusLaeuft ? basisMitDoppelXp : basisOhneBonus;
    return basis + math.max(0, streakDays) * proStreakTag;
  }

  /// 2026-08-19 (vucko): „wenn man eine Streak hat und einen Tag vergisst, das
  /// man die moeglichkeit hat die streak wieder zu entfachen aber wenn man die
  /// app zwei tage nicht verwendet und davor eine streak hatte, kommt man
  /// wieder auf die basisstreak ausser in der double xp woche."
  ///
  /// Schonfrist: EIN Fehltag reisst die Serie nicht. Ab diesem Fehltag laeuft
  /// sie sieben Tage; ein ZWEITER Fehltag darin beendet sie. Zwei Fehltage am
  /// Stueck sind der haeufigste Fall davon und setzen die Serie damit auf 0
  /// zurueck — der Multiplikator faellt dann auf die reine Basis (2,00x in der
  /// Bonuswoche, sonst 1,00x).
  static const int schonfristTage = 7;

  /// 2026-08-24 (Aufgabe 4.2): DER SCHALTER FUER DIE SCHONFRIST.
  ///
  /// Hier widersprechen sich zwei Aussagen von Vucko, beide woertlich:
  ///
  ///  * 23.08., Aufnahme 5 [00:32]: „wenn man halt einen Tag vergisst, dass es
  ///    dann wieder auf zwei zurueckfaellt und nicht auf eins."
  ///  * 19.08., auf genau diese Frage geantwortet: „wenn man eine Streak hat
  ///    und einen Tag vergisst, das man die moeglichkeit hat die streak wieder
  ///    zu entfachen aber wenn man die app zwei tage nicht verwendet und davor
  ///    eine streak hatte, kommt man wieder auf die basisstreak" — und auf
  ///    Nachfrage: „7 Tage ab dem Fehltag, ein zweiter beendet sie."
  ///
  /// ENTSCHEIDUNG am 24.08. (Vucko schlaeft, keine Rueckfrage moeglich): DIE
  /// SCHONFRIST BLEIBT, also `true`. Begruendung: Der Kern der Aussage vom
  /// 23.08. ist „NICHT AUF EINS" — der BODEN bei 2,0 waehrend der Bonuswoche.
  /// Der stimmt bereits und wird von
  /// `test/services/streak_multiplikator_test.dart` festgehalten. Die Zahl der
  /// erlaubten Fehltage hat er vier Tage vorher auf ausdrueckliche Nachfrage
  /// anders beantwortet, und danach ist gebaut und getestet worden.
  ///
  /// AUF `false` STELLEN heisst: schon der ERSTE Fehltag reisst die Serie, so
  /// wie es die Lesart vom 23.08. nahelegt. Es ist genau diese eine Zeile;
  /// sieben Faelle in `streak_multiplikator_test.dart` werden dann rot, und
  /// das ist richtig so — sie halten die heutige Regel fest.
  static const bool schonfristAktiv = true;

  /// Zaehlt die Serie rueckwaerts ab [ab] und beruecksichtigt die Schonfrist.
  /// Fehltage zaehlen NICHT mit, sie unterbrechen nur (oder eben nicht).
  static int _serieRueckwaerts(Set<DateTime> fahrTage, DateTime ab) {
    var tag = ab;
    var serie = 0;
    DateTime? offenerFehltag;
    // Die Schleife bricht spaetestens beim zweiten Fehltag ab; die Obergrenze
    // ist reine Absicherung gegen kaputte Datumswerte.
    for (var schritt = 0; schritt < 4000; schritt++) {
      if (fahrTage.contains(tag)) {
        serie++;
      } else if (!schonfristAktiv) {
        // Lesart vom 23.08.: schon der erste Fehltag beendet die Serie.
        break;
      } else if (offenerFehltag != null &&
          _tageDazwischen(offenerFehltag, tag) <= schonfristTage) {
        break;
      } else {
        offenerFehltag = tag;
      }
      tag = _vortag(tag);
    }
    return serie;
  }

  /// Ganze Kalendertage zwischen zwei Tagesstempeln. Ueber die UTC-Kopie
  /// gerechnet, damit eine Zeitumstellung (23- oder 25-Stunden-Tag) die
  /// Differenz nicht um einen Tag verschiebt.
  static int _tageDazwischen(DateTime spaeter, DateTime frueher) {
    return DateTime.utc(
      spaeter.year,
      spaeter.month,
      spaeter.day,
    ).difference(DateTime.utc(frueher.year, frueher.month, frueher.day)).inDays;
  }

  /// Der Vortag als Tagesstempel. Ueber den Konstruktor (Tag 0 = letzter Tag
  /// des Vormonats) statt ueber `subtract(Duration(days: 1))`, weil das an
  /// Zeitumstellungen auf 23:00 des Vortags landen wuerde.
  static DateTime _vortag(DateTime tag) {
    return DateTime(tag.year, tag.month, tag.day - 1);
  }

  /// Serie fuer die ANZEIGE (Startseite, Auswertung).
  ///
  /// Der heutige Tag ist noch nicht vorbei: ist heute noch nicht gefahren,
  /// gilt das NICHT als Fehltag, sondern die Zaehlung setzt bei gestern an.
  /// Genau das ist die „Moeglichkeit, die Streak wieder zu entfachen" — die
  /// Zahl bleibt sichtbar, bis der zweite Fehltag sie reisst.
  static int calculateDrivingStreakDays(
    Iterable<UserDriveSession> sessions, {
    DateTime? now,
  }) {
    final heute = _dateOnly((now ?? DateTime.now()).toLocal());
    final fahrTage = _driveDays(sessions);
    if (fahrTage.isEmpty) return 0;
    final start = fahrTage.contains(heute) ? heute : _vortag(heute);
    return _serieRueckwaerts(fahrTage, start);
  }

  /// Serie fuer die GUTSCHRIFT einer konkreten Fahrt. Der Fahrttag selbst
  /// zaehlt mit, das Ergebnis ist deshalb immer mindestens 1.
  static int calculateStreakDaysForRide(
    Iterable<UserDriveSession> existingSessions, {
    DateTime? rideDate,
  }) {
    final fahrtTag = _dateOnly((rideDate ?? DateTime.now()).toLocal());
    final fahrTage = _driveDays(existingSessions)..add(fahrtTag);
    return _serieRueckwaerts(fahrTage, fahrtTag);
  }

  static Future<int> getStreakDaysForNextRide({DateTime? rideDate}) async {
    // 2026-08-19: Die Basis des Multiplikators haengt an der Doppel-XP-Woche,
    // und die liegt im Geraetespeicher. `doppelXpAktiv` meldet vor dem Laden
    // immer false — eine Fahrt kurz nach dem Start haette dann mit Basis 1,0
    // statt 2,0 gerechnet. Der Fahrt-Ablauf ruft diese Methode vor jeder
    // Fahrt auf (cruise_mode_page: _prepareXpStreakContext), also wird hier
    // sichergestellt, dass der Bonus-Zustand bekannt ist. `load()` ist
    // idempotent und kehrt nach dem ersten Mal sofort zurueck.
    await StarterAufgabenService.instance.load();
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return 1;

    try {
      final data = await _db
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final sessions = (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
      return calculateStreakDaysForRide(sessions, rideDate: rideDate);
    } catch (e) {
      debugPrint('[Gamification] Streak-Abfrage fehlgeschlagen: $e');
      return 1;
    }
  }

  static Set<DateTime> _driveDays(Iterable<UserDriveSession> sessions) {
    return sessions
        .where((session) => session.distanceKm > 0)
        .map((session) => _dateOnly(session.createdAt.toLocal()))
        .toSet();
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 2026-08-16 (vucko Testfahrt T6): Kennzahlen fuer die neuen Badges — pur
  /// aus den Sessions, damit Freischaltung (calculateAndSync) und Fortschritt
  /// (badgeFortschrittFuer) garantiert dieselben Zahlen sehen.
  ///
  /// Zeitpunkte: `created_at` ist das Fahrt-ENDE; der Start wird als Ende
  /// minus Fahrdauer geschaetzt (lokale Zeit). „Vor 8 Uhr gestartet" und
  /// „nach 22 Uhr unterwegs" verlangen mindestens 5 km, damit ein 200-m-Test
  /// vor der Haustuer nicht zaehlt.
  static SessionKennzahlen sessionKennzahlen(
    Iterable<UserDriveSession> sessions,
  ) {
    var frueh = 0;
    var nacht = 0;
    var wochenende = 0;
    var kurvenjagd = 0;
    var rundkurse = 0;
    var aNachB = 0;
    final stile = <String>{};
    const vierStile = {'Kurvenjagd', 'Sport Mode', 'Abendrunde', 'Entdecker'};
    for (final s in sessions) {
      if (s.distanceKm <= 0) continue;
      final ende = s.createdAt.toLocal();
      final start = ende.subtract(Duration(seconds: s.durationSeconds));
      if (s.distanceKm >= 5) {
        if (start.hour < 8) frueh++;
        if (ende.hour >= 22 || start.hour >= 22 || ende.hour < 4) nacht++;
      }
      if (!s.completedAtEnd) continue;
      if (ende.weekday == DateTime.saturday ||
          ende.weekday == DateTime.sunday) {
        wochenende++;
      }
      final stil = s.routeStyle?.trim();
      if (stil == 'Kurvenjagd') kurvenjagd++;
      if (stil != null && vierStile.contains(stil)) stile.add(stil);
      if (s.routeType == 'ROUND_TRIP') rundkurse++;
      if (s.routeType == 'POINT_TO_POINT') aNachB++;
    }
    return SessionKennzahlen(
      fruehFahrten: frueh,
      nachtFahrten: nacht,
      wochenendFahrten: wochenende,
      besteSerieTage: laengsteFahrSerie(sessions),
      kurvenjagdFahrten: kurvenjagd,
      gefahreneStile: stile.length,
      rundkurse: rundkurse,
      aNachBFahrten: aNachB,
    );
  }

  /// Laengste Serie aufeinanderfolgender Fahrtage in der ganzen Historie.
  static int laengsteFahrSerie(Iterable<UserDriveSession> sessions) {
    final tage = _driveDays(sessions).toList()..sort();
    var beste = 0;
    var lauf = 0;
    DateTime? vorher;
    for (final t in tage) {
      if (vorher != null && t.difference(vorher).inDays == 1) {
        lauf++;
      } else {
        lauf = 1;
      }
      if (lauf > beste) beste = lauf;
      vorher = t;
    }
    return beste;
  }

  /// Zaehlt echte Kurven — dichte-unabhaengig + akkurat.
  ///
  /// 2026-08-09 (vucko): Das Verfahren liegt jetzt in [KurvenZaehler], damit
  /// ANZEIGE und ROUTEN-AUSWAHL dieselbe Zahl benutzen. Vorher entschied die
  /// Kurvenjagd-Auswahl mit einem eigenen, groben Index-Zaehler — die App zeigte
  /// also eine ehrliche Kurvenzahl an, waehlte die Route aber nach einer anderen.
  static int countCurves(List<List<double>> coords) =>
      KurvenZaehler.zaehle(coords);

  /// Async-Version: Zählt Kurven in einem separaten Isolate (Main-Thread bleibt frei).
  static Future<int> countCurvesAsync(List<List<double>> coords) {
    if (coords.length < 100) return Future.value(countCurves(coords));
    return compute(_countCurvesIsolate, coords);
  }

  static int _countCurvesIsolate(List<List<double>> coords) =>
      countCurves(coords);

  @visibleForTesting
  static DriveSessionTotals summarizeDriveSessions(
    Iterable<UserDriveSession> sessions,
  ) {
    double totalKm = 0;
    double totalSecs = 0;
    int totalXp = 0;
    int totalRoutes = 0;

    for (final session in sessions) {
      if (session.distanceKm <= 0 && session.xpAwarded <= 0) continue;
      totalRoutes++;
      totalKm += math.max(0, session.distanceKm);
      totalSecs += math.max(0, session.durationSeconds);
      totalXp += math.max(0, session.xpAwarded);
    }

    return DriveSessionTotals(
      totalRoutes: totalRoutes,
      totalDistanceKm: totalKm,
      totalSeconds: totalSecs,
      totalXp: totalXp,
    );
  }

  @visibleForTesting
  static int completedGroupRideCount(Iterable<UserDriveSession> sessions) {
    return sessions
        .where(
          (session) =>
              session.completedAtEnd &&
              (session.groupId?.trim().isNotEmpty ?? false),
        )
        .length;
  }

  @visibleForTesting
  static Map<String, dynamic> buildDriveSessionInsert({
    required String userId,
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
    int? xpAwarded,
    String? groupId,
    double? topSpeedKmh,
    List<List<double>>? trackGeometry,
    String? photoUrl,
    // 2026-08-16 (T2): Nachbuchung einer unterbrochenen Fahrt traegt das
    // FAHRT-Datum, nicht den Tag der Buchung (Wochen-Chart, Streak).
    DateTime? createdAt,
  }) {
    final safeDistanceKm = math.max(0.0, distanceKm);
    return {
      'user_id': userId,
      if (createdAt != null) 'created_at': createdAt.toUtc().toIso8601String(),
      if (routeId?.trim().isNotEmpty == true) 'route_id': routeId!.trim(),
      'distance_km': double.parse(safeDistanceKm.toStringAsFixed(3)),
      'duration_seconds': math.max(0, durationSeconds),
      'xp_awarded': math.max(0, xpAwarded ?? calculateDriveXp(safeDistanceKm)),
      'completed_at_end': completedAtEnd,
      if (routeStyle?.trim().isNotEmpty == true)
        'route_style': routeStyle!.trim(),
      if (routeType?.trim().isNotEmpty == true) 'route_type': routeType!.trim(),
      if (routeFingerprint?.trim().isNotEmpty == true)
        'route_fingerprint': routeFingerprint!.trim(),
      'source': source,
      // 2026-06-23 (vucko X3 Gruppen-Rangliste): Fahrt der Gruppe zuordnen +
      // erreichte Top-Speed mitschreiben, damit die deterministische Rangliste
      // (get_group_leaderboard) je Mitglied aggregieren kann.
      if (groupId?.trim().isNotEmpty == true) 'group_id': groupId!.trim(),
      if (topSpeedKmh != null && topSpeedKmh > 0)
        'top_speed_kmh': double.parse(topSpeedKmh.toStringAsFixed(1)),
      // 2026-06-25 (vucko Routen-Detail-Page): gefahrenen Track (für akkurate
      // Karten-Darstellung) + optionales Foto persistieren. Track auf ~400 Punkte
      // gedünnt → kompakt genug für jsonb, akkurat genug für die Skizze/Karte.
      if (trackGeometry != null && trackGeometry.length >= 2)
        'track_geometry': _downsampleTrack(trackGeometry, 400),
      if (photoUrl?.trim().isNotEmpty == true) 'photo_url': photoUrl!.trim(),
    };
  }

  static List<List<double>> _downsampleTrack(
    List<List<double>> pts,
    int maxPoints,
  ) {
    if (pts.length <= maxPoints) return pts;
    final step = pts.length / maxPoints;
    final out = <List<double>>[];
    for (var i = 0; i < maxPoints; i++) {
      out.add(pts[(i * step).floor()]);
    }
    out.add(pts.last);
    return out;
  }

  // ── Hoechsttempo-Uebergabe an das Routen-Speichern ──────────────────────
  //
  // 2026-08-28 (Fehler 8, Community-Routenkarte): Die geteilte Route zeigt
  // das Hoechsttempo der Fahrt, also braucht `routes.top_speed_kmh` beim
  // Speichern den Wert aus GENAU DIESER Fahrt. Der Abschluss-Flow in
  // cruise_mode_page ruft erst [recordDriveSession] (mit topSpeedKmh) und
  // unmittelbar danach SavedRoutesService.saveRoute. Damit saveRoute den
  // Wert bekommt, ohne dass die Fahransicht angefasst werden muss, wird er
  // hier kurz zwischengelagert.
  //
  // Absichtlich eng gefasst:
  //  * Einmal abholen leert den Speicher (kein Nachzuegler erbt ihn).
  //  * Nach [_hoechsttempoUebergabeFenster] verfaellt er, damit ein
  //    verworfener Abschluss nie in eine SPAETERE Route sickert.
  //  * Jeder Aufzeichnungs-Versuch ueberschreibt ihn, auch mit null.
  static double? _hoechsttempoLetzterFahrtKmh;
  static DateTime? _hoechsttempoLetzterFahrtZeit;
  static const Duration _hoechsttempoUebergabeFenster = Duration(minutes: 3);

  /// Holt das Hoechsttempo der zuletzt aufgezeichneten Fahrt ab und leert
  /// den Zwischenspeicher. Liefert null, wenn keine frische Fahrt vorliegt.
  static double? uebernimmHoechsttempoLetzterFahrt({DateTime? jetzt}) {
    final tempo = _hoechsttempoLetzterFahrtKmh;
    final zeit = _hoechsttempoLetzterFahrtZeit;
    _hoechsttempoLetzterFahrtKmh = null;
    _hoechsttempoLetzterFahrtZeit = null;
    if (tempo == null || zeit == null) return null;
    final alter = (jetzt ?? DateTime.now()).difference(zeit);
    if (alter > _hoechsttempoUebergabeFenster) return null;
    return tempo;
  }

  @visibleForTesting
  static void setzeHoechsttempoLetzterFahrtFuerTest(
    double? kmh, {
    DateTime? zeit,
  }) {
    _hoechsttempoLetzterFahrtKmh = kmh;
    _hoechsttempoLetzterFahrtZeit = kmh == null ? null : (zeit ?? DateTime.now());
  }

  static Future<UserDriveSession?> recordDriveSession({
    required double distanceKm,
    required int durationSeconds,
    required bool completedAtEnd,
    String? routeId,
    String? routeStyle,
    String? routeType,
    String? routeFingerprint,
    String source = 'navigation',
    int? xpAwarded,
    String? groupId,
    double? topSpeedKmh,
    List<List<double>>? trackGeometry,
    String? photoUrl,
    DateTime? createdAt,
    // 2026-08-26: Soll die Fahrt bei einem Fehlschlag in die
    // OfflineFahrtenWarteschlange? Standard ja — sie ist sonst verloren.
    //
    // `false` gehoert dorthin, wo der Aufrufer BEREITS einen eigenen,
    // dauerhaften zweiten Versuch hat (UnterbrocheneFahrtVerbuchung haelt den
    // Schnappschuss und prueft ueber `route_fingerprint` vor dem Buchen).
    // Zwei Nachtrage-Mechanismen fuer dieselbe Fahrt koennten sich sonst
    // gegenseitig ueberholen und zwei Zeilen anlegen — der Fingerabdruck-Test
    // dort kennt die Warteschlange nicht.
    bool beiFehlerNachtragen = true,
  }) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    if (distanceKm <= 0 && (xpAwarded ?? 0) <= 0) return null;

    // 2026-08-26 (Nutzerbericht „50 % der Fahrten kommen nicht an"): Die id
    // vergibt der CLIENT, nicht `gen_random_uuid()` auf dem Server. Nur so
    // kann dieselbe Fahrt nach einem Funkloch gefahrlos ein zweites Mal
    // geschickt werden: Steht sie schon, lehnt Postgres den Insert mit 23505
    // ab, statt eine zweite Zeile anzulegen (CLAUDE.md: „Eine gefahrene Fahrt
    // = GENAU EINE Zeile"). Siehe OfflineFahrtenWarteschlange.
    // Hoechsttempo fuer das direkt folgende Routen-Speichern bereitlegen.
    // VOR dem Insert, damit auch der Offline-Pfad (Insert scheitert, Fahrt
    // wandert in die Warteschlange) den Wert an saveRoute weitergibt.
    _hoechsttempoLetzterFahrtKmh = (topSpeedKmh != null && topSpeedKmh > 0)
        ? topSpeedKmh
        : null;
    _hoechsttempoLetzterFahrtZeit = DateTime.now();

    final sessionId = OfflineFahrtenWarteschlange.neueZeilenId();
    final row = buildDriveSessionInsert(
      userId: userId,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      completedAtEnd: completedAtEnd,
      routeId: routeId,
      routeStyle: routeStyle,
      routeType: routeType,
      routeFingerprint: routeFingerprint,
      source: source,
      xpAwarded: xpAwarded,
      groupId: groupId,
      topSpeedKmh: topSpeedKmh,
      trackGeometry: trackGeometry,
      photoUrl: photoUrl,
      createdAt: createdAt,
    );
    row['id'] = sessionId;

    try {
      final data = await _db
          .from('user_drive_sessions')
          .insert(row)
          .select()
          .single();
      // Neue Fahrt ist jetzt #1 → ältere Foto-Sessions aus der Top-5 räumen
      // (außer gespeicherte Routen). Fire-and-forget, blockt den Flow nicht.
      unawaited(pruneRecentRidePhotos());
      return UserDriveSession.fromJson(data);
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Session konnte nicht gespeichert werden: $e',
      );
      // 2026-08-26: Bis hierhin war die Fahrt an dieser Stelle verloren — der
      // Aufrufer raeumt gleich danach den Fahrt-Schnappschuss weg. Sie wandert
      // deshalb ZUERST in die Warteschlange und wird nachgetragen, sobald es
      // wieder Netz gibt. Das `await` ist Absicht: Erst wenn die Fahrt auf der
      // Platte liegt, darf der Fehler weiterlaufen.
      if (beiFehlerNachtragen) {
        await OfflineFahrtenWarteschlange.stelleAn(row);
      }
      rethrow;
    }
  }

  /// 2026-06-25 (vucko Routen-Detail-Page): Foto einer Fahrt nachträglich setzen
  /// oder entfernen (null). Detailseite ruft das nach dem Upload auf.
  static Future<bool> updateDriveSessionPhoto(
    String sessionId,
    String? photoUrl,
  ) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      // .select() zurückholen → ein leeres Ergebnis bedeutet 0 geänderte Zeilen
      // (z.B. RLS blockiert / falsche id), damit ein stiller Fehlschlag NICHT
      // fälschlich Erfolg meldet (das war die Wurzel des „Foto verschwindet").
      final rows = await _db
          .from('user_drive_sessions')
          .update({'photo_url': photoUrl})
          .eq('id', sessionId)
          .eq('user_id', userId)
          .select('id');
      if (rows.isEmpty) {
        debugPrint('[Gamification] Foto-Update: 0 Zeilen geändert (RLS/id?).');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('[Gamification] Foto-Update fehlgeschlagen: $e');
      return false;
    }
  }

  /// Sucht die jüngste EIGENE Drive-Session mit gegebenem route_fingerprint, die
  /// ein Foto trägt. So kann eine GESPEICHERTE Route das Foto der zugehörigen
  /// gefahrenen Fahrt anzeigen (eine Quelle = user_drive_sessions.photo_url),
  /// ohne das Foto doppelt zu speichern. RLS-konform (nur eigene Zeilen).
  static Future<String?> photoUrlForRouteFingerprint(String fingerprint) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null || fingerprint.trim().isEmpty) return null;
    try {
      final data = await _db
          .from('user_drive_sessions')
          .select('photo_url')
          .eq('user_id', userId)
          .eq('route_fingerprint', fingerprint)
          .not('photo_url', 'is', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final url = data?['photo_url'] as String?;
      return (url != null && url.trim().isNotEmpty) ? url : null;
    } catch (e) {
      debugPrint(
        '[Gamification] photoUrlForRouteFingerprint fehlgeschlagen: $e',
      );
      return null;
    }
  }

  /// 2026-06-25 (vucko #178): Fotos „zuletzt gefahrener" Fahrten, die aus der
  /// Top-[keep]-Liste herausfallen, wieder entfernen — ES SEI DENN, die Route
  /// wurde GESPEICHERT (dann lebt das Foto an der gespeicherten Route weiter).
  ///
  /// „Gespeichert" = es existiert eine eigene Route mit gleichem
  /// route_fingerprint ODER eine gespeicherte Route referenziert exakt dieselbe
  /// Foto-URL (Foto wurde beim Speichern mitkopiert). Nur in diesem Fall bleibt
  /// die Storage-Datei erhalten; sonst wird sie gelöscht (kein verwaister Müll).
  ///
  /// Läuft fire-and-forget nach dem Aufzeichnen einer neuen Fahrt — blockt also
  /// nie den Abschluss-Flow und schluckt Fehler still.
  ///
  /// 2026-09-01 (Vucko: „ganz wichtig fotos hinzufuegen kann" — nachtraeglich,
  /// zu schon gefahrenen Strecken): Die Grenze lag bei FUENF. Wer einer alten
  /// Fahrt ein Foto nachreichte, ohne die Route zu speichern, verlor es wieder,
  /// sobald fuenf neuere Foto-Fahrten dazukamen. Genau die Funktion, die er
  /// sich wuenscht, haette sich also selbst zerstoert.
  ///
  /// Gemessen an der Produktionsdatenbank am 01.09.: Es gibt DREI Fahrten mit
  /// Foto, von einem einzigen Nutzer, und der ganze Bilderspeicher ist 4,9 MB
  /// gross. Die Grenze raeumte also ein Problem weg, das es nicht gab.
  ///
  /// Fuenfzig ist bewusst grosszuegig und trotzdem eine Grenze: Bei rund einem
  /// halben Megabyte je Bild sind das etwa 25 MB je Nutzer. Sollte der
  /// Bilderspeicher spaeter wirklich wachsen, gehoert hier keine kleinere Zahl
  /// hin, sondern ein ehrlicher Weg — den Nutzer fragen, statt ihm still seine
  /// Erinnerung zu loeschen.
  static Future<void> pruneRecentRidePhotos({int keep = 50}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // Alle eigenen Sessions MIT Foto, neueste zuerst.
      final withPhoto = await _db
          .from('user_drive_sessions')
          .select('id, photo_url, route_fingerprint')
          .eq('user_id', userId)
          .not('photo_url', 'is', null)
          .order('created_at', ascending: false);
      final rows = (withPhoto as List).cast<Map<String, dynamic>>();
      if (rows.length <= keep) return;

      // Schutzschild: Fingerprints + Foto-URLs der eigenen GESPEICHERTEN Routen.
      final savedRows = await _db
          .from('routes')
          .select('route_fingerprint, photo_url')
          .eq('user_id', userId);
      final savedFingerprints = <String>{};
      final savedPhotoUrls = <String>{};
      for (final r in (savedRows as List).cast<Map<String, dynamic>>()) {
        final fp = (r['route_fingerprint'] as String?)?.trim();
        if (fp != null && fp.isNotEmpty) savedFingerprints.add(fp);
        final pu = (r['photo_url'] as String?)?.trim();
        if (pu != null && pu.isNotEmpty) savedPhotoUrls.add(pu);
      }

      // Alles JENSEITS der Top-[keep]: Foto entfernen, wenn nicht geschützt.
      for (final row in rows.skip(keep)) {
        final id = row['id'] as String?;
        final url = (row['photo_url'] as String?)?.trim();
        final fp = (row['route_fingerprint'] as String?)?.trim();
        if (id == null || url == null || url.isEmpty) continue;

        final isSaved =
            (fp != null && fp.isNotEmpty && savedFingerprints.contains(fp)) ||
            savedPhotoUrls.contains(url);
        if (isSaved) continue; // Foto bleibt — Route ist gespeichert.

        // Foto-Spalte der Session leeren …
        await _db
            .from('user_drive_sessions')
            .update({'photo_url': null})
            .eq('id', id)
            .eq('user_id', userId);
        // … und die Datei löschen, sofern KEINE gespeicherte Route sie nutzt.
        if (!savedPhotoUrls.contains(url)) {
          await SocialService.deleteUserAsset(
            bucket: 'ride-photos',
            publicUrl: url,
          );
        }
      }
    } catch (e) {
      debugPrint('[Gamification] pruneRecentRidePhotos fehlgeschlagen: $e');
    }
  }

  static Future<List<UserDriveSession>> getDriveSessions({int? limit}) async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      var query = _db
          .from('user_drive_sessions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      if (limit != null) {
        query = query.limit(limit);
      }
      final data = await query;
      return (data as List)
          .map((row) => UserDriveSession.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
        '[Gamification] Drive-Sessions konnten nicht geladen werden: $e',
      );
      return const [];
    }
  }

  /// Berechnet Level und Badges basierend auf immutable Drive-Sessions.
  /// Speichert den Fortschritt in der `profiles`-Tabelle.
  static Future<GamificationResult> calculateAndSync() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    // 1. Alle Drive-Sessions laden. Gespeicherte Routen sind nicht XP-Quelle.
    List<UserDriveSession> sessions;
    try {
      sessions = await getDriveSessions();
    } catch (e) {
      debugPrint('[Gamification] Drive-Session-Abfrage fehlgeschlagen: $e');
      return GamificationResult(
        level: UserLevel.fromXp(0),
        earnedBadgeIds: const [],
        newBadgeIds: const [],
        totalRoutes: 0,
        totalDistanceKm: 0,
        totalHours: 0,
        totalXp: 0,
      );
    }

    // 2. Statistiken berechnen
    final totals = summarizeDriveSessions(sessions);
    final totalKm = totals.totalDistanceKm;
    final totalSecs = totals.totalSeconds;
    // 2026-08-25: Hier stand `final totalXp = totals.totalXp;`. Die Summe der
    // Fahrten ist seit heute nicht mehr die ganze Wahrheit — der einmalige
    // Starter-Bonus kommt dazu. Er kann aber erst weiter unten feststehen,
    // weil er am Stand der Starter-Aufgaben haengt, und der wird erst nach den
    // Badge-Kennzahlen abgeglichen. Deshalb der Zwischenname.
    final fahrtenXp = totals.totalXp;
    final totalRoutes = totals.totalRoutes;
    final completedSessions = sessions
        .where((session) => session.completedAtEnd)
        .toList();
    final completedGroupRides = completedGroupRideCount(sessions);

    // 3. Level aus XP berechnen — vorlaeufig, ohne den Starter-Bonus.
    //
    // Die Reihenfolge ist ein echter Ringschluss und laesst sich nicht
    // aufloesen: Level → Badge-Kennzahlen → erfuellte Abzeichen → die Aufgabe
    // „drei Abzeichen sammeln" → `paketVerdient` → Starter-Bonus → Level. Er
    // wird an der duennsten Stelle aufgetrennt: die Badge-Schwellen rechnen
    // mit dem Level OHNE Bonus, und sobald der Bonus feststeht, wird das Level
    // neu bestimmt und die Level-Abzeichen werden noch einmal geprueft (siehe
    // unten). Was dabei trotzdem eine Runde spaeter faellt, faellt beim
    // naechsten Sync — die Vergabe haengt ueberall am ZUSTAND, nie an einem
    // Ereignis.
    final levelOhneBonus = UserLevel.fromXp(fahrtenXp.toDouble());

    // 2026-08-19 (vucko, Starter-Aufgabe „der erste post"): Der Zaehler lief
    // hier bisher nur ueber Posts MIT geteilter Route (badge_09). Fuer die
    // Aufgabe zaehlt jeder Post, auch der reine Foto-Post. Beide Zahlen
    // kommen jetzt aus derselben, unveraenderten Abfrage — kein zweiter
    // Netzweg.
    final gruppenZaehler = _countCreatedGroups(userId);
    final postZaehler = _countPosts(userId);
    final gespeicherteZaehler = _countSavedRouteReferences(userId);
    // 2026-08-24 (Aufgabe 4.5 und 10a): zwei weitere Zahlen, beide parallel
    // zu den bestehenden — kein zusaetzlicher Wartetakt.
    final fahrzeugZaehler = _countVehicles(userId);
    final gruendungZaehler = _hatCommunityGegruendet();
    // 2026-08-24 (Aufgabe 4): die zwoelfte Starter-Aufgabe. Ebenfalls parallel.
    //
    // 2026-08-24 (badge_59 … badge_70): Aus dem Ja/Nein „hat je einen Hashtag
    // benutzt" ist eine ZAHL geworden — die Familie Hashtags hat die Stufen
    // 1/5/20, ein Ja/Nein reicht nur fuer die erste. Dieselbe RPC liefert die
    // Meldungs-Zahl gleich mit, deshalb bleibt es bei EINEM zusaetzlichen
    // Netzweg, und der laeuft neben den anderen. Warum serverseitig, steht in
    // Migration 20260824180000: die Sichtbarkeitsregel von `road_incidents`
    // blendet abgelaufene Meldungen aus (gemessen: 7 abgesetzt, 2 sichtbar),
    // und Beitraege mit Raute sind `count(distinct post_id)`, nicht die Anzahl
    // der Rauten.
    final kennzahlenZaehler = _ladeBadgeKennzahlen();
    final createdGroupCount = await gruppenZaehler;
    final postZahlen = await postZaehler;
    final savedRouteReferenceCount = await gespeicherteZaehler;
    final fahrzeugAnzahl = await fahrzeugZaehler;
    final communityGegruendet = await gruendungZaehler;
    final badgeKennzahlen = await kennzahlenZaehler;
    final hashtagBeitragsAnzahl = badgeKennzahlen.hashtagBeitraege;
    final meldungsAnzahl = badgeKennzahlen.meldungen;
    final hashtagBenutzt = hashtagBeitragsAnzahl > 0;
    final routePostCount = postZahlen.mitRoute;

    // 4. Badges prüfen
    //
    // 2026-08-18 (Aufgabe 4.2): Hier standen rund dreissig einzelne
    // `if`-Zeilen, und dieselben Schwellen noch einmal in
    // `badgeFortschrittFuer`. Beide Listen konnten auseinanderlaufen — genau
    // davor warnte badge.dart. Jetzt liest BEIDES dieselbe Datentabelle
    // [badgeFamilien]; eine neue Stufe ist eine Zeile Daten, keine Zeile Code.
    final kz = sessionKennzahlen(sessions);
    final longestRideKm = completedSessions.isEmpty
        ? 0.0
        : completedSessions
              .map((s) => s.distanceKm)
              .reduce((a, b) => a > b ? a : b);
    final metriken = badgeMetriken(
      level: levelOhneBonus.level,
      totalKm: totalKm,
      totalHours: totalSecs / 3600,
      completedRides: completedSessions.length,
      completedGroupRides: completedGroupRides,
      routePosts: routePostCount,
      createdGroups: createdGroupCount,
      savedRoutes: savedRouteReferenceCount,
      longestRideKm: longestRideKm,
      fruehFahrten: kz.fruehFahrten,
      nachtFahrten: kz.nachtFahrten,
      wochenendFahrten: kz.wochenendFahrten,
      besteSerieTage: kz.besteSerieTage,
      kurvenjagdFahrten: kz.kurvenjagdFahrten,
      gefahreneStile: kz.gefahreneStile,
      rundkurse: kz.rundkurse,
      aNachBFahrten: kz.aNachBFahrten,
      // 2026-08-24: Diese vier Zeilen fehlten, seit die Familien Garage,
      // Beitraege, Hashtags und Meldungen angelegt wurden. Ohne sie blieb
      // jede der zwoelf Stufen auf 0 stehen — die Abzeichen standen dauerhaft
      // gesperrt in der Sammlung. Zwei der Zahlen lagen hier schon vor
      // (`fahrzeugAnzahl` fuer die Garage-Aufgabe, `postZahlen.gesamt` fuer
      // „der erste post"); sie werden bewusst wiederverwendet statt neu
      // geholt.
      fahrzeuge: fahrzeugAnzahl,
      beitraege: postZahlen.gesamt,
      hashtagBeitraege: hashtagBeitragsAnzahl,
      meldungen: meldungsAnzahl,
    );
    final currentlyQualifiedBadges = erfuellteBadgeIds(metriken);

    // 2026-08-14 (vucko Tutorial-Badge): „Gründungszeit" (badge_15) bekommt
    // JEDER registrierte Nutzer — bewusst OHNE Bedingung. Bestandsnutzer
    // erhalten es dadurch beim ersten Sync nach dem Update automatisch als
    // newBadgeId → das Unlock-Popup (Verleih-Animation) feuert von selbst.
    currentlyQualifiedBadges.add(Badge.membershipBadgeId);

    // 2026-08-19 (vucko): „das startklar abzeichen hat keiner."
    //
    // GEMESSEN am 19.08.: badge_16 hatte 0 von 152 Profilen — auch die beiden
    // Nutzer nicht, deren Doppel-XP-Woche nachweislich lief, die also alle
    // Starter-Aufgaben erledigt hatten. Ursache: Die Vergabe haing allein am
    // einmaligen Ereignis `paketFrischVerdient` in starter_paket_karte.dart,
    // und genau in diesem Moment verwarf die Datenbank-Whitelist noch alles ab
    // badge_15 (repariert erst am 18.08. mit 20260818230000). Ein Ereignis,
    // das nur einmal feuert, kann man nicht nachholen — hier stand nichts, was
    // badge_16 nachtraegt.
    //
    // JETZT aus dem ZUSTAND: Der Abgleich zieht den Stand vom Profil (falls
    // das Geraet gewechselt hat), leitet die drei Fahr- und Social-Aufgaben
    // aus denselben Kennzahlen ab, die oben schon fuer die Badges berechnet
    // wurden, und `paketVerdient` sagt danach, ob das Abzeichen zusteht. Diese
    // Pruefung laeuft bei JEDEM Sync, also kommt das Abzeichen auch Wochen
    // spaeter noch an.
    // 2026-08-24 (Aufgabe 10a, vucko woertlich): „dass community ein enzelnes
    // badge bekommen [...] aber nur eins das heisst Gruende eine Community".
    //
    // Die Bedingung kommt aus der Datenbank (RPC `meine_community_gruendung`,
    // Migration 20260824103000), nicht aus einem Zaehler hier: Der GRUENDER
    // ist dort eine eigene, schreib-einmalige Spalte `communities.founder_id`.
    // Weder `communities.owner_id` (wird beim Verlassen umgesetzt) noch
    // `community_members.role = 'owner'` (die Admin-Rolle, gemessen 7 Zeilen
    // auf 6 Communities) taugen dafuer — ueber beide bekaemen mehrere Leute je
    // Community dasselbe Abzeichen.
    if (communityGegruendet) {
      currentlyQualifiedBadges.add(Badge.communityGruenderBadgeId);
    }

    final starter = StarterAufgabenService.instance;
    await starter.synchronisiereMitProfil();
    // 2026-08-24: Die Anzahl der Abzeichen fuer die Aufgabe „die ersten drei
    // Abzeichen sammeln" wird GENAU HIER genommen — vor der Vergabe von
    // badge_16. Das Startklar-Abzeichen ist die Belohnung dieser Liste; zaehlte
    // es mit, haenge die Aufgabe an ihrem eigenen Ergebnis.
    final abzeichenOhneStartklar = normalizeBadgeIds(
      currentlyQualifiedBadges,
    ).length;
    await starter.synchronisiereAusKennzahlen(
      posts: postZahlen.gesamt,
      abgeschlosseneFahrten: completedSessions.length,
      abgeschlosseneGruppenfahrten: completedGroupRides,
      erstellteGruppen: createdGroupCount,
      fahrzeuge: fahrzeugAnzahl,
      abzeichen: abzeichenOhneStartklar,
      gesamtKm: totalKm,
      hashtagBenutzt: hashtagBenutzt,
      gespeicherteRouten: savedRouteReferenceCount,
    );
    if (starter.paketVerdient) {
      currentlyQualifiedBadges.add(Badge.starterBadgeId);
    }

    // 2026-08-25 (vucko): badge_58 verlangt jetzt ALLE ZWOELF Starter-Aufgaben.
    //
    // Hier stand bis heute `starter.erledigt('tutorial')` — das Abzeichen fiel
    // also, sobald die Fuehrung mit den Leuchtkreisen durchgeklickt war.
    // GEMESSEN am 25.08. in der Produktivdatenbank: genau EIN Profil von 199
    // traegt badge_58, und dieses Profil hatte zehn von zwoelf Aufgaben
    // erledigt, zwei offen. Vucko hat das Abzeichen also fuer die Tour
    // bekommen und nicht fuer die Liste. Sein Satz dazu: „ich habe jetzt nur
    // das tutorial bekommen und nicht das onboarding und es soll passend sein
    // dafuer".
    //
    // NEUE ABGRENZUNG, damit die zwei Abzeichen verschiedene Dinge messen:
    //   badge_16 „Startklar"   = ACHT von zwoelf (`paketVerdient`, oben).
    //                            Die Boost-Schwelle, sie bleibt erreichbar.
    //   badge_58               = ZWOELF von zwoelf. Woertlich „alle Funktionen
    //                            einmal durchgetestet".
    //
    // WARUM ERST HIER, NACH `abzeichenOhneStartklar`: Das Abzeichen zaehlt
    // NICHT fuer die Aufgabe „die ersten drei Abzeichen sammeln" mit — aus
    // demselben Grund wie badge_16. Beide sind Belohnungen dieser Liste; wer
    // sie mitzaehlt, haengt die Aufgabe an ihr eigenes Ergebnis. Seit die
    // Bedingung ALLE zwoelf Aufgaben sind (darunter „drei Abzeichen"), waere
    // ein Mitzaehlen sogar ein echter Ringschluss und kein blosser
    // Schoenheitsfehler.
    //
    // Das Tutorial bleibt Teil der Bedingung, nur eben als eine von zwoelf
    // Zeilen: die Aufgabe „tutorial" wird weiterhin nur beim ECHTEN Abschluss
    // gesetzt (app_tutorial_overlay.dart, _complete), nicht beim
    // Ueberspringen.
    if (starter.alleAufgabenErledigt) {
      currentlyQualifiedBadges.add(alleAufgabenBadgeId);
    }

    // 4b. Der Starter-Bonus von 1000 XP.
    //
    // 2026-08-25 (vucko woertlich): „man soll sehen man bekommt ein badge
    // 1000 XP + noch einen 2 fach boost der 7 Tage lang aktiv ist."
    //
    // GEMESSEN am 25.08., bevor diese Zeilen entstanden sind: `total_xp` war
    // bei allen 202 Profilen exakt die Summe der `xp_awarded` ihrer Fahrten,
    // Differenz null. Die 1000 XP standen auf der Karte und wurden nie
    // gebucht.
    //
    // Sie haengen an DERSELBEN Bedingung wie das Startklar-Abzeichen zwei
    // Zeilen weiter oben (`starter.paketVerdient`) und wie die
    // Doppel-XP-Woche: ein Abzeichen, 1000 XP und sieben Tage doppelte XP
    // sind EINE Belohnung fuer EINE Sache und fallen gemeinsam.
    //
    // Warum als Zustand und nicht als Buchung, und warum OHNE Multiplikator:
    // siehe [gesamtXpMitStarterBonus].
    final totalXp = gesamtXpMitStarterBonus(
      fahrtenXp: fahrtenXp,
      paketVerdient: starter.paketVerdient,
    );
    final level = UserLevel.fromXp(totalXp.toDouble());
    if (level.level != levelOhneBonus.level) {
      // Der Bonus hat das Level gehoben. Ohne diese Zeilen bliebe ein
      // Level-Abzeichen bis zum naechsten Sync gesperrt, obwohl das Profil
      // die Schwelle schon traegt.
      currentlyQualifiedBadges.addAll(
        erfuellteBadgeIds({
          ...metriken,
          BadgeMetrik.level: level.level.toDouble(),
        }),
      );
    }

    // 5. Bisherige Badges laden und neue bestimmen
    List<String> previousBadges = [];
    try {
      final profile = await _db
          .from('profiles')
          .select('badges')
          .eq('id', userId)
          .maybeSingle();

      final rawBadges = profile?['badges'];
      if (rawBadges is Iterable) {
        previousBadges = normalizeBadgeIds(rawBadges);
      }
    } catch (e) {
      debugPrint('[Gamification] Badges-Abfrage fehlgeschlagen: $e');
    }

    final qualifiedBadges = normalizeBadgeIds(currentlyQualifiedBadges);
    final unlockedBadges = mergeBadgeIds(previousBadges, qualifiedBadges);
    final newBadges = newlyQualifiedBadgeIds(previousBadges, qualifiedBadges);

    // 6. Fortschritt im Backend speichern
    //
    // 2026-08-18 (Aufgabe 4.1): Das Ergebnis wird ZURUECKGELESEN. Grund war
    // der Dauer-Popup-Fehler: Die Datenbank hatte eine hartkodierte
    // Badge-Whitelist, die alles ab badge_15 stillschweigend verwarf. Der
    // Client hielt das Badge fuer vergeben, beim naechsten Sync fehlte es
    // wieder im Profil, galt erneut als „neu" — und das Verleih-Popup ging
    // wieder auf. Gemessen am 18.08.: 0 von 151 Profilen hatten badge_15,
    // obwohl es bei jedem Sync bedingungslos vergeben wurde.
    //
    // Die Whitelist ist repariert (Migration 20260818230000). Diese Pruefung
    // ist die zweite Sicherung: Kommt ein Badge NICHT in der Datenbank an,
    // wird es auch nicht als neu gefeiert. Ein kuenftiger Schreibfehler kann
    // dann still ausfallen, aber nie wieder spammen.
    var bestaetigteBadges = unlockedBadges;
    try {
      await _db
          .from('profiles')
          .update({
            'level': level.level,
            'total_km': totalKm,
            'total_xp': totalXp,
            'total_routes': totalRoutes,
            'badges': unlockedBadges,
          })
          .eq('id', userId);

      final nachher = await _db
          .from('profiles')
          .select('badges')
          .eq('id', userId)
          .maybeSingle();
      final rohNachher = nachher?['badges'];
      if (rohNachher is Iterable) {
        bestaetigteBadges = normalizeBadgeIds(rohNachher);
        final verschluckt = unlockedBadges
            .where((b) => !bestaetigteBadges.contains(b))
            .toList();
        if (verschluckt.isNotEmpty) {
          debugPrint(
            '[Gamification] WARNUNG: Diese Badges kamen nicht in der Datenbank '
            'an und werden NICHT als neu gemeldet: ${verschluckt.join(', ')}',
          );
        }
      }
    } catch (e) {
      debugPrint('[Gamification] Profil-Update fehlgeschlagen: $e');
    }

    // Nur feiern, was wirklich gespeichert wurde.
    newBadges.removeWhere((b) => !bestaetigteBadges.contains(b));

    // 2026-08-26 (vucko, Aufgabe 7): Vormerken, BEVOR das Ergebnis
    // zurueckgeht. Zeigt der Aufrufer die Feier (vier von zwoelf tun das),
    // quittiert er sie gleich danach. Zeigt er sie nicht, bleibt sie stehen
    // und der naechste passende Bildschirm holt sie nach. Vorher war ein
    // Abzeichen, das bei einem stillen Abgleich faellig wurde, fuer immer
    // stumm vergeben.
    await OffeneAuszeichnungen.merken(newBadges);

    return GamificationResult(
      level: level,
      earnedBadgeIds: bestaetigteBadges,
      newBadgeIds: newBadges,
      totalRoutes: totalRoutes,
      totalDistanceKm: totalKm,
      totalHours: totalSecs / 3600,
      totalXp: totalXp,
      completedRides: completedSessions.length,
      completedGroupRides: completedGroupRides,
      routePosts: routePostCount,
      createdGroups: createdGroupCount,
      savedRoutes: savedRouteReferenceCount,
      longestRideKm: longestRideKm,
      fruehFahrten: kz.fruehFahrten,
      nachtFahrten: kz.nachtFahrten,
      wochenendFahrten: kz.wochenendFahrten,
      besteSerieTage: kz.besteSerieTage,
      kurvenjagdFahrten: kz.kurvenjagdFahrten,
      gefahreneStile: kz.gefahreneStile,
      rundkurse: kz.rundkurse,
      aNachBFahrten: kz.aNachBFahrten,
      fahrzeuge: fahrzeugAnzahl,
      beitraege: postZahlen.gesamt,
      hashtagBeitraege: hashtagBeitragsAnzahl,
      meldungen: meldungsAnzahl,
    );
  }

  static Future<int> _countCreatedGroups(String userId) async {
    try {
      // 2026-08-18 (Aufgabe 4.2): Hier stand `.limit(2)`. Das reichte, solange
      // nur badge_07 („eine Gruppe") daran hing. Mit den Stufen 3 und 10
      // (badge_35, badge_38) haette der Zaehler bei 2 festgeklebt: die Stufen
      // waeren NIE freigeschaltet worden und der Fortschritt haette ewig
      // „2 von 10 Gruppen" gezeigt. Die Grenze liegt jetzt ueber der hoechsten
      // Schwelle.
      final rows = await _db
          .from('groups')
          .select('id')
          .eq('created_by', userId)
          .limit(64);
      return (rows as List).length;
    } catch (e) {
      debugPrint('[Gamification] Gruppen-Zähler fehlgeschlagen: $e');
      return 0;
    }
  }

  /// 2026-08-24 (Aufgabe 4.5, vucko): „Auto in die Garage hinzufuegen".
  ///
  /// GEMESSEN am 24.08.: 60 von 183 Profilen haben mindestens ein Fahrzeug in
  /// `profile_vehicles`.
  ///
  /// 2026-08-24 (badge_59…61 „Garage"): Die Zahl ist jetzt auch eine
  /// Badge-Schwelle (1/3/5), nicht mehr nur ein Ja/Nein fuer die
  /// Starter-Aufgabe. Die Grenze 8 liegt ueber der hoechsten Schwelle — dieselbe
  /// Regel wie beim Gruppen-Zaehler, wo `.limit(2)` genau deshalb einmal die
  /// Stufen 3 und 10 blockiert hat. Wer eine Stufe ueber 8 anlegt, muss sie
  /// mit anheben.
  static Future<int> _countVehicles(String userId) async {
    try {
      final rows = await _db
          .from('profile_vehicles')
          .select('id')
          .eq('user_id', userId)
          .limit(8);
      return (rows as List).length;
    } catch (e) {
      // Faellt still aus, wenn die Tabelle fehlt (Altbestand ohne Migration).
      debugPrint('[Gamification] Fahrzeug-Zähler fehlgeschlagen: $e');
      return 0;
    }
  }

  /// 2026-08-24 (Aufgabe 10a): Hat der Nutzer je eine Community GEGRUENDET?
  ///
  /// Bewusst die RPC und keine eigene Abfrage auf `communities`. Zwei Gruende,
  /// beide stehen ausfuehrlich in Migration 20260824103000:
  ///  * Der Gruender ist `founder_id`, nicht `owner_id` und nicht die Rolle
  ///    `owner` in `community_members`.
  ///  * Die Sichtbarkeitsregel `communities_visible_public_or_member` zeigt
  ///    eine private Community nur Mitgliedern. Wer seine eigene private
  ///    Community gegruendet und spaeter verlassen hat, saehe sie per SELECT
  ///    nicht mehr und verloere das Abzeichen wieder. Die RPC laeuft deshalb
  ///    als SECURITY DEFINER und liest ausschliesslich Zeilen mit
  ///    `founder_id = auth.uid()`.
  static Future<bool> _hatCommunityGegruendet() async {
    try {
      final antwort = await _db.rpc('meine_community_gruendung');
      if (antwort is Map) return antwort['gegruendet'] == true;
      return false;
    } catch (e) {
      debugPrint('[Gamification] Community-Gründung-Abfrage fehlgeschlagen: $e');
      return false;
    }
  }

  /// Posts des Nutzers: [gesamt] fuer die Starter-Aufgabe „der erste post",
  /// [mitRoute] fuer die Routen-Badges. 2026-08-19 aus `_countRoutePosts`
  /// hervorgegangen; die Abfrage ist dieselbe geblieben.
  static Future<({int gesamt, int mitRoute})> _countPosts(String userId) async {
    try {
      final rows = await _db
          .from('posts')
          .select('shared_route_id')
          .eq('user_id', userId);
      final liste = (rows as List).whereType<Map>().toList();
      return (
        gesamt: liste.length,
        mitRoute: liste.where((row) => row['shared_route_id'] != null).length,
      );
    } catch (e) {
      debugPrint('[Gamification] Post-Zähler fehlgeschlagen: $e');
      return (gesamt: 0, mitRoute: 0);
    }
  }

  /// 2026-08-24: Beitraege mit Hashtag und abgesetzte Meldungen — die beiden
  /// Zahlen hinter den Familien Hashtags (badge_65…67) und Meldungen
  /// (badge_68…70). Fuer die Starter-Aufgabe „benutze einen hashtag" (Aufgabe 4
  /// vom selben Tag) genuegt davon `hashtagBeitraege > 0`.
  ///
  /// EINE RPC statt zweier Tabellen-Abfragen, und zwar aus drei Gruenden
  /// (ausfuehrlich in Migration 20260824180000):
  ///  * `road_incidents` zeigt per Sichtbarkeitsregel nur Meldungen, die
  ///    gerade noch gueltig sind. GEMESSEN am 24.08.: 7 abgesetzt, 2 sichtbar.
  ///    Ueber den Client waeren zwanzig Meldungen praktisch nie zu erreichen.
  ///  * Die Hashtag-Familie zaehlt BEITRAEGE mit Raute. `post_hashtags` hat
  ///    eine Zeile je Raute — ein Beitrag mit fuenf Rauten haette Stufe 5
  ///    sofort freigeschaltet. `count(distinct post_id)` gehoert in die
  ///    Datenbank.
  ///  * `calculateAndSync` laeuft bei jedem Start der Startseite. Ein Aufruf
  ///    statt zwei ist ein Wartetakt statt zwei.
  static Future<({int hashtagBeitraege, int meldungen})>
  _ladeBadgeKennzahlen() async {
    try {
      final antwort = await _db.rpc('meine_badge_kennzahlen');
      return badgeKennzahlenAusAntwort(antwort);
    } catch (e) {
      // Faellt still aus, wenn die RPC fehlt (Altbestand ohne Migration).
      debugPrint('[Gamification] Badge-Kennzahlen fehlgeschlagen: $e');
      return (hashtagBeitraege: 0, meldungen: 0);
    }
  }

  static Future<int> _countSavedRouteReferences(String userId) async {
    final routeIds = <String>{};

    try {
      final rows = await _db
          .from('routes')
          .select('id, source_route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final sourceRouteId = row['source_route_id'] as String?;
        final routeId = sourceRouteId?.trim().isNotEmpty == true
            ? sourceRouteId!.trim()
            : row['id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint(
        '[Gamification] Gespeicherte Routen-Zähler fehlgeschlagen: $e',
      );
    }

    try {
      final rows = await _db
          .from('route_bookmarks')
          .select('route_id')
          .eq('user_id', userId);
      for (final row in (rows as List).whereType<Map>()) {
        final routeId = row['route_id'] as String?;
        if (routeId != null && routeId.trim().isNotEmpty) {
          routeIds.add(routeId.trim());
        }
      }
    } catch (e) {
      debugPrint('[Gamification] Routen-Speicher-Zähler fehlgeschlagen: $e');
    }

    return routeIds.length;
  }
}

/// 2026-08-16 (T6): Kennzahlen aus den Fahrt-Sessions fuer die Badges 23–36.
class SessionKennzahlen {
  const SessionKennzahlen({
    required this.fruehFahrten,
    required this.nachtFahrten,
    required this.wochenendFahrten,
    required this.besteSerieTage,
    required this.kurvenjagdFahrten,
    required this.gefahreneStile,
    required this.rundkurse,
    required this.aNachBFahrten,
  });
  final int fruehFahrten;
  final int nachtFahrten;
  final int wochenendFahrten;
  final int besteSerieTage;
  final int kurvenjagdFahrten;
  final int gefahreneStile;
  final int rundkurse;
  final int aNachBFahrten;
}
