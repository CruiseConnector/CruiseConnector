#!/usr/bin/env bash
# DACH-Stabilize autonomous heartbeat (vucko 2026-05-21, PC2-parallel 2026-05-27).
#
# Prüft PC1 (vucko1@vucko) + PC2 (vucko2@100.64.27.108) ZEITGLEICH parallel.
# Immer beide im Report — egal ob ok, importing, down oder unreachable.
#
# Exit-Codes:
#   0 = alles healthy (PC1 ok, PC2 ok oder importing)
#   1 = PC1 Server down
#   2 = Edge-Smoke-Test rejected
#   3 = PC1 SSH nicht erreichbar
#   4 = PC2 down (nicht mehr importing, unerwartet)
#
# Usage: bash scripts/dach_autonomous_heartbeat.sh [--quiet]

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/heartbeat-$(date +%Y-%m-%d).log"
QUIET="${1:-}"
NOW=$(date +"%Y-%m-%dT%H:%M:%S")

log_line() {
  echo "$1" >> "$LOG_FILE"
  [[ "$QUIET" != "--quiet" ]] && echo "$1"
}

# ─── Temporäre Files für parallele Ausgaben ──────────────────────────────────
TMP_PC1=$(mktemp)
TMP_PC2=$(mktemp)
trap "rm -f $TMP_PC1 $TMP_PC2" EXIT

# ─── PC1 SSH-Check (Background) ──────────────────────────────────────────────
(
  OUT=$(ssh -o ConnectTimeout=8 -o BatchMode=yes vucko1@vucko \
    'h1=$(curl -sf -m 3 http://localhost:8989/health 2>/dev/null || echo FAIL); \
     h2=$(curl -sf -m 3 http://localhost:8991/health 2>/dev/null || echo FAIL); \
     fn=$(tailscale funnel status 2>&1 | grep -c "Funnel on" || echo 0); \
     mem=$(free -m | awk "/Speicher|Mem/ {print \$3\"/\"\$2}"); \
     load=$(uptime | awk -F"load average:" "{print \$2}" | xargs); \
     echo "$h1#$h2#$fn#$mem#$load"' 2>/dev/null)
  echo "$OUT" > "$TMP_PC1"
) &
PID_PC1=$!

# ─── PC2 SSH-Check (Background) ──────────────────────────────────────────────
(
  OUT=$(ssh -o ConnectTimeout=8 -o BatchMode=yes vucko2@100.64.27.108 \
    'h=$(curl -sf -m 5 http://localhost:8989/health 2>/dev/null || echo FAIL); \
     mem=$(free -m | awk "/Speicher|Mem/ {print \$3\"/\"\$2}"); \
     load=$(uptime | awk -F"load average:" "{print \$2}" | xargs); \
     if [[ "$h" == "FAIL" ]]; then \
       imp=$(docker logs gh-eu --tail 5 2>/dev/null | grep -c "pass[12]\|creating graph\|Finished\|starting server\|PrepareRouting\|subnetwork\|LocationIndex\|StorableProperties\|osm_warnings" || echo 0); \
       [[ "$imp" -gt 0 ]] && h="IMPORTING"; \
     fi; \
     echo "$h#$mem#$load"' 2>/dev/null)
  echo "$OUT" > "$TMP_PC2"
) &
PID_PC2=$!

# ─── Auf beide warten ────────────────────────────────────────────────────────
wait $PID_PC1
wait $PID_PC2

# ─── PC1 parsen ──────────────────────────────────────────────────────────────
PC1_RAW=$(cat "$TMP_PC1")
PC1_STATE="ssh_unreachable"
PC1_MEM="?/?"
PC1_LOAD="?"
PC1_8989="FAIL"
PC1_8991="FAIL"

if [[ -n "$PC1_RAW" ]]; then
  IFS='#' read -r PC1_8989 PC1_8991 PC1_FUNNEL PC1_MEM PC1_LOAD <<< "$PC1_RAW"
  if [[ "$PC1_8989" == "OK" && "$PC1_8991" == "OK" ]]; then
    PC1_STATE="ok"
  elif [[ "$PC1_8989" != "OK" ]]; then
    PC1_STATE="dach_down"
  elif [[ "$PC1_8991" != "OK" ]]; then
    PC1_STATE="de_down"
  fi
fi

# ─── PC2 parsen ──────────────────────────────────────────────────────────────
PC2_RAW=$(cat "$TMP_PC2")
PC2_STATE="ssh_unreachable"
PC2_MEM="?/?"
PC2_LOAD="?"

if [[ -n "$PC2_RAW" ]]; then
  IFS='#' read -r PC2_H PC2_MEM PC2_LOAD <<< "$PC2_RAW"
  case "$PC2_H" in
    OK)         PC2_STATE="ok" ;;
    IMPORTING)  PC2_STATE="importing" ;;
    *)          PC2_STATE="down" ;;
  esac
fi

# ─── PC1 kritischer Fehler → sofort loggen + exit ────────────────────────────
if [[ "$PC1_STATE" == "ssh_unreachable" ]]; then
  log_line "[$NOW] PC1=ssh_unreachable | PC2=$PC2_STATE pc2mem=$PC2_MEM pc2load=$PC2_LOAD | exit=3"
  exit 3
fi

if [[ "$PC1_STATE" != "ok" ]]; then
  log_line "[$NOW] PC1=$PC1_STATE pc1mem=$PC1_MEM pc1load=$PC1_LOAD | PC2=$PC2_STATE pc2mem=$PC2_MEM pc2load=$PC2_LOAD | exit=1"
  exit 1
fi

# ─── Edge-Smoke-Test ─────────────────────────────────────────────────────────
ANON=$(grep -A1 supabaseAnonKey lib/config/secrets.dart | tail -1 \
  | sed "s/.*'\([^']*\)'.*/\1/")
SMOKE=$(curl -s -m 12 -X POST \
  "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
  -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
  -d '{"startLocation":{"latitude":48.2082,"longitude":16.3738},"targetDistance":50,"mode":"Sport Mode","route_type":"ROUND_TRIP","avoid_highways":false}' \
  | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  if 'error' in d:
    print(f'ERR:{d[\"error\"]}')
  elif d.get('route'):
    km  = d['route'].get('distance_km', '?')
    dur = d['route'].get('duration', 0)
    trn = d.get('meta', {}).get('turn_count', '?')
    pen = d.get('meta', {}).get('style_penalty', '?')
    print(f'OK:km={km}|dur_s={dur}|turns={trn}|pen={pen}')
  else:
    print('ERR:unknown_response')
except Exception as e:
  print(f'ERR:parse_{e}')
" 2>/dev/null)

# ─── Finale Log-Zeile — IMMER beide PCs ──────────────────────────────────────
EXIT_CODE=0
[[ "$SMOKE" == ERR:* ]] && EXIT_CODE=2
[[ "$PC2_STATE" == "down" ]] && EXIT_CODE=4

log_line "[$NOW] PC1=ok|smoke=$SMOKE|pc1mem=$PC1_MEM|pc1load=$PC1_LOAD PC2=$PC2_STATE|pc2mem=$PC2_MEM|pc2load=$PC2_LOAD | exit=$EXIT_CODE"
exit $EXIT_CODE
