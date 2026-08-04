import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Entscheidet, WANN wir nach einer Bewertung fragen dürfen.
///
/// 2026-08-04 (vucko): „Nach der ersten Fahrt soll ein Pop-up kommen mit der
/// Sternebewertung. Nicht direkt nach dem Onboarding, weil die Leute kennen ja
/// die App nicht, sondern erst nach der ersten Fahrt, nachdem sie sie
/// abgeschlossen und dann entweder gespeichert oder verworfen haben. Auf gar
/// keinen Fall während der Fahrt. Und wenn sie nicht bewertet haben, soll es
/// alle drei Routen kommen, die man sucht oder fährt oder mitfährt."
///
/// Diese Klasse hält NUR die Entscheidung und die Zähler. Wo gefragt wird,
/// bestimmt der Aufrufer — heute ausschließlich die Home-Schale beim Wechsel
/// auf den Home-Tab. Damit ist „niemals während der Fahrt" keine Prüfung, die
/// man vergessen kann, sondern ergibt sich aus dem Ort des Aufrufs.
class RideRatingPromptService {
  RideRatingPromptService._();
  static final RideRatingPromptService instance = RideRatingPromptService._();

  /// Abgeschlossene Fahrten (gespeichert ODER verworfen — beides zählt, der
  /// Nutzer hat die Fahrt ja hinter sich).
  static const _kCompletedRides = 'ride_rating_completed_rides_v1';

  /// Alles, was vuckos „Routen" meint: gesucht, gefahren, mitgefahren.
  static const _kRouteEvents = 'ride_rating_route_events_v1';

  /// Wie oft das Popup schon zu sehen war.
  static const _kPromptsShown = 'ride_rating_prompts_shown_v1';

  /// Stand von [_kRouteEvents] beim letzten Popup — Basis für „alle drei".
  static const _kEventsAtLastPrompt = 'ride_rating_events_at_last_prompt_v1';

  /// Bewertet oder ausdrücklich abgelehnt → nie wieder fragen.
  static const _kSettled = 'ride_rating_settled_v1';

  /// Eine Fahrt ist fertig, das erste Popup steht noch aus.
  static const _kPending = 'ride_rating_pending_v1';

  /// Vuckos „alle drei Routen".
  static const int routesBetweenPrompts = 3;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// Eine Routensuche, ein Fahrtstart oder ein Mitfahren.
  Future<void> registerRouteEvent() async {
    try {
      final p = await _prefs;
      if (p.getBool(_kSettled) ?? false) return;
      await p.setInt(_kRouteEvents, (p.getInt(_kRouteEvents) ?? 0) + 1);
    } catch (e) {
      debugPrint('[RideRating] Routen-Ereignis nicht gezaehlt: $e');
    }
  }

  /// Die Fahrt ist durch — gespeichert oder verworfen.
  ///
  /// Zählt AUCH als Routen-Ereignis: wer fährt, ohne vorher zu suchen
  /// (Aufzeichnen, Gruppenfahrt), soll genauso in den Drei-Rhythmus kommen.
  Future<void> registerCompletedRide() async {
    try {
      final p = await _prefs;
      if (p.getBool(_kSettled) ?? false) return;
      await p.setInt(_kCompletedRides, (p.getInt(_kCompletedRides) ?? 0) + 1);
      await p.setInt(_kRouteEvents, (p.getInt(_kRouteEvents) ?? 0) + 1);
      await p.setBool(_kPending, true);
    } catch (e) {
      debugPrint('[RideRating] Fahrt-Abschluss nicht gezaehlt: $e');
    }
  }

  /// Darf JETZT gefragt werden?
  ///
  /// Erste Frage: sobald die erste Fahrt abgeschlossen ist. Danach: alle
  /// [routesBetweenPrompts] Routen-Ereignisse, solange niemand bewertet oder
  /// abgelehnt hat.
  Future<bool> shouldPrompt() async {
    try {
      final p = await _prefs;
      if (p.getBool(_kSettled) ?? false) return false;

      // Ohne abgeschlossene Fahrt wird nie gefragt. Das ist die Umsetzung von
      // „nicht direkt nach dem Onboarding" — frisch installiert steht der
      // Zaehler auf 0, ganz gleich wie viel sonst schon passiert ist.
      final rides = p.getInt(_kCompletedRides) ?? 0;
      if (rides < 1) return false;

      final shown = p.getInt(_kPromptsShown) ?? 0;
      if (shown == 0) return p.getBool(_kPending) ?? false;

      final events = p.getInt(_kRouteEvents) ?? 0;
      final seit = events - (p.getInt(_kEventsAtLastPrompt) ?? 0);
      return seit >= routesBetweenPrompts;
    } catch (e) {
      debugPrint('[RideRating] Entscheidung fehlgeschlagen: $e');
      return false;
    }
  }

  /// Das Popup war zu sehen. Setzt den Drei-Rhythmus neu auf.
  Future<void> markPromptShown() async {
    try {
      final p = await _prefs;
      await p.setInt(_kPromptsShown, (p.getInt(_kPromptsShown) ?? 0) + 1);
      await p.setInt(_kEventsAtLastPrompt, p.getInt(_kRouteEvents) ?? 0);
      await p.setBool(_kPending, false);
    } catch (e) {
      debugPrint('[RideRating] Popup-Stand nicht gespeichert: $e');
    }
  }

  /// Bewertet oder „nicht mehr fragen" — ab hier ist Ruhe.
  Future<void> markSettled() async {
    try {
      final p = await _prefs;
      await p.setBool(_kSettled, true);
      await p.setBool(_kPending, false);
    } catch (e) {
      debugPrint('[RideRating] Abschluss nicht gespeichert: $e');
    }
  }

  /// Nur für die Diagnose im Debug-Build.
  Future<String> debugState() async {
    final p = await _prefs;
    return 'Fahrten=${p.getInt(_kCompletedRides) ?? 0} '
        'Routen=${p.getInt(_kRouteEvents) ?? 0} '
        'Popups=${p.getInt(_kPromptsShown) ?? 0} '
        'seitLetztem=${(p.getInt(_kRouteEvents) ?? 0) - (p.getInt(_kEventsAtLastPrompt) ?? 0)} '
        'erledigt=${p.getBool(_kSettled) ?? false}';
  }
}
