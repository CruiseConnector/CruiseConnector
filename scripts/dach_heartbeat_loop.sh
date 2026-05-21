#!/usr/bin/env bash
# DACH-Stabilize background loop — jede Minute heartbeat + log.
#
# Läuft in Background als bash-background-process. Aufruf:
#   bash scripts/dach_heartbeat_loop.sh &
# Stop: pkill -f dach_heartbeat_loop
#
# Schreibt in logs/heartbeat-YYYY-MM-DD.log (1 Zeile pro Minute).

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

echo "[loop-start] $(date +"%Y-%m-%dT%H:%M:%S") pid=$$" >> logs/heartbeat-loop.log

while true; do
  bash "$ROOT/scripts/dach_autonomous_heartbeat.sh" --quiet >/dev/null 2>&1
  EXIT_CODE=$?
  TS=$(date +"%Y-%m-%dT%H:%M:%S")
  # exit code → status für später (anomaly detection durch Claude-Cron)
  # 2026-05-21 BUGFIX (vucko): $? referenzierte vorher $(date)-substitution
  # (return=0), nicht das heartbeat-Skript. Fix: in Variable cachen.
  echo "$TS exit=$EXIT_CODE" >> "$ROOT/logs/heartbeat-loop.log"
  sleep 60
done
