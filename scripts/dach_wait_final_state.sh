#!/usr/bin/env bash
# Wartet bis dach_seed_all_missing.sh fertig ist, dann gibt Final-Report.
# Aufruf via Bash run_in_background — Claude wird notified.

set -uo pipefail
ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"

# Warte bis seed-process fertig
while pgrep -f "dach_seed_all_missing.sh" > /dev/null; do
  sleep 60
done

# 60s grace für den auto-push
sleep 30

# Report
echo "═══════════════════════════════════════════════════════════════"
echo "🎯 DACH FINAL STATE ERREICHT — $(date)"
echo "═══════════════════════════════════════════════════════════════"
tail -20 "$ROOT/logs/seed-all-missing.log"
echo ""
echo "Lokale Migrations:"
ls "$ROOT/supabase/migrations/2026052"*_*_pool.sql 2>/dev/null | wc -l
echo "files mit pool-routes"
