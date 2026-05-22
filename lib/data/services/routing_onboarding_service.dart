import 'package:shared_preferences/shared_preferences.dart';

/// Routing-Onboarding-Service mit Doppel-Open-Schutz.
///
/// Das Sheet wird beim allerersten Cruise-Tab-Open angezeigt. Da
/// `addPostFrameCallback` mehrfach feuern kann (z. B. wenn CruiseModePage
/// im IndexedStack mehrfach gebaut wird oder ein Provider rebuild
/// triggert), reicht der reine SharedPreferences-Check nicht — ein
/// async-await-Lauf liest die Prefs erst nach mehreren Frames, in der
/// Zwischenzeit kann das Sheet bereits ein zweites Mal geplant sein.
///
/// `_openLock` verhindert genau das: er wird beim ersten Show-Aufruf
/// SOFORT (synchron) gesetzt und erst nach `markAccepted()` oder beim
/// Schließen wieder freigegeben.
class RoutingOnboardingService {
  RoutingOnboardingService._();

  static const String acceptedKey = 'routing_onboarding_v1_accepted';

  // Synchroner Lock — gilt nur für die aktuelle App-Session.
  // Verhindert dass parallel mehrere Sheets geöffnet werden.
  static bool _openLock = false;

  static bool get isOpen => _openLock;

  static void acquireLock() {
    _openLock = true;
  }

  static void releaseLock() {
    _openLock = false;
  }

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(acceptedKey) ?? false;
  }

  static Future<void> markAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(acceptedKey, true);
  }

  /// Für Tests / Settings „Hinweis zurücksetzen".
  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(acceptedKey);
  }
}
