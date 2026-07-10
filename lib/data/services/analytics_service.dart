import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Zentrale Firebase-Analytics-Fassade — Nutzerzahlen, Sitzungsdauer und
/// Screen-Flow kommen automatisch (Firebase Console → Analytics). Diese
/// Klasse ergänzt gezielt Custom Events an den Stellen, an denen Nutzer
/// im Funnel aufgeben (Routen-Generierung, Onboarding, Fahrt), damit man
/// in der Konsole sieht WO genau — nicht nur DASS Nutzer abspringen.
///
/// Crash-Reporting läuft separat über FirebaseCrashlytics (siehe main.dart) —
/// diese Klasse ist nur für Analytics/Funnel-Events zuständig.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsObserver? _observer;

  /// NavigatorObserver für MaterialApp.navigatorObservers — trackt jeden
  /// Seitenwechsel automatisch als "screen_view" (Basis für Sitzungsdauer +
  /// Nutzungshäufigkeit pro Screen in der Firebase Console).
  FirebaseAnalyticsObserver get observer =>
      _observer ??= FirebaseAnalyticsObserver(analytics: analytics);

  FirebaseAnalytics get analytics => _analytics ??= FirebaseAnalytics.instance;

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (kIsWeb) return; // Analytics läuft nur auf Android/iOS in dieser App.
    try {
      await analytics.logEvent(name: name, parameters: params);
    } catch (_) {
      // Best-effort: Analytics darf die App nie beeinträchtigen.
    }
  }

  Future<void> setUserId(String? userId) async {
    if (kIsWeb) return;
    try {
      await analytics.setUserId(id: userId);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Onboarding-Funnel — jeder Schritt einzeln, damit sichtbar wird, WO
  // Nutzer den Account-Wizard abbrechen.
  // ---------------------------------------------------------------------
  Future<void> logOnboardingStep(String step) =>
      _log('onboarding_step', {'step_name': step});

  Future<void> logOnboardingComplete() => _log('onboarding_complete');

  Future<void> logSignUp(String method) =>
      _log('sign_up', {'method': method});

  Future<void> logLogin(String method) => _log('login', {'method': method});

  // ---------------------------------------------------------------------
  // Routen-Generierung — das Kernfeature. Fehler-Events zeigen, WELCHER
  // Modus/Grund Nutzer am häufigsten aussteigen lässt.
  // ---------------------------------------------------------------------
  Future<void> logRouteGenerationStarted(String mode) =>
      _log('route_generation_started', {'mode': mode});

  Future<void> logRouteGenerationSuccess(String mode, String source) =>
      _log('route_generation_success', {'mode': mode, 'source': source});

  Future<void> logRouteGenerationFailed(String mode, String reason) =>
      _log('route_generation_failed', {'mode': mode, 'reason': reason});

  // ---------------------------------------------------------------------
  // Fahrt/Cruise-Mode — Abbruch zeigt, ob/wo Nutzer Fahrten vorzeitig
  // beenden (z.B. wegen Navigationsproblemen).
  // ---------------------------------------------------------------------
  Future<void> logTripStarted(String mode) =>
      _log('trip_started', {'mode': mode});

  Future<void> logTripCompleted(double distanceKm, int durationSeconds) =>
      _log('trip_completed', {
        'distance_km': distanceKm,
        'duration_seconds': durationSeconds,
      });

  Future<void> logTripAbandoned(String mode, int durationSeconds) =>
      _log('trip_abandoned', {'mode': mode, 'duration_seconds': durationSeconds});

  // ---------------------------------------------------------------------
  // Gruppen
  // ---------------------------------------------------------------------
  Future<void> logGroupCreated() => _log('group_created');
  Future<void> logGroupJoined() => _log('group_joined');
  Future<void> logGroupLeft() => _log('group_left');
}
