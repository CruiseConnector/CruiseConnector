import 'package:flutter/foundation.dart';
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
/// SOFORT (synchron) gesetzt und erst beim Schließen wieder freigegeben.
///
/// 2026-08-24 (eingesperrter Nutzer, TikTok): drei Härtungen, damit der
/// Speicher niemanden mehr blockieren kann.
///  1. [tryAcquireLock] prüft und setzt die Sperre in EINEM Schritt. Vorher
///     stand die Prüfung (`isOpen`) vor dem `await hasAccepted()` — zwei
///     gleichzeitige Aufrufe kamen beide durch und öffneten zwei Blätter
///     übereinander. Das zweite Blatt war dann nicht mehr wegzubekommen.
///  2. Kein Aufruf wirft mehr. Ist kein Speicher da (Plugin fehlt, Platte
///     voll, Kanal antwortet nicht), liefert [hasAccepted] `false` und
///     [markAccepted] `false` — der Hinweis erscheint dann eben nochmal.
///     Ein hängender Speicher darf NIE dazu führen, dass das Blatt offen
///     bleibt, deshalb der harte [_speicherTimeout].
///  3. [_acceptedInSession] merkt die Zustimmung für die laufende Sitzung
///     auch dann, wenn das Schreiben fehlgeschlagen ist. Sonst käme das
///     Blatt bei jedem Cruise-Aufruf erneut.
class RoutingOnboardingService {
  RoutingOnboardingService._();

  static const String acceptedKey = 'routing_onboarding_v1_accepted';

  /// Kein Speicherzugriff darf länger dauern. Danach machen wir ohne ihn
  /// weiter — der Nutzer bleibt handlungsfähig.
  static const Duration _speicherTimeout = Duration(seconds: 3);

  // Synchroner Lock — gilt nur für die aktuelle App-Session.
  // Verhindert dass parallel mehrere Sheets geöffnet werden.
  static bool _openLock = false;

  // Zustimmung der laufenden Sitzung, unabhängig vom Speicher.
  static bool _acceptedInSession = false;

  static bool get isOpen => _openLock;

  /// Holt die Sperre atomar. `false` heißt: es läuft bereits ein Blatt.
  ///
  /// Zwischen Prüfung und Setzen darf kein `await` stehen — sonst ist die
  /// Sperre wirkungslos.
  static bool tryAcquireLock() {
    if (_openLock) return false;
    _openLock = true;
    return true;
  }

  static void releaseLock() {
    _openLock = false;
  }

  static Future<bool> hasAccepted() async {
    if (_acceptedInSession) return true;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _speicherTimeout,
      );
      final accepted = prefs.getBool(acceptedKey) ?? false;
      if (accepted) _acceptedInSession = true;
      return accepted;
    } catch (error) {
      // Im Zweifel den Hinweis zeigen statt zu verschlucken. Das ist die
      // harmlose Richtung: nochmal lesen statt festsitzen.
      debugPrint('[RoutingOnboarding] hasAccepted fehlgeschlagen: $error');
      return false;
    }
  }

  /// Merkt die Zustimmung. Gibt `false` zurück, wenn nur der Sitzungs-Merker
  /// gesetzt werden konnte — der Aufrufer darf trotzdem NICHT stehenbleiben.
  static Future<bool> markAccepted() async {
    _acceptedInSession = true;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _speicherTimeout,
      );
      await prefs.setBool(acceptedKey, true).timeout(_speicherTimeout);
      return true;
    } catch (error) {
      debugPrint('[RoutingOnboarding] markAccepted fehlgeschlagen: $error');
      return false;
    }
  }

  /// Für Tests / Settings „Hinweis zurücksetzen".
  ///
  /// Gibt auch die Sperre frei: bliebe sie von einem abgeräumten Blatt
  /// hängen, ließe sich der Hinweis in dieser Sitzung nie wieder öffnen.
  static Future<void> reset() async {
    _acceptedInSession = false;
    _openLock = false;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _speicherTimeout,
      );
      await prefs.remove(acceptedKey).timeout(_speicherTimeout);
    } catch (error) {
      debugPrint('[RoutingOnboarding] reset fehlgeschlagen: $error');
    }
  }
}
