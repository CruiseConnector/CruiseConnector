#!/usr/bin/env bash
# DACH Improvement-Scout ensure — startet dach_improvement_loop falls nicht läuft.
# Idempotent — wird vom Claude-Cron parallel zum Heartbeat aufgerufen.

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOOP_PIDS=$(ps -axo pid,ppid,command | awk '/[d]ach_improvement_loop\.sh$/ {print $1}' | head -10)

if [[ -n "$LOOP_PIDS" ]]; then
  COUNT=$(echo "$LOOP_PIDS" | wc -l | xargs)
  if [[ "$COUNT" -gt 1 ]]; then
    echo "$LOOP_PIDS" | tail -n +2 | xargs kill 2>/dev/null
    echo "DEDUP killed $((COUNT - 1)) extra scout-loops"
  fi
  echo "ALIVE pids=$(echo "$LOOP_PIDS" | head -1)"
  exit 0
fi

nohup bash "$ROOT/scripts/dach_improvement_loop.sh" > /dev/null 2>&1 &
disown
sleep 1
NEW_PID=$(pgrep -f dach_improvement_loop.sh | head -1)
echo "RESTARTED pid=$NEW_PID"
