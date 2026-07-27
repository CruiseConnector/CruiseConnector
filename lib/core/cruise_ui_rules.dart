/// Reine UI-Regeln der Fahransicht, bewusst ohne Flutter-Abhängigkeiten,
/// damit sie ohne Widget-Test überprüfbar sind.
///
/// 2026-07-27 (vucko „Schnellzugriff/POIs sind während der Fahrt weg"):
/// Die Sichtbarkeit der rechten Schnellzugriff-Spalte hing direkt im
/// 17.000-Zeilen-Widget an einer zusammengesetzten Bedingung und war damit
/// faktisch ungetestet. Eine falsche Verknüpfung ließ die Spalte mitten in
/// der Navigation verschwinden. Die Regel steht deshalb jetzt hier — an
/// einer Stelle, benannt, und mit Tests abgesichert.
library;

/// Soll die rechte Schnellzugriff-Spalte (POI-Filter, Sprachausgabe,
/// Kamera-Lock, Melde-Button) ausgeblendet werden?
///
/// [hasRoute] true, sobald die Fahransicht im Navigations-Zustand ist.
/// [waypointRailActive] true, wenn im Wegpunkte-Modus bereits die eigene
/// rechte Leiste steht (sonst lägen zwei Spalten übereinander).
/// [configCollapsed] true, wenn das Strecken-Setup heruntergewischt ist und
/// die Karte freigibt. Dieses Sheet existiert **nur vor** der bestätigten
/// Route; während der Fahrt ist der Wert bedeutungslos und stellenweise
/// sogar false (Fahrt-Resume, Startwert).
bool cruiseFabColumnHidden({
  required bool hasRoute,
  required bool waypointRailActive,
  required bool configCollapsed,
}) {
  if (waypointRailActive) return true;
  // Während der Fahrt IMMER sichtbar: dort gibt es kein Setup-Sheet, das die
  // Karte verdecken könnte, und die Buttons werden gerade dann gebraucht.
  if (hasRoute) return false;
  return !configCollapsed;
}
