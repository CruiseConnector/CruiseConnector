# Cruise Connector — Onboarding für einen KI-Coding-Agenten (Codex)

> Kopiere dieses Dokument als ersten Kontext in Codex (oder lege es als `AGENTS.md`
> ins Repo-Root). Es erklärt das Projekt, das Setup und die Regeln, damit der Agent
> sofort sinnvoll arbeiten kann.

## Was ist das?
**Cruise Connector** — eine Flutter-App für Autofahrer/Motorradfahrer: Routen
generieren (Rundkurse + A→B), live „cruisen" mit Turn-by-Turn-Navigation, Gruppen-
Fahrten mit Live-Standort, plus Social-/Gamification-Features. Deutsche UI, englische
Variablennamen. App-Store-Launch steht kurz bevor — also **stabil bleiben, nichts
kaputt machen**.

## Stack
- **Frontend:** Flutter / Dart (eine Codebasis für Android + iOS).
- **Backend:** Supabase (Auth, Postgres-DB, Storage, Edge Functions, Realtime).
- **Routing:** selbst-gehostetes **GraphHopper** (2 Mini-PCs, DE/EU), angesprochen aus den Edge Functions.
- **Karten:** **MapLibre GL Native** + Vektor-Tiles als **PMTiles** auf **Cloudflare R2** (`tiles.cruiseconnector.at`), eigener dunkler Style. (KEIN Mapbox-SDK clientseitig.)
- **Push:** Firebase Cloud Messaging (Android) + APNs (iOS).
- **Geocoding (Adress-Suche):** serverseitig über die Edge-Function `geocode` (Nominatim/Photon).

## Prerequisites (WICHTIG: exakte Versionen)
- **Flutter 3.44.2 / Dart 3.12.2** — NICHT neuer, nicht älter. (`sign_in_with_apple` 8.1 verlangt das; pubspec hat eine Schranke `sdk ^3.12.0`, `flutter >=3.44.0`.) `flutter --version` prüfen.
- Xcode (für iOS) + CocoaPods, Android SDK (für Android), ein Apple-Developer-Team für Geräte-Builds.
- `supabase` CLI (für Edge-Function-Deploys), optional.

## Erststart (Setup)
```bash
# 1. Repo klonen
git clone <REPO_URL> && cd CruiserConnect

# 2. Secrets anlegen (siehe HANDOFF_SECRETS.md — Werte kommen von Vucko)
cp lib/config/secrets.example.dart lib/config/secrets.dart
#   → echte Supabase-/Google-Werte eintragen
#   → android/app/google-services.json + ios/Runner/GoogleService-Info.plist einlegen

# 3. Dependencies
flutter pub get

# 4. Im Debug auf einem Gerät/Emulator starten
flutter run            # Debug — braucht KEINEN Release-Keystore

# 5. Statische Analyse (nach JEDER Code-Änderung!)
flutter analyze lib/

# 6. Tests
flutter test
```

## Builds
```bash
flutter build apk --release          # Android (braucht android/key.properties + Keystore)
flutter build ios --release          # iOS (braucht Apple-Signing)
```
- **Exit-0-Falle:** `flutter build ... | tail` liefert rc=0 auch bei „BUILD FAILED".
  Immer auf die Zeile **`✓ Built …`** prüfen, nicht nur den Exit-Code.
- Nach `flutter test` kann ein stale Plugin-Registrant den APK-Build brechen
  („integration_test ist nicht vorhanden") → dann `flutter clean && flutter pub get` vor dem Build.
- **iOS auf Gerät:** `flutter build ios --release` ZUERST (sonst spielt `flutter install`
  einen alten Build auf). Install via `xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app`.

## Architektur / wichtigste Dateien
```
lib/
  main.dart                                  App-Start, Deep-Links, Splash, Hochformat-Lock
  core/                                       Konstanten, Deep-Link-Helfer, Limits
  config/secrets.dart                         (gitignored) API-Keys
  domain/models/                              Datenmodelle (SavedRoute, UserDriveSession, …)
  data/services/
    route_service.dart                        Routenberechnung, Manöver-Extraktion, Icons (groß!)
    gamification_service.dart                 XP, Badges, Streak, countCurves
    saved_routes_service.dart                 gespeicherte Routen (Tabelle routes)
    social_service.dart                       Posts, Storage-Upload/Delete
    map_style_service.dart / offline_map_service.dart   Karten-Style + Offline-Cache
  presentation/
    pages/cruise_mode_page.dart               Navigation, GPS-Tracking, Reroute (~16k Zeilen, Kern)
    pages/route_share_page.dart               Strava-artiger Teilen-Composer
    pages/home_content_page.dart, profile_page.dart, analytics_page.dart, …
    widgets/cruise/                           Manöver-Banner, Kurvenwarnung, Karte, Kreisverkehr-Symbol
supabase/
  functions/                                  Edge Functions (Deno/TypeScript): generate-cruise-route(-v2),
                                              geocode, send-push, curate-route-pool, process-route-seed-jobs, …
  migrations/                                 SQL-Migrationen
```
> Die ausführliche Architektur steht in **`CLAUDE.md`** (im Repo-Root) — dort ZUERST lesen.

## Konventionen & Stolpersteine (unbedingt beachten)
- **Koordinaten sind `[longitude, latitude]`** (Mapbox-/GeoJSON-Reihenfolge), nicht lat/lng.
- **Deutsche UI-Texte**, englische Variablennamen.
- **Nach Code-Änderungen IMMER `flutter analyze lib/`** — Ziel: 0 Issues.
- **NIE** API-Keys/Tokens aus `lib/config/secrets.dart` / `lib/core/constants.dart` ausgeben oder committen.
- **Release-Crash-Falle:** kein `RenderObject.debugNeedsPaint` o.ä. `debug*`-Getter im
  versendeten Code — Asserts sind im Release entfernt → `LateInitializationError`.
- **Edge Functions:** brauchen oft `verify_jwt = false` in `config.toml`; GraphHopper ehrt
  `custom_model` NUR per POST.
- **Edits am richtigen Ort:** wenn mit git-Worktrees gearbeitet wird, im jeweiligen Pfad editieren.
- Branch-Strategie: Feature-Branches, `main` ist Release. CarPlay/Android-Auto liegen in
  eigenem Branch, NICHT in `main`.

## Verifikation, bevor etwas „fertig" ist
1. `flutter analyze lib/` → keine Fehler.
2. `flutter test` → grün.
3. Für UI-/Navi-Änderungen: auf echtem Gerät (oder iOS-Simulator) gegenchecken — viele
   Bugs zeigen sich NUR am Gerät (1 Hz GPS, native Karte).
4. Niemals halbe Stände als „fertig" melden; ehrlich sagen, was getestet ist und was nicht.

## Was als Nächstes ansteht (Stand 2026-06-25, App-Version 1.0.4+35)
- Restliche Navi-Politur (Reroute-Latenz, Kreisverkehre) ist großteils erledigt; offene
  Punkte sind in `CLAUDE.md` / den Commit-Messages dokumentiert.
- Store-Release vorbereiten (Signing, Screenshots, Datenschutz).
