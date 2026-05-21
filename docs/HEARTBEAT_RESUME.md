# Heartbeat-Resume nach Compact

**Wenn du diese Datei liest, ist die letzte Session-Memory verloren.**
Hier ist alles was du brauchst um den Heartbeat-Loop nahtlos fortzusetzen.

## Was läuft (Stand 2026-05-21, DE-Tunnel LIVE)

**Branch:** `graphhopper-dach-stabilize`

**Setup auf vucko1@vucko** (Tailscale-IP 100.65.155.7):
- Port **8989**: GraphHopper mit AT+LI+CH+BW-clipped (1.7 GB merged). Tunnel: `https://vucko.taildddd94.ts.net`
- Port **8991**: GraphHopper mit germany-latest.osm.pbf. Tunnel: `https://vucko.taildddd94.ts.net:8443`
- Memory-Verbrauch ~6 GB / 15 GB. Beide Server stabil.

**Supabase Edge:**
- `generate-cruise-route-v2` deployed mit lat-basierter Server-Wahl + 5-seed Best-of-N parallel.
- Secret `GRAPHHOPPER_URL = https://vucko.taildddd94.ts.net` gesetzt.
- Secret `GRAPHHOPPER_DE_URL = https://vucko.taildddd94.ts.net:8443` gesetzt ✓.

**Flutter:**
- `lib/data/services/route_service.dart` Konstante `edgeFunction = 'generate-cruise-route-v2'` aktiv. Rollback durch Zurückstellen auf `'generate-cruise-route'`.

**E2E DACH-Sweep verifiziert (15/18 ≈ 83%):**
- ✓ Friedrichshafen, Wien, Stuttgart, Zürich, München, Salzburg, Klagenfurt
- ✓ Vaduz, Lugano, Graz, Linz, Heilbronn, Feldkirch, Bern, Mannheim
- ⚠ Bregenz -24% (alpine reachable-area), Innsbruck -17% (alpine Bergtal),
  Basel +23% (GH-Round-Trip-Variance, kein systemisches Issue)

## Autonomous Monitoring (seit 2026-05-21)

**Background-Loop** läuft als nohup-Process unter PPID 1:
```bash
ps -axo pid,ppid,command | awk '/[d]ach_heartbeat_loop\.sh$/'
```

**Bei jedem Wakeup oder neuer Session zuerst:**
```bash
bash scripts/dach_loop_ensure.sh   # Loop neu starten falls down (idempotent)
bash scripts/dach_watchdog.sh      # Last-5-Heartbeats Analyse
```

**Logs:**
- `logs/heartbeat-loop.log` — 1 Zeile pro Minute (`timestamp exit=N`)
- `logs/heartbeat-YYYY-MM-DD.log` — detaillierter Status (SSH + Edge-Smoke)

**Manueller Heartbeat-Befehl (one-shot):**
```bash
bash scripts/dach_autonomous_heartbeat.sh
```

Erwartete OK-Antwort: `STATE=ok|smoke=OK:km=49.48|dur_s=3763|turns=58|pen=0`

## Was zu tun ist je nach Heartbeat-Befund

| Befund | Aktion |
|---|---|
| **Beide /health OK + beide Funnels** | Healthy state. ScheduleWakeup 1800s. |
| **SSH-Timeout / PC offline** | ScheduleWakeup 900s. User-Mac/Tailscale könnte gerade Probleme haben. |
| **Server 8989 down** | Restart per SSH: `cd ~/graphhopper/config && (nohup java -Xmx10g -Xms2g -server -jar ~/graphhopper/bin/graphhopper-web.jar server config.yml > ~/graphhopper/gh.log 2>&1 < /dev/null &)` |
| **Server 8991 down** | Restart per SSH: `cd ~/graphhopper/config && (nohup java -Xmx5g -Xms1g -server -jar ~/graphhopper/bin/graphhopper-web.jar server config-de.yml > ~/graphhopper/gh-de.log 2>&1 < /dev/null &)` |
| **Funnel-Status zeigt nur einen Port** | Anderen reaktivieren: `sudo tailscale funnel --bg --https=443 http://localhost:8989` bzw `--https=8443 http://localhost:8991`. Erfordert User-sudo. |
| **Friedrichshafen-Test fail** | Edge-Logs prüfen: `supabase functions logs generate-cruise-route-v2 --project-ref tlcfaxvvqzobmzwvfnvb`. Secret verifizieren: `supabase secrets list --project-ref tlcfaxvvqzobmzwvfnvb`. |

## Wenn DE-Tunnel-URL erkennbar wird

```bash
# Den genauen Pfad aus 'tailscale funnel status' lesen, z.B. https://vucko.taildddd94.ts.net:8443
DE_URL="<ausgelesene URL>"
supabase secrets set --project-ref tlcfaxvvqzobmzwvfnvb GRAPHHOPPER_DE_URL="$DE_URL"
supabase functions deploy generate-cruise-route-v2 --project-ref tlcfaxvvqzobmzwvfnvb --no-verify-jwt

# Verifiziere Friedrichshafen-Test (lat 47.6552, lng 9.4806)
SUPABASE_ANON=$(grep -o "supabaseAnonKey = '[^']*'" lib/config/secrets.dart | sed "s/supabaseAnonKey = '//;s/'//")
curl -s -X POST "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
  -H "Authorization: Bearer $SUPABASE_ANON" -H "Content-Type: application/json" \
  -d '{"startLocation":{"latitude":47.6552,"longitude":9.4806},"targetDistance":50,"mode":"Sport Mode","route_type":"ROUND_TRIP","avoid_highways":false}' \
  | python3 -m json.tool | head -20
```

Bei Erfolg → Task 14 + 18 auf completed setzen, User benachrichtigen, Heartbeat-Intervall auf 1800s.

## ScheduleWakeup-Standard-Prompt

```
DACH-Stabilize heartbeat. SSH zu vucko1@vucko: beide /health (8989+8991) + funnel status.
1) PC offline → wakeup 300s. 2) GH down → restart. 3) Funnel zeigt DE-URL → secret set + redeploy + test Friedrichshafen. 4) Sonst → 1800s wakeup. 
Branch graphhopper-dach-stabilize. Falls Compact: docs/HEARTBEAT_RESUME.md ist die Wahrheit.
```

## Direkt-Test-URLs

- DACH-Health: `curl -sf https://vucko.taildddd94.ts.net/health` (sollte `{"status":"OK"}`)
- Edge v2: `https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2`
- Edge v1 (Rollback): `https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route`

## Offene Tasks (Stand)

| # | Status | Was |
|---|---|---|
| 9 | pending | Alten 15K-Zeilen Mapbox-Hack löschen — erst nach App-Live-Test im Simulator |
| 10 | pending | Endbericht: Migration-Verdict + Demo-readiness |
| 14 | ✓ completed | DACH Vollabdeckung — DE-Tunnel live, Friedrichshafen verifiziert |
| 17 | ✓ completed | systemd-Units installed + enabled + active (2026-05-21 14:03:50) — Auto-Restart aktiv |
| 18 | ✓ completed | DE-Server Tunnel-Exposure — beide Funnels aktiv |
| 19 | ✓ completed | Stil-Differenzierung — Runtime-Overlay (Wien: Kurvenjagd +24% turns) |
| 20 | ✓ completed | Pool-Stil-Mismatch — strict cluster (sport↔kurvenjagd \| abendrunde↔entdecker) |
| 21 | ✓ completed | Endless-Loop-Guard — 30s wall-clock cap + settingsChanged reset |
| 22 | ✓ completed | Live-Diversity — 8 Seeds bei force_fresh oder previousFingerprints |
| 23 | wartend | Live-First Policy — User regelt Pool/Live-Mix später separat |
| 24 | ✓ completed | Duration-Bug CRITICAL — Edge schickte ms statt s (1029h-Fehler behoben) |
| 25 | ✓ completed | MAPBOX_RESCUE-Label — umbenannt zu `emergency_fallback` |
| 26 | ✓ completed | 25km Rundkurs — UI-Option + Live-Pfad (Pool DB hat noch keine 25er) |
| 27 | ✓ completed | Sport-Style-Penalty — turn-density Score 1.0 t/km für Sport, 1.4 für Kurvenjagd |
| 28 | ✓ completed | Butterfly-Shape-Filter — style-agnostic spurArmCount≥2 + foldedArea>50 |
| **Autonomous Loop** | ✓ live | Background-Loop + Watchdog-Cron alle 3 Min (vucko Wunsch) |
| **Endbericht** | ✓ done | docs/MIGRATION_FINAL_REPORT.md — Verdict GO |
| **Mapbox-Löschung** | wartend | docs/MAPBOX_DELETION_INVENTORY.md prep, nur nach User-OK |
| **systemd-Units** | drafted | docs/systemd_*.service + SYSTEMD_INSTALL.md — User-sudo nötig |
| **Tuning** | accepted | Bregenz/Innsbruck/Basel als known-Outlier (alpine reachable-area + GH-Variance) |

## Architektur-Snapshot

```
[Flutter App] → [Supabase Edge generate-cruise-route-v2]
                  │
                  ├── primary lat∈AT/CH/LI/BW≥48.3 → https://vucko.taildddd94.ts.net (Port 8989)
                  │                                  → GH mit at-li-ch-bwclip-merged.osm.pbf
                  │
                  └── primary lat∈DE-rest → GRAPHHOPPER_DE_URL (Port 8991, kein Tunnel yet)
                                            → GH mit germany-latest.osm.pbf

Distance-Compensation (per Region):
  alpine 0.90 (Vorarlberg/Tirol/CH-Alpen/LI)
  alpenanrand 1.00 (Allgäu/Salzburg)
  flatland 1.00 (Wien/Zürich/Bern/Linz/BW/DE-rest)

Seed-Strategy: 5 parallele GH-Calls, Best-of-N nach Delta zum Target.
Force-Fresh-Variant: Timestamp-basierte Seeds für Search-Again-Diversity.
```
