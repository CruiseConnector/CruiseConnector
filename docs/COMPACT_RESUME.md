# COMPACT-RESUME — Stand 2026-05-22 02:30

**Diese Datei lesen wenn Auto-Compact passiert ist.**

## 🎯 Wo wir stehen

**Branch:** `graphhopper-dach-stabilize`
**Working dir:** `/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f`
**Production DB:** Supabase project `tlcfaxvvqzobmzwvfnvb`

### Migration GraphHopper komplett

- ✅ Mapbox 15.000-Zeilen Hack → GraphHopper Edge v2 (290 Zeilen)
- ✅ 2 GH-Server auf vucko1@vucko (DACH 8989 + DE 8991) via systemd auto-restart
- ✅ Tailscale Funnels live: `https://vucko.taildddd94.ts.net` + `:8443`
- ✅ Edge v2: `https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2`

### Pool-System komplett

- ✅ **2.182 Routes für 48 DACH-Städte** (source='pool_seed_v2')
- ✅ Pool-Lifecycle: `refresh_pool_route_ratings()` + `decay_pool_rotation_scores()`
- ✅ Wöchentlich-Cron: `dach_weekly_pool_maintenance` (So 23:59 UTC)
- ✅ Demand-Auto-Seeder: `dach_pool_auto_seeder` (*/15 Min) mit dynamic rate (3/10/20/30 jobs/tick)
- ✅ Coverage-Snapshot-Table für Trend-Tracking

### Routing-Modi

- ✅ Round-Trip (25/50/75/100 km × Sport/Kurvenjagd/Abendrunde/Entdecker) — 50/50 Pool/Live coin-flip
- ✅ A→B mit Detour-Levels (0=direkt, 1=klein, 2=mittel, 3=groß) via Sub-Waypoints
- ✅ A→B Stil-Differenzierung via `profileDetourMultiplier` (kurvenjagd 1.4×, scenic 1.15×, abendrunde 0.7×, entdecker 1.0×)
- ✅ Waypoints Backend (Edge `req.waypoints` field) — UI noch alt mit Distanz-Limit
- ✅ Trip-Schema DB: `trips`, `trip_stops`, `trip_segments` + RLS

### Open Tasks (next Heartbeats)

Aus diesem User-Request:
1. **Wegpunkte-UI fix**: alte Matrix-basierte Logik durch Edge-v2 ersetzen, große Distanzen erlauben
2. **Wegpunkte vs Trip Decision-UI**: "einfache Route" oder "Trip planen" auswählen
3. **Trip-Progress Resume**: Homescreen-Card "Trip fortsetzen"
4. **Map-Tile-Caching**: Mapbox-Tiles vorladen damit kein Spinner
5. **Map-Live**: noch flüssigere Bewegung + Heading-Updates (über aktuelle 220ms hinaus)

Vorherige offene Tasks:
- #4 Gruppen-Routen-Teilung (Backend ready via `trips.group_id`, UI fehlt)
- #7 PC2-Setup als GH-Mirror (User macht Montag, Plan in `docs/PC2_SETUP_MONTAG.md`)

## 🔧 Production-State

**GH-Server (vucko1@vucko)**:
- `systemctl status graphhopper_dach.service graphhopper_de.service`
- Beide enabled + active, RestartSec=20

**pg_cron Jobs (laufen alle):**
| jobname | schedule |
|---|---|
| `dach_pool_auto_seeder` | `*/15 * * * *` (alle 15 Min, dynamic rate) |
| `dach_weekly_pool_maintenance` | `59 23 * * 0` (So 23:59 UTC) |
| `weekly-route-pool-curation` | `59 23 * * 0` (legacy) |
| `process_route_search_sessions_every_minute` | `* * * * *` (legacy) |
| `cruise_groups_cleanup` | `0 * * * *` |

**Supabase Secrets:**
- `GRAPHHOPPER_URL=https://vucko.taildddd94.ts.net` (DACH-Server)
- `GRAPHHOPPER_DE_URL=https://vucko.taildddd94.ts.net:8443` (DE-Server)

## 📋 Wichtige Files

### Migrations Production-State
- `20260521_add_25km_bucket.sql` — 25km Pool-Bucket erlaubt
- `20260522001000-033000_*_pool.sql` — 48 City-Seeds
- `20260522020000_pool_lifecycle_system.sql` — refresh_pool_route_ratings + decay
- `20260523010000_trips_schema.sql` — Trip-Modus DB-Schema
- `20260523020000_weekly_pool_maintenance.sql` — pg_cron Sonntag
- `20260523030000_pool_demand_auto_seeder.sql` — Demand-Log + Auto-Seed-Queue
- `20260523040000_pool_auto_seed_dynamic_rate.sql` — Dynamic Rate-Limit

### Scripts
- `scripts/dach_pool_seed.py` — generiert Pool-Routes via Edge v2 mit Quality-Filter (avg_speed≥40 für ≥75km, ≥35 für 25-50km, distance ±18%)
- `scripts/dach_master_cities.txt` — 41 DACH-Master-Städte
- `scripts/dach_seed_all_missing.sh` — batch-seedet alle in master_cities aber nicht in migrations
- `scripts/dach_push_with_retry.sh` — Push mit Internet-Retry + auto migration repair
- `scripts/dach_auto_seed_next.sh` — pickt next un-seeded city
- `scripts/dach_heartbeat_loop.sh` — Background-Monitor (lokal, optional)

### Key Source-Files
- `lib/data/services/route_service.dart` — `generateRoundTrip()` + `generatePointToPoint()`, 50/50 Pool/Live coin-flip
- `lib/data/services/route_pool_service.dart` — Pool-Stil-Match strict (sport↔kurvenjagd, abendrunde↔entdecker)
- `lib/data/services/route_quality_validator.dart` — Block-Loop-Detection + Butterfly-Filter
- `supabase/functions/generate-cruise-route-v2/index.ts` — Edge v2 (624 Zeilen, Sub-Waypoint-A→B, Style-Penalty, Speed-Penalty, 8-Direction-Offset-Fallback)
- `lib/presentation/pages/cruise_mode_page.dart` — Camera-Anim 180/220ms + 0.50/0.60 Prediction-Mix, Source-Badge entfernt

## 🐛 Known Issues / Workarounds

1. **10 Cities failed seeding** wegen Umlauten/Bindestrichen im Filename:
   Tübingen, Nürnberg, Würzburg, Wörgl, Zell-am-See, St-Johann, St-Gallen,
   St-Pölten, Wiener-Neustadt, Bruck-Mur
   → Fix: ASCII-Slug verwenden (Tuebingen, Nuernberg, Wuerzburg, etc.)

2. **Wegpunkte UI ist alt** — Mapbox-Matrix-API basiert, kann keine großen Distanzen.
   → Fix: Edge v2 `waypoints` field nutzen (Backend ready), UI umschreiben.

3. **Mapbox-Tiles laden langsam** — `OfflineMapService.cacheRegionAroundPoint`
   bereits implementiert in `home_page` (Pre-Warm 2s nach Launch), aber
   möglicherweise nicht aggressiv genug.

4. **PC2 wartet auf Montag** — Plan in `docs/PC2_SETUP_MONTAG.md`.

## 🎯 Plan nach Compact

1. **Lese diese Datei** + `docs/MIGRATION_FINAL_REPORT.md`
2. **Verify Production**:
   ```
   SELECT COUNT(*) FROM public.route_pool WHERE source='pool_seed_v2';
   ```
   Erwarte: ≥ 2182
3. **Verify Crons**:
   ```
   SELECT jobname, schedule, active FROM cron.job;
   ```
4. **Continue Tasks** aus diesem User-Request:
   - Wegpunkte UI Decision-Screen
   - Trip-Resume im Homescreen
   - Map-Tile-Performance
   - Map-Live noch flüssiger

## 📞 Commands für Quick-Status

```bash
# DB-Pool-Coverage
psql ... -c "SELECT city_cluster, COUNT(*) FROM route_pool WHERE source='pool_seed_v2' GROUP BY city_cluster;"

# GH-Server-Health
ssh vucko1@vucko 'curl -sf http://localhost:8989/health && curl -sf http://localhost:8991/health'

# Edge-v2 Smoke
curl -X POST "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
  -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d '{"startLocation":{"latitude":48.2082,"longitude":16.3738},"targetDistance":50,"mode":"Sport Mode","route_type":"ROUND_TRIP"}'
```
