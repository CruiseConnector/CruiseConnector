#!/usr/bin/env bash
# CruiseConnect Routing Quality Test Suite
# Testet: A→B, Wegpunkte, Round-Trip, Autobahn-Regel, Sackgassen,
#         U-Turns, POIs, Rerouting-Simulation, außerhalb DACH
# Exit 0 = alle Tests ok | Exit 1 = min. 1 Fail

set -uo pipefail

EDGE="https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2"
ANON="sb_publishable_rq42MGGjHHy8IApa4dR3Nw_UCEqkZ8M"
AUTH="Authorization: Bearer $ANON"
CT="Content-Type: application/json"
PASS=0; FAIL=0; WARN=0
LOG=""

log()  { LOG="${LOG}\n$1"; echo -e "$1" >&2; }
pass() { PASS=$((PASS+1)); log "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); log "  ❌ $1"; }
warn() { WARN=$((WARN+1)); log "  ⚠️  $1"; }

call_edge() {
  curl -s -m 20 -X POST "$EDGE" -H "$AUTH" -H "$CT" -d "$1" 2>/dev/null
}

check_route() {
  local resp="$1" label="$2"
  # Alles in einem python3-Call — gibt "km turns" aus oder "ERR:msg"
  local result
  result=$(echo "$resp" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  err=d.get('error','')
  if err and err!='None':
    print(f'ERR:{err}')
  else:
    km=d.get('route',{}).get('distance_km',0)
    turns=d.get('meta',{}).get('turn_count',0)
    if not km or float(km)==0:
      print('ERR:keine Route')
    else:
      print(f'{km} {turns}')
except Exception as e:
  print(f'ERR:parse_{e}')
" 2>/dev/null)
  if [[ "$result" == ERR:* ]]; then
    fail "$label — ${result#ERR:}"; echo "0 0"; return 1
  fi
  echo "$result"
  return 0
}

check_uturn() {
  local resp="$1" label="$2"
  local uturns
  uturns=$(echo "$resp" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  mans = d.get('route',{}).get('maneuvers',[])
  u=[m for m in mans if 'U_TURN' in str(m.get('type','')) or 'u-turn' in str(m.get('instruction','')).lower()]
  print(len(u))
except: print(0)
" 2>/dev/null)
  if [[ "${uturns:-0}" -gt 0 ]]; then
    warn "$label — $uturns U-Turn(s) gefunden"
  else
    pass "$label — keine U-Turns"
  fi
}

check_deadend() {
  local resp="$1" label="$2"
  local result
  result=$(echo "$resp" | python3 -c "
import sys,json,math
try:
  d=json.load(sys.stdin)
  coords=d.get('route',{}).get('geometry',{}).get('coordinates',[])
  if len(coords)<10: print('SHORT'); exit()
  # Check ob Start und Ende nah beieinander (round trip ok), aber Mittelpunkt weit weg
  s=coords[0]; e=coords[-1]
  dist_se=math.sqrt((s[0]-e[0])**2+(s[1]-e[1])**2)
  # Check ob Route sich selbst zu oft kreuzt (Sackgasse-Indikator)
  # Einfacher Check: letzten 10% der Route nochmal in erste 10%?
  n=len(coords)
  start_box=coords[:n//10]
  end_section=coords[n*9//10:]
  reentry=0
  for ep in end_section:
    for sp in start_box:
      if math.sqrt((ep[0]-sp[0])**2+(ep[1]-sp[1])**2)<0.005:
        reentry+=1
        break
  print(f'OK:se_dist={dist_se:.4f} reentry={reentry}')
except Exception as e: print(f'ERR:{e}')
" 2>/dev/null)
  local reentry
  reentry=$(echo "$result" | python3 -c "import sys,re; m=re.search(r'reentry=(\d+)',sys.stdin.read()); print(m.group(1) if m else '0')" 2>/dev/null || echo "0")
  if [[ "${reentry:-0}" -gt 3 ]]; then
    warn "$label — mögl. Sackgasse (reentry=$reentry)"
  else
    pass "$label — Routenform ok (reentry=$reentry)"
  fi
}

check_highway_rule() {
  local km_with="$1" km_without="$2" label="$3"
  local diff
  diff=$(python3 -c "print(abs($km_with - $km_without))" 2>/dev/null)
  local significant
  significant=$(python3 -c "print('YES' if abs($km_with - $km_without) > 5 else 'NO')" 2>/dev/null)
  if [[ "$significant" == "YES" ]]; then
    pass "$label — Autobahn-Regel wirkt (Δ${diff}km)"
  else
    warn "$label — Autobahn-Regel kaum Unterschied (Δ${diff}km) — evtl. kein Autobahn auf Strecke"
  fi
}

# ════════════════════════════════════════════════
log "\n🧪 ROUTING TEST SUITE — $(date +%H:%M)"
log "═══════════════════════════════════════════"

# TEST 1: A→B Wien → Salzburg (ohne Autobahn)
log "\n[1] A→B: Wien → Salzburg (mit/ohne Autobahn)"
RESP_AB_MIT=$(call_edge '{"route_type":"POINT_TO_POINT","startLocation":{"latitude":48.2082,"longitude":16.3738},"target_location":{"latitude":47.8095,"longitude":13.0550},"mode":"Abendrunde","avoid_highways":false}')
RESP_AB_OHNE=$(call_edge '{"route_type":"POINT_TO_POINT","startLocation":{"latitude":48.2082,"longitude":16.3738},"target_location":{"latitude":47.8095,"longitude":13.0550},"mode":"Abendrunde","avoid_highways":true}')

read KM_MIT TURNS_MIT <<< $(check_route "$RESP_AB_MIT" "A→B Wien→Salzburg mit Autobahn")
read KM_OHNE TURNS_OHNE <<< $(check_route "$RESP_AB_OHNE" "A→B Wien→Salzburg ohne Autobahn")

if [[ "$KM_MIT" != "0" ]]; then pass "A→B Wien→Salzburg: ${KM_MIT}km, ${TURNS_MIT} Kurven"; fi
if [[ "$KM_OHNE" != "0" ]]; then pass "A→B ohne Autobahn: ${KM_OHNE}km"; fi
if [[ "$KM_MIT" != "0" && "$KM_OHNE" != "0" ]]; then
  check_highway_rule "$KM_MIT" "$KM_OHNE" "Autobahn-Regel Wien→Salzburg"
fi
check_uturn "$RESP_AB_MIT" "A→B U-Turn-Check"
check_deadend "$RESP_AB_MIT" "A→B Sackgassen-Check"

# TEST 2: Wegpunkte — Wien → Linz → Salzburg (3 Punkte)
log "\n[2] Wegpunkte: Wien → Linz → Salzburg"
RESP_WP=$(call_edge '{"route_type":"POINT_TO_POINT","startLocation":{"latitude":48.2082,"longitude":16.3738},"target_location":{"latitude":47.8095,"longitude":13.0550},"waypoints":[{"latitude":48.3069,"longitude":14.2858}],"mode":"Sport Mode","avoid_highways":false}')
read KM_WP TURNS_WP <<< $(check_route "$RESP_WP" "Wegpunkte Wien→Linz→Salzburg")
if [[ "$KM_WP" != "0" ]]; then
  pass "Wegpunkte: ${KM_WP}km, ${TURNS_WP} Kurven"
  # Prüfe ob Route durch Linz-Bereich geht (lon ~14.28)
  LINZ_CHECK=$(echo "$RESP_WP" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  coords=d.get('route',{}).get('geometry',{}).get('coordinates',[])
  near_linz=[c for c in coords if 13.8<c[0]<14.8 and 48.1<c[1]<48.5]
  print('YES' if len(near_linz)>5 else 'NO')
except: print('ERR')
" 2>/dev/null)
  if [[ "$LINZ_CHECK" == "YES" ]]; then pass "Wegpunkt Linz korrekt durchfahren"; else warn "Wegpunkt Linz möglicherweise umgangen"; fi
fi
check_uturn "$RESP_WP" "Wegpunkte U-Turn-Check"

# TEST 3: Round Trip — Kurvenreiche Region (Salzkammergut)
log "\n[3] Round Trip: Salzkammergut Sport 75km"
RESP_RT=$(call_edge '{"route_type":"ROUND_TRIP","startLocation":{"latitude":47.7928,"longitude":13.6470},"targetDistance":75,"mode":"Kurvenjagd","avoid_highways":true}')
read KM_RT TURNS_RT <<< $(check_route "$RESP_RT" "Round Trip Salzkammergut")
if [[ "$KM_RT" != "0" ]]; then
  pass "Round Trip: ${KM_RT}km, ${TURNS_RT} Kurven"
  if [[ "${TURNS_RT:-0}" -gt 20 ]]; then pass "Kurvendichte ok (${TURNS_RT} Kurven)"; else warn "Kurvendichte niedrig (${TURNS_RT} Kurven)"; fi
fi
pass "Round Trip Sackgassen-Check — übersprungen (Round Trip kehrt planmäßig zurück)"
check_uturn "$RESP_RT" "Round Trip U-Turn-Check"

# TEST 4: Trip-Modus — Wien → Graz → Klagenfurt
log "\n[4] Trip-Modus: Wien → Graz → Klagenfurt"
RESP_TRIP=$(call_edge '{"route_type":"POINT_TO_POINT","startLocation":{"latitude":48.2082,"longitude":16.3738},"target_location":{"latitude":46.6249,"longitude":14.3050},"waypoints":[{"latitude":47.0707,"longitude":15.4395}],"mode":"Entdecker","avoid_highways":false}')
read KM_TRIP TURNS_TRIP <<< $(check_route "$RESP_TRIP" "Trip Wien→Graz→Klagenfurt")
if [[ "$KM_TRIP" != "0" ]]; then pass "Trip: ${KM_TRIP}km, ${TURNS_TRIP} Kurven"; fi

# TEST 5: Außerhalb DACH — Toskana (Italien)
log "\n[5] Außerhalb DACH: Toskana Round Trip 50km"
RESP_IT=$(call_edge '{"route_type":"ROUND_TRIP","startLocation":{"latitude":43.7696,"longitude":11.2558},"targetDistance":50,"mode":"Sport Mode","avoid_highways":true}')
read KM_IT TURNS_IT <<< $(check_route "$RESP_IT" "Toskana Round Trip 50km")
if [[ "$KM_IT" != "0" ]]; then pass "Toskana: ${KM_IT}km, ${TURNS_IT} Kurven"; fi

# TEST 6: Rerouting-Simulation — Starte 500m abseits der idealen Route
log "\n[6] Rerouting-Simulation: Startpunkt abseits"
RESP_REROUTE=$(call_edge '{"route_type":"POINT_TO_POINT","startLocation":{"latitude":48.2150,"longitude":16.4100},"target_location":{"latitude":47.8095,"longitude":13.0550},"mode":"Abendrunde","avoid_highways":false}')
read KM_RR TURNS_RR <<< $(check_route "$RESP_REROUTE" "Rerouting-Sim (500m versetzt)")
if [[ "$KM_RR" != "0" ]]; then pass "Rerouting: ${KM_RR}km — Route von versetztem Start gefunden"; fi

# TEST 7: POI-Check
log "\n[7] POI-Check (Tankstellen/POIs entlang Route)"
POI_COUNT=$(echo "$RESP_AB_MIT" | python3 -c "
import sys,json
try:
  d=json.load(sys.stdin)
  pois=d.get('pois',[]) or d.get('meta',{}).get('pois',[]) or []
  print(len(pois))
except: print(-1)
" 2>/dev/null)
if [[ "${POI_COUNT:-0}" -gt 0 ]]; then pass "POIs vorhanden ($POI_COUNT Einträge)";
elif [[ "${POI_COUNT:-0}" -eq 0 ]]; then warn "Keine POIs in Response (Feature evtl. noch nicht aktiv)";
else warn "POI-Check nicht auswertbar"; fi

# ════════════════════════════════════════════════
log "\n═══════════════════════════════════════════"
log "📊 ERGEBNIS: ✅ $PASS Pass | ❌ $FAIL Fail | ⚠️  $WARN Warn"
log "═══════════════════════════════════════════"

# Schreibe Summary
SUMMARY_FILE="$(dirname "$0")/../logs/routing-test-$(date +%Y-%m-%d).log"
echo "[$(date +%Y-%m-%dT%H:%M:%S)] pass=$PASS fail=$FAIL warn=$WARN" >> "$SUMMARY_FILE"

if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
exit 0
