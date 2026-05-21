#!/usr/bin/env bash
# DACH Seed-Loop — wählt eine Stadt aus master_cities, seedet sie, schreibt
# Migration, pusht via dach_push_with_retry.sh.
#
# Aufruf von Cron (z.B. alle 30 Min) ODER manuell. Idempotent.
#
# Schritt-für-Schritt:
# 1. Nimm erste Stadt aus master_cities ohne seed-migration
# 2. Seed via dach_pool_seed.py
# 3. Migration-File anlegen mit auto-timestamp + ON CONFLICT
# 4. dach_push_with_retry.sh → DB

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG="$ROOT/logs/seed-loop.log"
mkdir -p "$(dirname "$LOG")"
log() { echo "[$(date +%Y-%m-%dT%H:%M:%S)] $1" | tee -a "$LOG"; }

# 1. Wähle Stadt
result=$(bash "$ROOT/scripts/dach_auto_seed_next.sh" 2>&1)
echo "$result" >> "$LOG"
new_migration=$(echo "$result" | grep -oE 'supabase/migrations/[^ ]+_pool\.sql' | tail -1)

if [[ -z "$new_migration" ]]; then
  log "✓ Keine neue Stadt zu seeden (alle DACH-Cities aus master durch)"
  exit 0
fi

log "📦 Migration ready: $new_migration"

# 2. Push
bash "$ROOT/scripts/dach_push_with_retry.sh" > /dev/null 2>&1 &
push_pid=$!
wait "$push_pid"
push_exit=$?

if [[ "$push_exit" -eq 0 ]]; then
  log "✓ Push erfolgreich für $new_migration"
else
  log "❌ Push gefailt (exit=$push_exit) — Migration bleibt, retry nächster Tick"
fi
