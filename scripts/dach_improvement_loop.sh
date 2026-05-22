#!/usr/bin/env bash
# DACH Improvement-Scout Loop — alle 30min Verbesserungs-Vorschläge sammeln.
# Parallel zum Heartbeat-Loop. Schreibt nach logs/improvement-suggestions.log.

set -u

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

echo "[scout-loop-start] $(date +"%Y-%m-%dT%H:%M:%S") pid=$$" >> logs/improvement-loop.log

# Erster Lauf sofort, dann alle 30 Minuten
while true; do
  bash "$ROOT/scripts/dach_improvement_scout.sh" >/dev/null 2>&1
  EXIT_CODE=$?
  TS=$(date +"%Y-%m-%dT%H:%M:%S")
  echo "$TS exit=$EXIT_CODE" >> "$ROOT/logs/improvement-loop.log"
  sleep 1800   # 30 Minuten
done
