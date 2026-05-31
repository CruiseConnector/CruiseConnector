#!/usr/bin/env bash
# DACH-Stabilize watchdog — analysiert heartbeat-loop.log + meldet beide PCs.
# 2026-05-27: PC2-parallel support, tac-Fix für macOS.

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

# Check ob letzter Entry < 3 Min alt
LAST_TS=$(echo "$RECENT" | tail -1 | awk '{print $1}')
LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$LAST_TS" "+%s" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
AGE=$((NOW_EPOCH - LAST_EPOCH))
AGE_MIN=$(( AGE / 60 ))

if [[ "$AGE" -gt 180 ]]; then
  echo "STATUS=loop_dead reason=last_entry_age=${AGE}s pid_check=$(pgrep -f dach_heartbeat_loop | wc -l | xargs)"
  exit 1
fi

# PC1: ok wenn exit=0 oder exit=4 (nur PC2-Problem, PC1 läuft)
OK_COUNT=$(echo "$RECENT" | grep -cE "exit=[04]")
TOTAL_COUNT=$(echo "$RECENT" | wc -l | xargs)

# Letzter Day-Log-Eintrag — PC1 und PC2 Status extrahieren
LAST_LINE=""
PC1_STATUS="?"
PC2_STATUS="?"
PC1_MEM="?"
PC2_MEM="?"
PC2_LOAD="?"
if [[ -f "$DAY_LOG" ]]; then
  LAST_LINE=$(tail -1 "$DAY_LOG" 2>/dev/null)
  PC1_STATUS=$(echo "$LAST_LINE" | grep -oE "PC1=[a-z_]+" | head -1 | cut -d= -f2)
  PC2_STATUS=$(echo "$LAST_LINE" | grep -oE "PC2=[a-z_]+" | head -1 | cut -d= -f2)
  PC1_MEM=$(echo "$LAST_LINE" | grep -oE "pc1mem=[0-9/]+" | cut -d= -f2)
  PC2_MEM=$(echo "$LAST_LINE" | grep -oE "pc2mem=[0-9/]+" | cut -d= -f2)
  PC2_LOAD=$(echo "$LAST_LINE" | grep -oE "pc2load=[0-9,. ]+" | cut -d= -f2 | xargs | cut -d' ' -f1)
fi

# Consecutive fails: tail -r als tac-Ersatz auf macOS
CONSECUTIVE_FAILS=$(tail -5 "$LOOP_LOG" | grep -E "exit=[0-9]" | tail -r 2>/dev/null | \
  awk '/exit=[04]/ {exit} /exit=[1-9]/ {c++} END {print c+0}')

# Output
if [[ "$OK_COUNT" -eq "$TOTAL_COUNT" ]]; then
  echo "STATUS=healthy last_age_min=$AGE_MIN ok=$OK_COUNT/$TOTAL_COUNT PC1=$PC1_STATUS(mem:$PC1_MEM) PC2=$PC2_STATUS(mem:$PC2_MEM load:$PC2_LOAD)"
  if [[ -f "$DAY_LOG" ]]; then
    echo "--- Letzte 3 Runs ---"
    tail -3 "$DAY_LOG" | sed 's/|/!/g'
  fi
  exit 0
fi

if [[ "$CONSECUTIVE_FAILS" -ge 3 ]]; then
  echo "STATUS=down consecutive_fails=$CONSECUTIVE_FAILS PC1=$PC1_STATUS PC2=$PC2_STATUS last=\"$LAST_LINE\""
  exit 2
fi

echo "STATUS=degraded ok=$OK_COUNT/$TOTAL_COUNT consec_fails=$CONSECUTIVE_FAILS PC1=$PC1_STATUS PC2=$PC2_STATUS"
exit 1
