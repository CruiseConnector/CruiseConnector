# Compact-Resume — CruiseConnect

**Letztes Update**: 2026-05-24
**Branch**: `graphhopper-dach-stabilize`
**Worktree**: `/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f`
**Supabase Project-ID**: `tlcfaxvvqzobmzwvfnvb`

## Sofort-Status

System läuft autonom. Heartbeat- und Scout-Loops via Claude-Cron.
- GH-DACH-Server: ok (smoke 49.48km/58t/pen 0)
- GH-DE-Server: ok
- Pool: 2.182 routes / 48 DACH-cities
- Edge `generate-cruise-route-v2` deployed
- Edge `daily-weather-push` deployed mit pg_cron daily 06:00 UTC

## Architektur-Kern

- **Flutter Front-End** (lib/) – ~250 dart-files
- **Supabase Backend** (postgres + RLS + pg_cron + Realtime)
- **GraphHopper 8.0** für Routing (DACH-Server + DE-Server fallback)
- **OpenMeteo** für Wetter (gratis, kein Key)
- **Mapbox** nur als Tile-Provider (keine Routing-Logik)

## Was in dieser Session (42+ Tasks) gebaut wurde

### Routing
- A→B mit detour 0-3 funktioniert für alle DACH-Distanzen
- Trip-Modus = A→B mit Multi-Stopps (letzter WP = Endziel)
- Bodensee-Fähre via Custom-Model `road_environment==FERRY → limit_to=0` blockiert
- Snap-Fallback 3-stufig (130m → 1.1km → 5.5km)
- Server-Wahl checkt ALLE Punkte (DACH/DE)
- Quality-Filter für A→B: nur `destinationReached`
- Loop-Cleanup für Round-Trip
- Klare Error-Codes statt "Temporärer Serverfehler"

### UI/UX
- Trip-Mode-Picker als iOS-Style Segmented-Pill (44px)
- Style-Dock aus Map raus (nur in Setup-Panel)
- Wegpunkte 3/5-Limit dynamisch je Modus
- Mode-Header verbirgt sich bei Error-Banner
- TopToast oben statt Bottom-Snackbar
- Pull-to-Refresh Home
- Disclaimer rechtssicher

### Notifications v2
- DB-Triggers auto-erzeugen Notifications (follows, likes, group_members)
- Like-Batching 10-min-Buckets (aggregate_count)
- NotificationService + Supabase Realtime
- Inbox-Page mit Swipe + Mark-all-read
- Bell-Badge in Home-Header
- 6 Settings-Switches
- Daily-Weather-Push (pg_cron 06:00 UTC)

### Wetter
- WeatherChip mit Pulse-Animation + Tageszeit-Gradient
- Trend für lange Routen ("Sonnig → Regen")

### USP-Features (Marktdifferenzierung)
- **Driven Track Overlay**: geplant grau + echt accent → "Das bin ich gefahren". Im Completion + PNG-Share
- **Streak-Hero-Banner**: above-the-fold ab 2 Tagen
- **Kurven-DNA**: Rider-Type (KURVEN-JÄGER/SPORT-TYP/CRUISER/EXPLORER) + 8 Stats-Chips

### Navigation
- Haptic 3-Stufen (300/150/50m)
- Voice-TTS mit 3 Modi (off/important/all)
- Map-Live 200ms

### Security + Infra
- RLS überall (route_pool_coverage_snapshot war einzige Lücke)
- Heartbeat-Loop minütlich + Scout-Loop 30min
- 41 DACH-Cities seeded (10 Umlaut-Cities noch pending)

## Offene Tasks (diese Session)

1. **POIs entlang Route** (Task #44) — IN ARBEIT
2. **Baustellen/Stau-Reroute** (Task #45) — IN ARBEIT
3. **CarPlay/Android Auto Foundation** (Task #46) — IN ARBEIT

## Wichtige Commands

```bash
# Heartbeat
bash scripts/dach_loop_ensure.sh
bash scripts/dach_watchdog.sh

# Scout
bash scripts/dach_improvement_ensure.sh
bash scripts/dach_improvement_watchdog.sh

# Edge deploy (aus Worktree)
supabase functions deploy generate-cruise-route-v2 --no-verify-jwt
supabase functions deploy daily-weather-push --no-verify-jwt

# Tests
flutter analyze lib/

# Live Route Test
curl -sS -X POST "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
  -H "Content-Type: application/json" \
  -d '{"route_type":"ROUND_TRIP","start_location":{"latitude":47.5031,"longitude":9.7471},"selected_style":"Sport Mode","target_distance_km":50,"avoid_highways":true}'
```

## Kritische Dateien

- `lib/presentation/pages/cruise_mode_page.dart` — ~8500 Zeilen
- `lib/data/services/route_service.dart` — ~9300 Zeilen
- `lib/data/services/route_style_config.dart` — Style + Limits
- `supabase/functions/generate-cruise-route-v2/index.ts` — Edge v2
- `lib/data/services/notification_service.dart` — Realtime
- `lib/presentation/widgets/weather_chip.dart` — Wetter
- `lib/presentation/widgets/cruiser_dna_card.dart` — DNA

## User-Stil (kritisch)

- Vucko schreibt Deutsch — Antworten auf Deutsch
- "Autobahn an / Autobahn aus" NICHT "AB-AN / AB-AUS"
- Erwartet ehrliche Diagnose, klare Optionen, dann seine Entscheidung
- Pushed selber nach größeren Sweeps
- NIEMALS API-Keys aus core/constants.dart ausgeben

## Heartbeat-System

Cron: `7,22,37,52 * * * *` (15 min)
Antwort-Format:
```
🟢/🟡/🔴 [HH:MM]
  GH Servers: DACH ok | DE ok
  Pool: 2.182 routes / 48 cities
  Demand last 15min: N suchen
  Auto-Seed-Queue: M pending
  Open Tasks: #44 POI, #45 Reroute, #46 CarPlay
  Nächste 15min: <was passiert>
```

## Scout-System (parallel)

Cron: `*/30 * * * *`
Schreibt nach `logs/improvement-suggestions.log`

## Rückkehr nach Compact

1. **Read this file first**
2. `git log --oneline -15` für letzte Commits
3. `flutter analyze lib/` für Health
4. Bei Routing-Fragen: erst Edge-Function curl-Test
5. User merkt sofort wenn was vergessen — direkt fragen statt raten

## Letzte Commits

- `5be51ac` 3 USP-Features (Driven-Track, Streak-Hero, Kurven-DNA)
- `f7b30f9` 9-Tasks-Sweep (Trip-Bug, TTS, Elevation, Wetter-Polish)
- `f1d3eba` Notification-System v2 (vollständig)
- `75b2da0` Trip-Modus + UI-Cleanup + Wetter-Trend
- `847fd84` Bodensee-Fähre blockiert
- `21c49f7` A→B Dijkstra-Accept
- `d018add` schlanker Mode-Header + Voice-Toggle
