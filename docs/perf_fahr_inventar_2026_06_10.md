# Fahr-Performance: Timer-/Stream-/Rebuild-Inventar (2026-06-10)

Bestandsaufnahme aller periodischen Arbeiten während einer aktiven Fahrt
(`cruise_mode_page.dart` + `cruise_maplibre_map.dart`), Branch `fix/fahr-performance`.

## Periodische Arbeiten während der Fahrt (Solo, ohne Gruppe)

| # | Quelle | Frequenz | Tut was | setState? | Platform-Channel? |
|---|--------|----------|---------|-----------|-------------------|
| 1 | GPS-Stream (geolocator, iOS `bestForNavigation`, distanceFilter 0) | ~1 Hz (iOS-Hardware) | publiziert in `NavigationProgressSocketService` | – | – |
| 2 | `NavigationProgressSocketService._emit` | pro Fix: **bis zu 6 Events** (Original + bis zu 5 Interpolations-Zwischenpunkte, `(dist/2m).clamp(0,5)`) | jedes Event triggert `_onLocationUpdate` — als **synchroner Burst** | – | WebSocket-Broadcast pro Fix (Supabase Realtime) |
| 3 | `_onLocationUpdate` (×6 pro Fix) | ~6 Hz effektiv, burstweise | Smoother-Update, Kamera-Ziel setzen, Window-Match (80 Pkt), Korridor, Progress, Trail-Trim (4 m-Gate), Manöver-Check | **`_safeSetState` auf die GANZE Page**, 90 ms-Throttle → ~11 Hz max; zusätzlich `needsRebuild`-setState | `_carRouteBridge.publishProgress` (3 s-Throttle, SharedPrefs) |
| 4 | **Kamera-Ticker** `_cameraAnimController.repeat()` + `_onCameraAnimationTick` | **60 Hz** (vsync), läuft während Follow-Modus DAUERHAFT — auch im Stillstand (kein Konvergenz-Stop) | kritisch gedämpftes Nachziehen, dann `moveTo()` | – | **`moveCamera` pro Frame** (by design, coalesced via `_camMoveInFlight`) |
| 5 | `onCameraMove` (nativ → Dart, Folge von #4) | **60 Hz** während Fahrt | `_projectMarkers()`: alle Marker lokal projizieren | **setState im Map-State pro Frame** → rebuildet `mb.MapLibreMap`-Widget (Options-Map-Diff/Allokationen) + komplettes Marker-Overlay (Puck + bis zu 50 POI + Ziel + Peers) | – |
| 6 | Map-Widget `didUpdateWidget` (Folge von #3-Page-Rebuild) | ~11 Hz | `_linesSignature` (5 Samples), `_syncActiveRoute`-Sig, `_syncDrivenTrail`-Sig, `_applyRouteGradient` (No-op), `_projectMarkers` | setState (unconditional bei Markern) | `setGeoJsonSource` NUR bei Signatur-Änderung (4 m-/200 m-Gates in der Page) ✓ |
| 7 | `_initialSyncFallback` (Map, 700 ms periodic) | bis zum ersten erfolgreichen Sync | Größen-Probe → `_runFirstSync` | – | `toScreenLocation`-Probe |
| 8 | Sim-Timer (nur Simulation) | 20 Hz (50 ms) | Distanz-Interpolation, ruft `_onLocationUpdate` | über #3 | – |

**Zu #7:** cancelt sauber — sowohl im Tick (`!mounted || _firstFrameSynced → t.cancel()`)
als auch nach Erfolg in `_runFirstSync` (Zeile ~771). ✓ Kein Leak.

## Nur bei aktiver Gruppe (widget.groupId != null)

| Quelle | Frequenz | setState? |
|--------|----------|-----------|
| Peer-Anim-Timer | **20 Hz** (50 ms) | `_safeSetState` auf die GANZE Page sobald sich ein Peer >0,5 m bewegt (zwischen 2 s-Uploads praktisch immer) |
| Positions-Upload | 0,5 Hz (2 s) | – (Netzwerk) |
| Members-Backfill | 5 s | bei Änderung |
| Members-Freshness/Watchdog | 5 s | **ja, wenn irgendein Member Location hat** (unconditional) |
| Route-Backfill | 15 s | bei Änderung |

**Antwort auf die Eingangsfrage:** Der Peer-Animations-Timer läuft NICHT ohne Gruppe —
`_startGroupMembersRecovery` wird nur aus `_bootstrapGroupSession` aufgerufen, und das
ist `widget.groupId != null`-gegatet (initState Z. ~1283).

## Nur während Suche/Preview (nicht beim Fahren)

- `_routeLoadingPhaseTimer` 1 s (Phasen-Text), `_routeSearchExitTimer` (einmalig),
  `_routeDrawAnimationTimer` (Einzeichnen-Animation), `_viewportPoiDebounce` (Gesten-gegatet).
- BackdropFilter-Blurs liegen im Such-Status-Card, Config-Overlay, Completion-Dialog,
  Onboarding-Sheet — **nicht** im aktiven Fahr-Pfad. Im Fahr-Pfad nur boxShadows
  (blurRadius 6–28) in FABs/Banner/Puck.

## setState-Breite (der Kernbefund)

`_safeSetState` = `setState` auf dem State der ~12.700-Zeilen-Page. Während der Fahrt
feuert das ~11 Hz (90 ms-Throttle) und baut JEDES MAL neu:

- `_buildMapWidget()` → neue `CruiseMapLibreMap`-Props: `_buildMapLibreLines()` +
  `_buildMapLibreMarkers()` (Puck-CustomPaint, bis zu 50 POI-Marker-Widgets mit
  Shadows, Ziel-Marker, Peer-Avatare — alles frische Widget-Instanzen)
- `_buildNavigationOverlay()` → Manöver-Banner, FAB-Spalte, Info-Panel, Drive-Control
- Map-seitig löst jeder dieser Rebuilds `didUpdateWidget` aus (Signaturen + Projektion + setState)

Parallel dazu rebuildet der 60-Hz-Pfad (#4→#5) das Map-Widget-Subtree
(Platform-View-Widget + Marker-Overlay) bei jedem Frame.

## Messung

Harness: `lib/main_perf.dart` (FrameTiming-Collector, 10 s-Reports) +
`lib/perf/perf_route_fixture.dart` (echte 108-km-Pool-Route Friedrichshafen) +
`PERF_AUTOPILOT`/`SIM_ENABLED` dart-defines (Auto-Confirm + Sim-Start, kein Tippen nötig).

```
flutter run --profile -d <iphone> -t lib/main_perf.dart \
  --dart-define=PERF_AUTOPILOT=true --dart-define=SIM_ENABLED=true --dart-define=SIM_KMH=70
```

Ergebnisse: siehe `perf_fahr_messung_2026_06_10.md` (Vorher/Nachher).
