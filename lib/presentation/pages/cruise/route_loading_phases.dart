/// Lade-Phasen-Texte des Cruise-Routen-Loaders.
///
/// 2026-06-26 (vucko): behavior-preserving aus `cruise_mode_page.dart`
/// extrahiert. Die deutschen Phrasenlisten + die Phasen-Auswahl lagen als
/// statische Felder + Getter mitten im 16k-Zeilen-God-Object. Hier als reine,
/// in Isolation testbare Logik — identische Prioritätsreihenfolge (Gruppe >
/// bestehende Route > Wegpunkte > A→B > Rundkurs) und identisches Clamping.
class RouteLoadingPhases {
  RouteLoadingPhases._();

  static const List<String> roundTrip = [
    'Wir suchen eine passende Route',
    'Alternativen werden geprüft',
    'Route verfeinern',
    'Strecke final prüfen',
    'Fast fertig',
  ];

  static const List<String> waypoint = [
    'Stopps verbinden',
    'Nächste Straßen finden',
    'Stil anwenden',
    'Route final prüfen',
    'Fast fertig',
  ];

  static const List<String> pointToPoint = [
    'Ziel prüfen',
    'Straßen finden',
    'Stil anwenden',
    'Route final prüfen',
    'Fast fertig',
  ];

  static const List<String> existingRoute = [
    'Andockpunkt finden',
    'Anfahrt berechnen',
    'Route verbinden',
    'Rückweg vorbereiten',
    'Fast fertig',
  ];

  static const List<String> group = [
    'Route abstimmen',
    'Gruppe synchronisieren',
    'Fast fertig',
  ];

  /// Aktive Phrasenliste für den jeweiligen Modus. Prioritätsreihenfolge 1:1
  /// wie der ursprüngliche Getter in cruise_mode_page.
  static List<String> phrasesFor({
    required bool isGroup,
    required bool isPreparingExisting,
    required bool isWaypoint,
    required bool isRoundTrip,
  }) {
    if (isGroup) return group;
    if (isPreparingExisting) return existingRoute;
    if (isWaypoint) return waypoint;
    if (!isRoundTrip) return pointToPoint;
    return roundTrip;
  }

  /// Anzahl der Phasen für den aktiven Modus.
  static int phaseCount({
    required bool isGroup,
    required bool isPreparingExisting,
    required bool isWaypoint,
    required bool isRoundTrip,
  }) =>
      phrasesFor(
        isGroup: isGroup,
        isPreparingExisting: isPreparingExisting,
        isWaypoint: isWaypoint,
        isRoundTrip: isRoundTrip,
      ).length;

  /// Statustext für den aktuellen Phasen-Index (geclampt auf gültigen Bereich).
  static String statusText({
    required bool isGroup,
    required bool isPreparingExisting,
    required bool isWaypoint,
    required bool isRoundTrip,
    required int phaseIndex,
  }) {
    final phrases = phrasesFor(
      isGroup: isGroup,
      isPreparingExisting: isPreparingExisting,
      isWaypoint: isWaypoint,
      isRoundTrip: isRoundTrip,
    );
    return phrases[phaseIndex.clamp(0, phrases.length - 1)];
  }
}
