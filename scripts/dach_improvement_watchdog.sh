#!/usr/bin/env bash
# DACH Improvement-Scout watchdog — zeigt immer einen kompakten Bericht.

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
LOG="$ROOT/logs/improvement-suggestions.log"
LOOP_LOG="$ROOT/logs/improvement-loop.log"

if [[ ! -f "$LOG" ]]; then
  echo "STATUS=no_log reason=scout_never_ran"
  exit 0
fi

# Letzter Scout-Run
LAST_RUN=$(grep "scout-run" "$LOG" | tail -1)
LAST_DONE=$(grep "scout-done" "$LOG" | tail -1)

# Counts aus letzten 100 Zeilen
TAIL_CONTENT=$(tail -100 "$LOG")
CRIT_COUNT=$(echo "$TAIL_CONTENT" | grep -c "\[CRIT\]" 2>/dev/null; true)
WARN_COUNT=$(echo "$TAIL_CONTENT" | grep -c "\[WARN\]" 2>/dev/null; true)
INFO_COUNT=$(echo "$TAIL_CONTENT" | grep -c "\[INFO\]" 2>/dev/null; true)
CRIT_COUNT=${CRIT_COUNT:-0}
WARN_COUNT=${WARN_COUNT:-0}
INFO_COUNT=${INFO_COUNT:-0}

# Alter des letzten Runs
if [[ -n "$LAST_RUN" ]]; then
  LAST_TS=$(echo "$LAST_RUN" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}" | head -1)
  LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$LAST_TS" "+%s" 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  AGE_MIN=$(( (NOW_EPOCH - LAST_EPOCH) / 60 ))
else
  AGE_MIN=999
fi

STATUS="healthy"
if [[ "$CRIT_COUNT" -gt 0 ]]; then STATUS="needs_attention"; fi
if [[ "$AGE_MIN" -gt 35 ]]; then STATUS="loop_lag"; fi

echo "STATUS=$STATUS last_age_min=$AGE_MIN crit=$CRIT_COUNT warn=$WARN_COUNT info=$INFO_COUNT"

# Loop-PID + Uptime
PID=$(pgrep -f dach_improvement_loop.sh | head -1)
if [[ -n "$PID" ]]; then
  UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | xargs)
  echo "Loop pid=$PID uptime=$UPTIME"
fi

# Bei needs_attention oder loop_lag → CRITs zeigen
if [[ "$CRIT_COUNT" -gt 0 ]]; then
  echo "--- CRIT/WARN Vorschläge ---"
  echo "$TAIL_CONTENT" | grep -E "\[CRIT\]|\[WARN\]" | tail -5
fi

# IMMER: Top 5 zuletzt emittierte Vorschläge
echo "--- Letzte 5 Vorschläge ---"
grep -E "\[CRIT\]|\[WARN\]|\[INFO\]" "$LOG" | tail -5

# IMMER: Loop-Log Snapshot
echo "--- Loop-Log letzte 3 ---"
tail -3 "$LOOP_LOG" 2>/dev/null
