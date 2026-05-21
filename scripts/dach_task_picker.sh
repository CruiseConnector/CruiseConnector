#!/usr/bin/env bash
# DACH-Stabilize task-picker — wählt die nächste autonom-bearbeitbare Task aus.
#
# Aufruf vom task-worker Cron (alle 15 Min). Schreibt 1 Zeile pro Run:
#   logs/task-worker.log
#
# Output (1 Zeile auf stdout):
#   NEXT=<task-id>|<short-desc>
#   NONE=all_blocked  (alle pending tasks brauchen User-Action)
#   NONE=all_done     (keine pending tasks)
#
# Tasks die NICHT autonom gemacht werden können:
#   #9  Mapbox-Code löschen — User-Approval nach App-Test
#   #23 Live-First Policy — User-Regeln stehen aus
# Diese werden geskipped.

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG="$ROOT/logs/task-worker.log"
mkdir -p "$(dirname "$LOG")"
NOW=$(date +"%Y-%m-%dT%H:%M:%S")

# Markdown-Datei mit Task-Definitionen (autonom-bearbeitbar):
# Format: TASK <id>:<short-desc>:<file-pattern-hint>
AUTONOMOUS_TASKS="$ROOT/scripts/dach_task_queue.txt"

if [[ ! -f "$AUTONOMOUS_TASKS" ]]; then
  echo "NONE=no_queue_file"
  echo "[$NOW] NONE=no_queue_file" >> "$LOG"
  exit 0
fi

# Lese erste nicht-erledigte (Zeile ohne führendes "DONE:")
NEXT=$(grep -v "^#" "$AUTONOMOUS_TASKS" | grep -v "^DONE:" | grep -v "^$" | head -1)

if [[ -z "$NEXT" ]]; then
  echo "NONE=all_done"
  echo "[$NOW] NONE=all_done" >> "$LOG"
  exit 0
fi

echo "NEXT=$NEXT"
echo "[$NOW] PICKED $NEXT" >> "$LOG"
