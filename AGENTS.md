# AGENTS.md — CruiseConnect (AI-Arbeitskontext)

Dieses Dokument ist der **Startpunkt für Cursor AI / Claude Code / Codex** in diesem Repo.
Vor jeder nicht-trivialen Aufgabe muss zusätzlich `codex.md` gelesen werden. `codex.md` ist die ausführliche Projekt- und Architekturquelle.

## Projektüberblick
**CruiseConnect** ist eine Flutter-App für eine Autofahrer-Community mit Fokus auf:
- **Rundkurse** (Cruise-Routen generieren)
- **A→B Routen** (mit konfigurierbaren Umwegen/Stil)
- **Navigation** (Turn-by-Turn, Off-Route/Rerouting)
- **Gespeicherte Routen**
- **Community** (Posts, Likes, Kommentare, Gruppen, Notifications)
- **Analytics** (Fahr-/Routen-Statistiken)

## Stack & Plattformen
- **Frontend**: Flutter / Dart (State Management: **lokal via `setState()`**, ergänzend `ValueNotifier`)
- **Backend**: Supabase (Auth, DB, Realtime, **Edge Functions**)
- **Routing/Maps**: Mapbox (Directions, Geocoding, Karten)
- **Plattformen**: iOS, Android, Web, macOS

## Produktbereiche (grobe Struktur)
- **Routing & Navigation**: Route-Generierung, Manöver, Kurvenwarnung, Off-Route/Rerouting
- **Routenverwaltung**: Speichern, Laden, Teilen
- **Community**: Social Feed + Realtime
- **Analytics**: Auswertungen & Charts
- **Offline**: Map-Caching

## Wichtige Einstiegsdateien (Routing/Navigation)
- `lib/data/services/route_service.dart` — **Kern**: Route via Supabase Edge Function, Parsing/Filter
- `lib/data/services/route_quality_validator.dart` — Qualitäts-/Plausibilitätschecks
- `lib/data/services/seen_route_registry.dart` — Duplikat-/Diversity-Tracking
- `supabase/functions/generate-cruise-route/index.ts` — Edge Function (Mapbox Directions Wrapper)
- `lib/presentation/pages/cruise_mode_page.dart` — **Kern-UI & Live-Navigation** (groß)
- `codex.md` — Architektur-/Arbeitskontextguide (**immer zuerst lesen**)

## Arbeitsstil der KI (verbindlich)
- **Pragmatisch & minimalinvasiv**: Kleine, sichere Schritte statt großer Umbauten.
- **Keine unrelated Dateien**: Nur Dateien anfassen, die direkt zur Aufgabe gehören.
- **Reales Verhalten > nur grüne Tests**: Benchmarks/Live-Simulation/realistische Daten sind bei Routing wichtiger als reine Mock-Tests.
- **Statusupdates bei längeren Aufgaben**: Kurz und regelmäßig, damit der Kontext nicht verloren geht.
- **Secrets/Keys**: Niemals API-Keys/Tokens ausgeben oder in Logs/Diffs schreiben (insb. `lib/core/constants.dart`).

## Qualitäts- & Prozessregeln
- **Vor Änderungen**: Kontext in `codex.md` prüfen, dann zielgerichtet suchen/lesen.
- **Refactors vermeiden**: Keine Format-/Naming-/Struktur-Refactors ohne klaren Nutzen für die Aufgabe.
- **Koordinatenformat**: Mapbox nutzt **`[longitude, latitude]`** (nicht `lat/lng`).
- **Verifikation**: Nach Codeänderungen bevorzugt `flutter analyze lib/` und passende Tests/Benchmarks (je nach Aufgabe).

## Commit / Push / Deploy
- **Nur wenn ausdrücklich gewünscht** (und nur wenn Erfolgskriterien erfüllt sind).
- **Kein Deploy** (Supabase/Stores) ohne klar benannte Risiken, Benchmarks und Rollback-Plan.
