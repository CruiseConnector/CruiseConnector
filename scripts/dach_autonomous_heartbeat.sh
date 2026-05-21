#!/usr/bin/env bash
# DACH-Stabilize autonomous heartbeat (vucko 2026-05-21).
#
# Wird vom Claude-Cron jede Minute ausgelöst. Prüft beide GH-Server +
# Funnel-Tunnels + ein Edge-Smoke-Test. Schreibt einen kompakten Status-
# Bericht in logs/heartbeat-YYYY-MM-DD.log, einmal pro Run.
#
# Exit-Codes:
#   0 = alles healthy
#   1 = irgend ein Server/Tunnel down
#   2 = Edge-Smoke-Test rejected (no_route oder timeout)
#   3 = SSH zu vucko1@vucko nicht erreichbar
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
  local line="$1"
  echo "$line" >> "$LOG_FILE"
  if [[ "$QUIET" != "--quiet" ]]; then
    echo "$line"
  fi
}

# 1) SSH + beide /health + funnel — single-line pipe-separated output
SSH_OUTPUT=$(ssh -o ConnectTimeout=8 -o BatchMode=yes vucko1@vucko \
  'h1=$(curl -sf -m 3 http://localhost:8989/health 2>/dev/null || echo FAIL); \
   h2=$(curl -sf -m 3 http://localhost:8991/health 2>/dev/null || echo FAIL); \
   fn=$(tailscale funnel status 2>&1 | grep -c "Funnel on" || echo 0); \
   mem=$(free -m | awk "/Speicher|Mem/ {print \$3\"/\"\$2}"); \
   load=$(uptime | awk -F"load average:" "{print \$2}" | xargs); \
   echo "$h1#$h2#$fn#$mem#$load"' 2>/dev/null)

if [[ -z "$SSH_OUTPUT" ]]; then
  log_line "[$NOW] STATE=ssh_unreachable | exit=3"
  exit 3
fi

# Parse hash-separated output
IFS='#' read -r H8989 H8991 FUNNEL_LINES MEM LOAD <<< "$SSH_OUTPUT"

SERVER_STATE="ok"
if [[ "$H8989" != "OK" ]]; then SERVER_STATE="dach_down"; fi
if [[ "$H8991" != "OK" ]]; then SERVER_STATE="${SERVER_STATE}_de_down"; fi
if [[ "$FUNNEL_LINES" -lt 1 ]]; then SERVER_STATE="${SERVER_STATE}_funnel_off"; fi

if [[ "$SERVER_STATE" != "ok" ]]; then
  log_line "[$NOW] STATE=$SERVER_STATE | mem=$MEM load=$LOAD | exit=1"
  exit 1
fi

# 2) Edge-Smoke-Test (Wien Sport 50km)
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
    km = d['route'].get('distance_km', '?')
    dur_s = d['route'].get('duration', 0)
    turns = d.get('meta', {}).get('turn_count', '?')
    pen = d.get('meta', {}).get('style_penalty', '?')
    print(f'OK:km={km}|dur_s={dur_s}|turns={turns}|pen={pen}')
  else:
    print('ERR:unknown_response')
except Exception as e:
  print(f'ERR:parse_{e}')
" 2>/dev/null)

if [[ "$SMOKE" == ERR:* ]]; then
  log_line "[$NOW] STATE=ok|smoke=$SMOKE | mem=$MEM load=$LOAD | exit=2"
  exit 2
fi

log_line "[$NOW] STATE=ok|smoke=$SMOKE | mem=$MEM load=$LOAD | exit=0"
exit 0
