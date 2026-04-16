# PROJECT_CONTEXT — CruiseConnect

## Kurzbeschreibung
**CruiseConnect** ist eine Flutter-App für Fahrer:innen, die **Rundkurse** und **A→B Routen** generiert, eine **Live-Navigation** anbietet, Routen speichert und Social-/Community-Features sowie Analytics integriert.

## Produktumfang (high level)
- **Rundkurse**: generierte Cruise-Runden mit konfigurierbarer Distanz/Stil
- **A→B**: Navigation von Start nach Ziel, mit Umweg-Stufen und Präferenzen (z.B. `avoidHighways`)
- **Navigation**: Turn-by-Turn, Off-Route-Erkennung, Rerouting
- **Gespeicherte Routen**: Persistenz/Sharing
- **Community**: Feed, Interaktionen, Realtime
- **Analytics**: Auswertungen der Fahrten/Routen

## Technischer Überblick
- **Flutter/Dart**: UI + Services (kein globaler State Manager; Schwerpunkt auf `setState()` + punktuell `ValueNotifier`)
- **Supabase**: Auth, Datenbank, Realtime, **Edge Functions**
- **Mapbox**: Karten + Geocoding + Directions (Routing)
- **Koordinatenformat**: Mapbox nutzt **`[longitude, latitude]`**

## Routing-/Navigation-Kernpfade
Diese Dateien sind bei Routing-Aufgaben meistens betroffen:
- `/Users/vucko/Development/CruiserConnect/lib/data/services/route_service.dart`
- `/Users/vucko/Development/CruiserConnect/lib/data/services/route_quality_validator.dart`
- `/Users/vucko/Development/CruiserConnect/lib/data/services/seen_route_registry.dart`
- `/Users/vucko/Development/CruiserConnect/supabase/functions/generate-cruise-route/index.ts`
- `/Users/vucko/Development/CruiserConnect/lib/presentation/pages/cruise_mode_page.dart`

## Tests/Benchmarks (Routing)
- `test/route/…` enthält Routing-Tests (u.a. Validator/Qualität).
- `tool/route_service_local_benchmark.dart` ist ein wichtiger Einstieg für **echte** Qualitäts-/Latenzmessungen.

