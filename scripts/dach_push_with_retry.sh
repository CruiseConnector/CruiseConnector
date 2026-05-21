#!/usr/bin/env bash
# DACH DB-Push mit Retry — überlebt Internet-Ausfälle.
#
# Idee:
# 1. Versuche `supabase db push` mit yes-stream
# 2. Bei "Remote migration versions not found" → automatisch repair --reverted
# 3. Bei Network-Fail → exponential backoff retry (max 6 versuche)
# 4. Bei success → exit 0
#
# Usage:
#   bash scripts/dach_push_with_retry.sh
#
# Output → logs/db-push.log
# Exit 0 = success, 2 = unfixable schema-error, 3 = network exhausted

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG="$ROOT/logs/db-push.log"
mkdir -p "$(dirname "$LOG")"

MAX_NETWORK_RETRIES=6
MAX_REPAIR_LOOPS=10
network_attempt=0
repair_attempt=0
backoff=10

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG"; }

log "=== DB-Push gestartet ==="

while true; do
  # Internet-Check: ping public endpoint (DNS + TCP). 1.1.1.1 = Cloudflare DNS,
  # immer erreichbar wenn Internet steht. -W 3 = 3s timeout pro packet.
  if ! ping -c 1 -W 3000 1.1.1.1 > /dev/null 2>&1 \
    && ! curl -sf -m 5 -I https://supabase.com > /dev/null 2>&1; then
    network_attempt=$((network_attempt + 1))
    if [[ "$network_attempt" -gt "$MAX_NETWORK_RETRIES" ]]; then
      log "❌ Kein Internet nach $MAX_NETWORK_RETRIES retries — abbruch"
      exit 3
    fi
    log "⚠ Kein Internet (Versuch $network_attempt/$MAX_NETWORK_RETRIES) — warte ${backoff}s"
    sleep "$backoff"
    backoff=$((backoff * 2))
    [[ "$backoff" -gt 300 ]] && backoff=300
    continue
  fi
  # Internet ok → reset backoff
  backoff=10
  network_attempt=0

  out=$(yes Y 2>/dev/null | supabase db push 2>&1)
  exit_code=$?

  if [[ "$exit_code" -eq 0 ]]; then
    log "✓ Push erfolgreich"
    echo "$out" | tail -10 | tee -a "$LOG"
    exit 0
  fi
  # "Remote database is up to date" = success (CLI exit nonzero aber kein Fehler)
  if echo "$out" | grep -q "Remote database is up to date"; then
    log "✓ DB ist already up-to-date"
    exit 0
  fi

  # Schema-Repair-Hinweis erkennen
  orphan=$(echo "$out" | grep -oE "20260[0-9]+" | grep -v "^20260[12]" | head -1)
  if [[ -n "$orphan" ]]; then
    repair_attempt=$((repair_attempt + 1))
    if [[ "$repair_attempt" -gt "$MAX_REPAIR_LOOPS" ]]; then
      log "❌ Zu viele Repair-Loops ($MAX_REPAIR_LOOPS) — abbruch"
      echo "$out" | tail -10 | tee -a "$LOG"
      exit 2
    fi
    log "🔧 Repair orphan tracking: $orphan (Versuch $repair_attempt/$MAX_REPAIR_LOOPS)"
    supabase migration repair --status reverted "$orphan" >> "$LOG" 2>&1
    sleep 2
    continue
  fi

  # Anderer Fehler — log + exit
  log "❌ Push gefailt mit unbekanntem Error:"
  echo "$out" | tail -20 | tee -a "$LOG"
  exit 2
done
