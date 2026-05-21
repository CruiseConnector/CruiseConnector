#!/usr/bin/env bash
# DACH Final-State Monitor — pollt Seed-Loop bis fertig + meldet Bericht.
#
# Beobachtet:
# 1. dach_seed_all_missing.sh Prozess (wenn weg → seed-loop done)
# 2. logs/seed-all-missing.log auf "SUMMARY"-line
#
# Bei Abschluss → Bericht an Claude (Status-File + exit).
#
# Wird vom Claude-Cron alle paar Minuten aufgerufen oder als one-shot.

set -uo pipefail
ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG="$ROOT/logs/seed-all-missing.log"
REPORT="$ROOT/logs/final-state-report.md"

if [[ ! -f "$LOG" ]]; then
  echo "STATUS=no_log"
  exit 0
fi

# Ist seed-loop noch aktiv?
running=$(pgrep -f "dach_seed_all_missing.sh" | head -1)
if [[ -n "$running" ]]; then
  # Calc progress
  done=$(grep -c "✓.*routes" "$LOG" 2>/dev/null || echo 0)
  failed=$(grep -c "❌" "$LOG" 2>/dev/null || echo 0)
  total=39  # aus Master-Liste
  eta_min=$(python3 -c "
done = $done
remaining = max(0, $total - done - $failed)
print(round(remaining * 1.3))" 2>/dev/null || echo "?")
  current=$(grep "🌱 Seeding" "$LOG" | tail -1 | sed 's/.*Seeding /Seeding /' | cut -d'(' -f1)
  echo "STATUS=running done=$done failed=$failed remaining=$((total - done - failed)) eta=${eta_min}min current=\"$current\""
  exit 0
fi

# Process weg → entweder fertig oder gecrasht
if grep -q "SUMMARY:" "$LOG"; then
  summary=$(grep "SUMMARY:" "$LOG" | tail -1)
  pushed=$(grep -c "Push erfolgreich\|already up-to-date" "$LOG")

  # Final report schreiben
  cat > "$REPORT" << EOF
# 🎯 DACH Final-State — $(date)

**Background-Seed abgeschlossen.**

$summary

## Aktuelle Pool-Coverage
Wird gleich abgefragt via SQL.

## Push-Status
Pushes erfolgreich: $pushed

## Wöchentlicher Maintenance-Cron
Aktiv seit Migration 20260523020000_weekly_pool_maintenance.
Nächster Lauf: Sonntag 23:59 UTC (Mo 01:59 CEST).
- refresh_pool_route_ratings()
- decay_pool_rotation_scores()
- coverage_snapshot
EOF
  echo "STATUS=done $summary"
  exit 0
fi

# Gecrasht
echo "STATUS=crashed no_summary_in_log"
exit 1
