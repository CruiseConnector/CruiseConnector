import 'package:cruise_connect/data/services/active_ride_snapshot_service.dart';
import 'package:cruise_connect/data/services/gamification_service.dart';
import 'package:cruise_connect/data/services/starter_aufgaben_service.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 2026-08-16 (vucko Testfahrt, Aufgabe 2): „Was davor abgebrochen worden
/// ist, wird von der App im Hintergrund erfasst — nichts geht verloren."
///
/// Eine unterbrochene Fahrt (App vom System beendet) lebt als Schnappschuss
/// weiter. Zwei Wege:
///  * FORTSETZEN → die Fahrt laeuft als DIESELBE Fahrt weiter (Kilometer/Zeit
///    werden in den Rekorder eingespielt, cruise_mode_page P2) und wird am
///    Ende als EINE Session gebucht. Keine Doppelbuchung, eine Fahrt in der
///    Statistik, Badges (z. B. 100-km-Fahrt) rechnen mit der ganzen Fahrt.
///  * NICHT fortsetzen (Verwerfen, abgelaufen nach 48 h, neue Fahrt
///    ueberschreibt den Schnappschuss) → der gefahrene Teil wird HIER als
///    Drive-Session gebucht — nach denselben Regeln wie ein vorzeitiges
///    Beenden: erst ab [GamificationService.minRouteProgressForXp] der
///    geplanten Strecke, XP mit Streak-Multiplikator und Starter-Bonus,
///    Fahrzeit auf Plausibilitaet geprueft.
///
/// Sicherungen:
///  * Nur der Fahrer selbst (user_id im Schnappschuss) — nach Kontowechsel
///    bekommt der andere nichts gutgeschrieben.
///  * Idempotent ueber `route_fingerprint = 'unterbrochen:<ride_id>'`: Geht
///    die Antwort des Inserts verloren, findet der naechste Versuch die Zeile
///    und bucht nicht erneut.
///  * Datum der Session = Fahrtdatum (created_at), nicht der Tag der Buchung.
class UnterbrocheneFahrtVerbuchung {
  UnterbrocheneFahrtVerbuchung._();

  static const double _mindestKm = 0.05;
  static const double _minPlausibelKmh = 5.0;
  static const double _maxPlausibelKmh = 180.0;

  /// Reiner Rechenkern, testbar: Was ist fuer diesen Schnappschuss zu buchen?
  /// null = nichts (zu wenig gefahren, unter der XP-Schwelle).
  static VerbuchungsPosten? posten(ActiveRideSnapshot s, {required int streakTage}) {
    if (s.drivenKm < _mindestKm) return null;
    if (s.fortschritt < GamificationService.minRouteProgressForXp) return null;
    return _rechne(s, streakTage);
  }

  /// 2026-08-18 (vucko, Aufgabe 2.3): „Nach komplettem Schliessen und
  /// Wiederoeffnen sind die vorher gesammelten XP und Fahrtdaten schon
  /// eingetragen."
  ///
  /// Wortwoertlich umgesetzt hiesse das: den abgebrochenen Teil als eigene
  /// Zeile buchen und den Rest spaeter noch einmal. Das verbietet CLAUDE.md:
  /// „Eine gefahrene Fahrt = GENAU EINE Zeile" in `user_drive_sessions` —
  /// sonst zaehlen Badges wie „Anzahl Fahrten" doppelt, und die 100-km-Fahrt
  /// zerfaellt in zwei halbe.
  ///
  /// Deshalb der ZWISCHENSTAND: derselbe Rechenkern, aber nur zum ANZEIGEN
  /// beim Fortsetzen. Gebucht wird weiterhin genau einmal, am Ende der
  /// fortgesetzten Fahrt — dann aber inklusive dieses Teils, weil Kilometer,
  /// Fahrzeit und Hoechstgeschwindigkeit in den Rekorder eingespielt werden.
  ///
  /// Unterschied zu [posten]: KEINE Mindestfortschritts-Schwelle. Wer 5 % der
  /// Strecke gefahren hat, bekommt dafuer zwar keine eigene Fahrt gebucht,
  /// aber seine 3 km sind trotzdem gefahren und muessen sichtbar bleiben.
  static VerbuchungsPosten zwischenstand(
    ActiveRideSnapshot s, {
    required int streakTage,
  }) => _rechne(s, streakTage);

  static VerbuchungsPosten _rechne(ActiveRideSnapshot s, int streakTage) {
    final xp = GamificationService.calculateRouteXpBreakdown(
      distanceKm: s.drivenKm,
      curves: 0,
      style: s.style,
      streakDays: streakTage,
    ).totalXp;
    return VerbuchungsPosten(
      km: s.drivenKm,
      sekunden: plausibleSekunden(s),
      xp: xp,
    );
  }

  /// Fahrzeit wie beim normalen Abschluss auf 5–180 km/h Schnitt geprueft:
  /// Wer ohne Pause-Tipp eine Stunde stand, bekommt sie nicht als Fahrzeit.
  /// Ausserhalb des Fensters wird die geplante Dauer anteilig genommen, sonst
  /// aus dem Tempo geschaetzt.
  static int plausibleSekunden(ActiveRideSnapshot s) {
    final sek = s.fahrSekunden;
    if (s.drivenKm <= 0) return 0;
    if (sek > 0) {
      final kmh = s.drivenKm / (sek / 3600.0);
      if (kmh >= _minPlausibelKmh && kmh <= _maxPlausibelKmh) return sek;
    }
    final geplantSek = s.durationSeconds;
    final geplantKm = s.anzeigeGeplantKm;
    if (geplantSek != null && geplantSek > 0 && geplantKm > 0) {
      return (geplantSek * (s.drivenKm / geplantKm)).round();
    }
    // Rueckfall: 50 km/h Schnitt.
    return (s.drivenKm / 50.0 * 3600.0).round();
  }

  static String fingerprint(ActiveRideSnapshot s) =>
      'unterbrochen:${s.rideId ?? s.startedAt.millisecondsSinceEpoch}';

  /// Bucht den gefahrenen Teil (falls buchbar) und LOESCHT den Schnappschuss.
  /// Bei Netzfehler bleibt er (als verworfen markiert) liegen — der naechste
  /// App-Start versucht es erneut. Gibt true zurueck, wenn danach nichts mehr
  /// offen ist (gebucht, nichts zu buchen, fremder Nutzer, nicht angemeldet).
  static Future<bool> verbucheUndLoesche(ActiveRideSnapshot s) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    // Fremder Fahrer: nichts gutschreiben, aber auch nicht liegen lassen.
    if (uid == null || (s.userId != null && s.userId != uid)) {
      await ActiveRideSnapshotService.clear();
      return true;
    }
    try {
      final streak = await GamificationService.getStreakDaysForNextRide(
        rideDate: s.startedAt,
      );
      final p = posten(s, streakTage: streak);
      if (p == null) {
        await ActiveRideSnapshotService.clear();
        return true;
      }
      final fp = fingerprint(s);
      final schonDa = await Supabase.instance.client
          .from('user_drive_sessions')
          .select('id')
          .eq('user_id', uid)
          .eq('route_fingerprint', fp)
          .limit(1);
      if ((schonDa as List).isEmpty) {
        // 2026-08-19: Der Zustand wird geladen, weil die XP-Rechnung in
        // `posten` die Doppel-XP-Woche selbst abfragt (sie steckt seitdem in
        // der BASIS des Streak-Multiplikators, nicht mehr in einem Faktor am
        // Ende). Frueher stand hier zusaetzlich
        // `StarterAufgabenService.wendeBonusAn(p.xp)` - das wuerde die Woche
        // ein zweites Mal zaehlen und ist deshalb weg.
        await StarterAufgabenService.instance.load();
        final session = await GamificationService.recordDriveSession(
          distanceKm: p.km,
          durationSeconds: p.sekunden,
          completedAtEnd: false,
          routeStyle: s.style,
          routeType: s.isRoundTrip ? 'ROUND_TRIP' : 'POINT_TO_POINT',
          routeFingerprint: fp,
          source: 'navigation_unterbrochen',
          xpAwarded: p.xp,
          createdAt: s.savedAt,
        );
        if (session == null) {
          await ActiveRideSnapshotService.clear();
          return true;
        }
        debugPrint(
          '[Verbuchung] Unterbrochene Fahrt gebucht: '
          '${p.km.toStringAsFixed(1)} km, ${p.sekunden} s, ${p.xp} XP',
        );
      } else {
        debugPrint('[Verbuchung] schon gebucht ($fp) — nur aufraeumen');
      }
      await ActiveRideSnapshotService.clear();
      return true;
    } catch (e) {
      debugPrint(
        '[Verbuchung] fehlgeschlagen, bleibt zum Nachbuchen liegen: $e',
      );
      await ActiveRideSnapshotService.markiereVerworfen();
      return false;
    }
  }
}

class VerbuchungsPosten {
  const VerbuchungsPosten({
    required this.km,
    required this.sekunden,
    required this.xp,
  });
  final double km;
  final int sekunden;
  final int xp;
}
