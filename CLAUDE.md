# CruiserConnect – Claude Context Guide

## Projekt-Überblick
CruiseConnect ist eine Flutter-App für Autofahrer-Community: Routen generieren, cruisen, Sights automatisch einbauen, Social-Features.

**Stack:** Flutter/Dart (Frontend) + Supabase (Backend/Auth/DB/Edge Functions) + Mapbox (Maps/Routing/Geocoding)
**Sprache im Code:** Mix aus Deutsch (UI-Texte, Kommentare) und Englisch (Variablennamen, API)
**Min SDK:** Dart 3.9.2

## Architektur

```
lib/
├── core/constants.dart              # API-Keys (Mapbox, Supabase)
├── data/services/                   # 8 Services (Business-Logik + API-Calls)
│   ├── route_service.dart           # ⭐ KERN: Routenberechnung via Supabase Edge Function
│   ├── route_cache_service.dart     # Pre-Caching Queue (5 Routen vorberechnen)
│   ├── saved_routes_service.dart    # CRUD für gespeicherte Routen
│   ├── auth_service.dart            # Supabase Auth (Login/Register/Logout)
│   ├── social_service.dart          # Posts, Follows, Likes, Comments, Groups, Notifications
│   ├── gamification_service.dart    # XP, Level (12 Stufen), Badges (16 Typen)
│   ├── geocoding_service.dart       # Mapbox Geocoding + Autocomplete
│   └── offline_map_service.dart     # Karten-Caching für Offline-Nutzung
├── domain/models/                   # Datenmodelle
│   ├── route_result.dart            # GeoJSON + Koordinaten + Manöver + SpeedLimits
│   ├── route_maneuver.dart          # Turn-by-Turn Anweisungen + RouteWindowMatch
│   ├── saved_route.dart             # Persistente Route
│   ├── badge.dart                   # 16 Achievement-Badges
│   ├── user_level.dart              # 12-Stufen XP-System
│   └── mapbox_suggestion.dart       # Geocoding-Vorschläge + Waypoints
├── presentation/
│   ├── pages/                       # 19 Screens
│   │   ├── cruise_mode_page.dart    # ⭐ KERN: Routenplanung + Live-Navigation (~1800 Zeilen)
│   │   ├── home_page.dart           # 5-Tab Container (IndexedStack)
│   │   ├── community_page.dart      # Social Feed mit Realtime
│   │   ├── analytics_page.dart      # Statistiken + Charts
│   │   └── profile_page.dart        # Profil + Posts + Routen
│   └── widgets/cruise/              # 8 Navigation-Widgets
│       ├── cruise_maneuver_indicator.dart   # Abbiegehinweis-Banner
│       ├── cruise_curve_warning.dart        # Kurvenwarnung (4 Stufen)
│       ├── cruise_navigation_info_panel.dart # Restzeit + Restdistanz
│       ├── cruise_completion_dialog.dart    # Route-Ende Dialog
│       ├── cruise_setup_card.dart           # Routenplanung UI
│       ├── cruise_elevation_profile.dart    # Höhenprofil
│       └── drive_control_panel.dart         # Start/Pause/Stop
```

## Routing-Architektur (Kernfeature)

### Routenberechnung
1. User wählt Modus (Rundkurs / A→B) + Distanz + Stil
2. `RouteService` ruft Supabase Edge Function `generate-cruise-route` auf
3. Edge Function nutzt Mapbox Directions API
4. Response enthält: GeoJSON-Geometrie, Legs→Steps→Maneuvers, SpeedLimits
5. `extractManeuvers()` parst Mapbox-Steps zu `RouteManeuver`-Objekten
6. `_snapRouteToStartPosition()` bereinigt Start-Schleifen + Loops
7. `_filterManeuvers()` entfernt U-Turns, Zwischen-Arrives, sinnlose Geradeaus

### Turn-by-Turn Navigation (cruise_mode_page.dart)
- GPS-Stream: `geolocator` mit `bestForNavigation`, `distanceFilter: 8m`
- Position-Matching: `findNearestInWindow()` — Sliding Window (40 Punkte voraus)
- Aktives Manöver: `_updateActiveManeuver()` — erstes Manöver mit routeIndex >= currentIndex
- Distanz zum Manöver: `_calculateDistanceToManeuver()` — Summe der Segmentdistanzen
- Off-Route: >150m für 5+ Updates → Rerouting via Mapbox
- Route-Ende: <50m vom Endpunkt + currentIndex am Ende → Completion Dialog

### Manöver-Typen (Mapbox → Deutsche Anweisung)
| Mapbox Type | Modifier | Icon | Deutsche Anweisung |
|-------------|----------|------|--------------------|
| turn | left/right/sharp/slight | turn_left/right/sharp/slight | Links/Rechts abbiegen |
| end of road | left/right | turn_left/right | Links/Rechts abbiegen (Straßenende) |
| roundabout | exit 1-4 | Custom Painter | Im Kreisverkehr X. Ausfahrt |
| arrive | — | flag | Ziel erreicht |
| fork | left/right | fork_left/right | Links/Rechts halten |
| on/off ramp | left/right | ramp_left/right | Auf-/Ausfahrt nehmen |
| merge | — | merge | Einfädeln |
| new name/continue | slight/left/right | entsprechend | Richtungsänderung bei Straßenwechsel |

### Kurvendetektion (cruise_curve_warning.dart)
- Scannt 400 Punkte voraus in 12er-Segmenten
- Bearing-Differenz zwischen Segmenten berechnen
- Schwellen: 35° gentle, 50° moderate, 80° sharp, 130° hairpin
- Mindestabstand 30m zwischen Messpunkten (verhindert GPS-Rauschen)

## State Management
- **Kein globaler State Manager** (kein Provider/BLoC/Riverpod)
- Alles über `StatefulWidget` + `setState()`
- `ValueNotifier` für Cross-Page Kommunikation (z.B. `pendingRoute`, `isFullscreen`)
- Supabase Realtime Channels für Live-Updates (Posts, Notifications)

## Häufige Problembereiche

### Routenlogik
- **Mapbox generiert manchmal Start-Schleifen** → `_snapRouteToStartPosition()` schneidet sie ab
- **Rundkurse haben mehrere Legs** → jedes Leg hat ein "arrive" → nur letztes behalten
- **U-Turns** → werden komplett gefiltert (beide Richtungen)
- **Coordinate-Density variiert** → Mapbox packt mehr Punkte in Kurven, weniger auf Geraden

### iOS-spezifisch
- Immer `Runner.xcworkspace` öffnen (NICHT `.xcodeproj`) — sonst fehlen CocoaPods
- CarPlay-Support wurde entfernt (braucht Apple Developer Program)
- `flutter clean && flutter pub get && cd ios && pod install` bei Build-Problemen

## Coding-Konventionen
- Deutsche UI-Texte, englische Variablennamen
- Services als Klassen mit `const` Constructor
- Models als immutable Klassen mit `required` named parameters
- Distanzen intern in Metern, Anzeige in km mit deutschem Dezimalkomma
- Koordinaten als `[longitude, latitude]` (Mapbox-Format, NICHT lat/lng!)
- GeoJSON LineString für Routendarstellung auf der Karte

## Befehle
```bash
# App starten
flutter run

# Analyse
flutter analyze lib/

# iOS Build vorbereiten
cd ios && pod install && cd ..

# Clean Build
flutter clean && flutter pub get && cd ios && pod install && cd ..
```

## Supabase Edge Functions
- `generate-cruise-route` — Hauptrouten-Generierung (Mapbox Directions API Wrapper)
- Deployment via Supabase CLI
- Response-Format: `{ route: { geometry, legs, distance, duration }, meta: {...} }`
