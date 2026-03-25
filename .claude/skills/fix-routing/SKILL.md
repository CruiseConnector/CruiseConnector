---
name: fix-routing
description: Analysiert und fixt Routenlogik-Bugs (falsche Abbiegungen, U-Turns, fehlende Manöver, Kurvenwarnung). Nutze diesen Skill wenn der User Probleme mit der Navigation, Turn-by-Turn Anweisungen oder der Routendarstellung meldet.
argument-hint: [Beschreibung des Routing-Bugs]
---

## Routing-Bug Fix Workflow

Du bist ein Experte für Mapbox Directions API und Flutter-basierte Turn-by-Turn Navigation. Dein Ziel: den beschriebenen Routing-Bug analysieren und fixen.

### Schritt 1: Bug verstehen
Analysiere die Beschreibung des Users: $ARGUMENTS

### Schritt 2: Relevante Dateien lesen
Die Routing-Logik verteilt sich auf diese Dateien — lies die relevanten:

- **Manöver-Extraktion & Icons:** `lib/data/services/route_service.dart`
  - `extractManeuvers()` — parst Mapbox Steps → RouteManeuver
  - `_iconForManeuver()` — mappt type+modifier → Flutter Icon
  - `_filterManeuvers()` — filtert U-Turns, Zwischen-Arrives
  - `_snapRouteToStartPosition()` — entfernt Start-Schleifen
  - `_removeRouteLoops()` — erkennt/entfernt Route-Loops

- **Navigation State Machine:** `lib/presentation/pages/cruise_mode_page.dart`
  - `_onLocationUpdate()` — GPS-Tracking, Position-Matching
  - `_updateActiveManeuver()` — nächstes aktives Manöver bestimmen
  - `_calculateDistanceToManeuver()` — Distanz entlang Route
  - `_rerouteToOriginalRoute()` — Off-Route Handling

- **Kurvendetektion:** `lib/presentation/widgets/cruise/cruise_curve_warning.dart`
  - `detectNextCurve()` — Bearing-Differenz, Schwellenwerte

- **Manöver-Anzeige:** `lib/presentation/widgets/cruise/cruise_maneuver_indicator.dart`

- **Datenmodelle:** `lib/domain/models/route_maneuver.dart`, `lib/domain/models/route_result.dart`

### Schritt 3: Ursache identifizieren
Typische Ursachen:
- **Falsche U-Turns:** Mapbox generiert "uturn" Modifier bei Rundkurs-Legs
- **"Ziel erreicht" mitten in Route:** Mehrere Legs = mehrere "arrive" Steps
- **Fehlende Abbiegung:** `new name`/`continue` Typ mit echtem Richtungswechsel wird als "geradeaus" ignoriert
- **Falsche Kurvenwarnung:** GPS-Koordinaten zu dicht → Bearing-Rauschen
- **Icon falsch:** `_iconForManeuver()` hat keinen Case für den Typ/Modifier

### Schritt 4: Fix implementieren
- Ändere NUR die Dateien die den Bug verursachen
- Teste mit `flutter analyze lib/` dass keine Errors entstehen
- Erkläre dem User was genau geändert wurde und warum

### Wichtige Regeln
- Koordinaten sind IMMER [longitude, latitude] (Mapbox-Format)
- Distanzen intern in Metern
- Mapbox Maneuver Types: turn, arrive, depart, roundabout, rotary, fork, merge, on ramp, off ramp, end of road, new name, continue, notification
- Mapbox Modifiers: left, right, slight left, slight right, sharp left, sharp right, uturn, straight
