#!/usr/bin/env bash
# DACH Improvement-Scout watchdog — zeigt letzten Scout-Run + Top-5 Vorschläge.

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
LOG="$ROOT/logs/improvement-suggestions.log"

if [[ ! -f "$LOG" ]]; then
  echo "STATUS=no_log"
  exit 0
fi

LAST_RUN=$(grep -E "scout-run|scout-done" "$LOG" | tail -2 | head -1)
CRIT_COUNT=$(tail -100 "$LOG" | grep -c "\[CRIT\]" 2>/dev/null; true)
WARN_COUNT=$(tail -100 "$LOG" | grep -c "\[WARN\]" 2>/dev/null; true)
INFO_COUNT=$(tail -100 "$LOG" | grep -c "\[INFO\]" 2>/dev/null; true)
CRIT_COUNT=${CRIT_COUNT:-0}
WARN_COUNT=${WARN_COUNT:-0}
INFO_COUNT=${INFO_COUNT:-0}

STATUS="healthy"
if [[ "$CRIT_COUNT" -gt 0 ]]; then STATUS="needs_attention"; fi

echo "STATUS=$STATUS last_run=\"$LAST_RUN\" crit=$CRIT_COUNT warn=$WARN_COUNT info=$INFO_COUNT"
echo "--- Top 5 letzte Vorschläge ---"
grep -E "\[CRIT\]|\[WARN\]|\[INFO\]" "$LOG" | tail -5
