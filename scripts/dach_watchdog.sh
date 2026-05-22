#!/usr/bin/env bash
# DACH-Stabilize watchdog — analysiert heartbeat-loop.log + meldet Anomalien.
#
# Wird vom Claude-Cron alle paar Minuten ausgelöst. Schaut sich die letzten
# 5 heartbeats an und entscheidet ob alles ok ist oder ob Eskalation nötig.
#
# Output (1 Zeile, parseable):
#   STATUS=healthy total_recent=N ok=M
#   STATUS=degraded recent_ok=M/N last_failure=...
#   STATUS=down consecutive_fails=K last_state=...
#   STATUS=loop_dead reason=no_recent_entries  (loop scheint nicht zu laufen)

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOOP_LOG="$ROOT/logs/heartbeat-loop.log"
DAY_LOG="$ROOT/logs/heartbeat-$(date +%Y-%m-%d).log"

if [[ ! -f "$LOOP_LOG" ]]; then
  echo "STATUS=loop_dead reason=no_loop_log"
  exit 1
fi

# Letzte 5 Loop-Entries
RECENT=$(tail -5 "$LOOP_LOG" | grep -E "exit=[0-9]")
if [[ -z "$RECENT" ]]; then
  echo "STATUS=loop_dead reason=no_recent_entries"
  exit 1
fi

# Check ob letzter Entry < 3 Min alt (loop läuft noch)
LAST_TS=$(echo "$RECENT" | tail -1 | awk '{print $1}')
LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$LAST_TS" "+%s" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
AGE=$((NOW_EPOCH - LAST_EPOCH))

if [[ "$AGE" -gt 180 ]]; then
  echo "STATUS=loop_dead reason=last_entry_age=${AGE}s pid_check=$(pgrep -f dach_heartbeat_loop | wc -l | xargs)"
  exit 1
fi

OK_COUNT=$(echo "$RECENT" | grep -c "exit=0")
TOTAL_COUNT=$(echo "$RECENT" | wc -l | xargs)

# Tag-Log letzte 3 zeigen für details
LAST_DETAILS=""
if [[ -f "$DAY_LOG" ]]; then
  LAST_DETAILS=$(tail -1 "$DAY_LOG" 2>/dev/null | sed 's/|/!/g')
fi

if [[ "$OK_COUNT" -eq "$TOTAL_COUNT" ]]; then
  echo "STATUS=healthy total_recent=$TOTAL_COUNT ok=$OK_COUNT last=\"$LAST_DETAILS\""
  # 2026-05-23 (vucko): Letzte 3 GH-smoke-results auch zeigen damit
  # User trend sieht statt nur "ok".
  if [[ -f "$DAY_LOG" ]]; then
    echo "--- Last 3 smoke-runs ---"
    tail -3 "$DAY_LOG" | sed 's/|/!/g'
  fi
  exit 0
fi

CONSECUTIVE_FAILS=$(echo "$RECENT" | tac | awk '/exit=0/ {exit} /exit=[1-9]/ {c++} END {print c+0}')

if [[ "$CONSECUTIVE_FAILS" -ge 3 ]]; then
  echo "STATUS=down consecutive_fails=$CONSECUTIVE_FAILS total_recent=$TOTAL_COUNT ok=$OK_COUNT last=\"$LAST_DETAILS\""
  exit 2
fi

echo "STATUS=degraded recent_ok=$OK_COUNT/$TOTAL_COUNT consecutive_fails=$CONSECUTIVE_FAILS last=\"$LAST_DETAILS\""
exit 1
