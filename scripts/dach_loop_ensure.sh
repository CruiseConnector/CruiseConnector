#!/usr/bin/env bash
# DACH-Stabilize loop-ensure — startet dach_heartbeat_loop falls nicht läuft.
# Idempotent: keine Doppel-Loops.
#
# Aufruf vom Claude-Cron + manuell wenn nötig.

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOOP_PIDS=$(pgrep -f dach_heartbeat_loop.sh 2>/dev/null | head -10)

if [[ -n "$LOOP_PIDS" ]]; then
  COUNT=$(echo "$LOOP_PIDS" | wc -l | xargs)
  # Wenn mehrere Loops laufen — alle ausser dem ersten killen
  if [[ "$COUNT" -gt 1 ]]; then
    echo "$LOOP_PIDS" | tail -n +2 | xargs kill 2>/dev/null
    echo "DEDUP killed $((COUNT - 1)) extra loops"
  fi
  echo "ALIVE pids=$(echo "$LOOP_PIDS" | head -1)"
  exit 0
fi

# Kein Loop läuft — neu starten
nohup bash "$ROOT/scripts/dach_heartbeat_loop.sh" > /dev/null 2>&1 &
disown
sleep 1
NEW_PID=$(pgrep -f dach_heartbeat_loop.sh | head -1)
echo "RESTARTED pid=$NEW_PID"
