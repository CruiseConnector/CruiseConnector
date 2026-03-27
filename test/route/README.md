# CruiserConnect Route Tests

Vollständige Testabdeckung der Routenlogik mit Mockito.

## Tests ausführen

```bash
# Alle Route-Tests
flutter test test/route/

# Einzelne Test-Datei
flutter test test/route/curve_detection_test.dart

# Mit Coverage
flutter test test/route/ --coverage
```

## Test-Dateien

| Datei | Was wird getestet |
|-------|-------------------|
| `coordinate_extraction_test.dart` | `extractCoordinates` – GeoJSON Parsing |
| `maneuver_extraction_test.dart` | `extractManeuvers` – Alle Manöver-Typen |
| `maneuver_filter_test.dart` | `filterManeuvers` – U-Turns, Arrives, Geradeaus |
| `icon_mapping_test.dart` | `iconForManeuver`, `directionText`, `formatDistance` |
| `window_matching_test.dart` | `findNearestInWindow` – Off-Route Erkennung |
| `bearing_test.dart` | `calculateBearing`, `headingDeltaDegrees`, U-Turn-Erkennung |
| `curve_detection_test.dart` | `detectNextCurve` – Alle 4 Schwärfegrade |
| `navigation_guidance_test.dart` | `selectForwardRejoinIndex`, Heading-Utils |
| `route_generation_mock_test.dart` | Mockito-Tests für `generateRoundTrip`/`generatePointToPoint` |

## Hinweis zu Mocks

Die Datei `route_generation_mock_test.mocks.dart` wurde manuell erstellt
(da Flutter nicht im VM verfügbar). Bei Änderungen an `RouteEdgeInvoker`
bitte die Mock-Datei entsprechend aktualisieren oder neu generieren:

```bash
dart run build_runner build --delete-conflicting-outputs
```
