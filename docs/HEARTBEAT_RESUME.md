# Heartbeat-Resume nach Compact

**Wenn du diese Datei liest, ist die letzte Session-Memory verloren.**
Hier ist alles was du brauchst um den Heartbeat-Loop nahtlos fortzusetzen.

## Was läuft (Stand 2026-05-21 ~02:38)

**Branch:** `graphhopper-dach-stabilize`

**Setup auf vucko1@vucko** (Tailscale-IP 100.65.155.7):
- Port **8989**: GraphHopper mit AT+LI+CH+BW-clipped (1.7 GB merged). Tunnel aktiv: `https://vucko.taildddd94.ts.net`
- Port **8991**: GraphHopper mit germany-latest.osm.pbf. **Kein Tunnel** (User-sudo ausstehend).
- Memory-Verbrauch ~6 GB / 15 GB. Beide Server stabil seit ~2 h.

**Supabase Edge:**
- `generate-cruise-route-v2` deployed mit lat-basierter Server-Wahl + 5-seed Best-of-N parallel.
- Secret `GRAPHHOPPER_URL = https://vucko.taildddd94.ts.net` gesetzt.
- Secret `GRAPHHOPPER_DE_URL` **noch nicht gesetzt** — wartet auf zweiten Tunnel.

**Flutter:**
- `lib/data/services/route_service.dart` Konstante `edgeFunction = 'generate-cruise-route-v2'` aktiv. Rollback durch Zurückstellen auf `'generate-cruise-route'`.

## Heartbeat-Befehl (vor jedem Wakeup-Reply)

```bash
ssh -o ConnectTimeout=15 vucko1@vucko 'curl -sf -m 3 http://localhost:8989/health; echo; curl -sf -m 3 http://localhost:8991/health; echo; tailscale funnel status 2>&1 | head -8; free -h | head -2'
```

Erwartete OK-Antwort: zweimal `OK`, Funnel-Liste, Memory ≤ 8 GB used.

## Was zu tun ist je nach Heartbeat-Befund

| Befund | Aktion |
|---|---|
| **SSH-Timeout / PC offline** | Nichts tun. ScheduleWakeup 300s. User-Mac/Tailscale könnte gerade Probleme haben. |
| **Server 8989 down** | Restart per SSH: `cd ~/graphhopper/config && (nohup java -Xmx10g -Xms2g -server -jar ~/graphhopper/bin/graphhopper-web.jar server config.yml > ~/graphhopper/gh.log 2>&1 < /dev/null &)` |
| **Server 8991 down** | Restart per SSH: `cd ~/graphhopper/config && (nohup java -Xmx5g -Xms1g -server -jar ~/graphhopper/bin/graphhopper-web.jar server config-de.yml > ~/graphhopper/gh-de.log 2>&1 < /dev/null &)` |
| **Funnel zeigt nur 8989** | User-Tunnel-sudo noch offen. ScheduleWakeup 1800s, warten. |
| **Funnel zeigt 8991 (oder /de path)** | **Action:** Secret setzen + redeploy (siehe unten). |

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
| 9 | pending | Alten 15K-Zeilen Mapbox-Hack löschen — erst nach erfolgreichem App-Live-Test |
| 10 | pending | Endbericht |
| 14 | in_progress | DE-Side-Server — Server läuft, Tunnel ausstehend |
| 17 | pending | systemd-Unit für GH-Auto-Restart |
| 18 | pending | DE-Server Tunnel-Exposure (User-sudo) |

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
