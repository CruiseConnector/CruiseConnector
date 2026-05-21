#!/usr/bin/env bash
# Seedet ALLE in master_cities aber noch nicht in migrations — sequenziell.
# Output: 1 migration pro Stadt.

set -uo pipefail
ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1
LOG="$ROOT/logs/seed-all-missing.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date +%H:%M:%S)] $1" | tee -a "$LOG"; }

# Enumerate missing
mapfile -t missing < <(python3 << 'PYEOF'
import os, re
master = []
with open('scripts/dach_master_cities.txt') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#'):
            parts = line.split(':')
            if len(parts) == 3:
                master.append((parts[0], parts[1], parts[2]))

migrations = set()
for f in os.listdir('supabase/migrations'):
    if 'pool.sql' in f and f.startswith('2026052'):
        m = re.search(r'_([a-z_0-9]+)_pool\.sql$', f)
        if m:
            migrations.add(m.group(1).lower())

for city, lat, lng in master:
    slug = re.sub(r'[^a-zA-Z0-9]', '_', city).lower()
    if slug not in migrations:
        print(f"{city}|{lat}|{lng}|{slug}")
PYEOF
)

log "📋 ${#missing[@]} Städte zu seeden"

# Get next timestamp
last_seed=$(ls supabase/migrations/2026052[12]*_*_pool.sql 2>/dev/null | sort | tail -1)
if [[ -n "$last_seed" ]]; then
  last_ts=$(basename "$last_seed" | grep -oE '^[0-9]+')
  next_ts=$((last_ts + 100))
else
  next_ts=20260522040000
fi

ok=0
fail=0
for entry in "${missing[@]}"; do
  IFS='|' read -r city lat lng slug <<< "$entry"
  log "🌱 Seeding $city ($lat, $lng)..."
  python3 scripts/dach_pool_seed.py "$city" "$lat" "$lng" \
    "25,50,75,100" "Sport Mode,Kurvenjagd,Abendrunde,Entdecker" 3 \
    > /dev/null 2>&1
  src="/tmp/dach_pool_seed_${city}.sql"
  if [[ ! -f "$src" ]]; then
    src=$(ls "/tmp/dach_pool_seed_${city}"*.sql 2>/dev/null | head -1)
  fi
  if [[ -z "$src" || ! -f "$src" ]]; then
    log "  ❌ no /tmp file for $city"
    fail=$((fail + 1))
    continue
  fi
  n=$(grep -c "^INSERT" "$src")
  if [[ "$n" -eq 0 ]]; then
    log "  ❌ $city: 0 routes (vermutlich GH bbox-issue)"
    fail=$((fail + 1))
    continue
  fi
  migration="supabase/migrations/${next_ts}_${slug}_pool.sql"
  python3 -c "
import re
with open('$src') as f: content = f.read()
new = re.sub(r'\);\n', ') ON CONFLICT (route_fingerprint) DO NOTHING;\n', content)
with open('$migration', 'w') as f:
    f.write('-- Auto-Seed $city $(date)\n' + new)
"
  log "  ✓ $city: $n routes → $(basename $migration)"
  ok=$((ok + 1))
  next_ts=$((next_ts + 100))
done

log "📊 SUMMARY: $ok geseeded, $fail gefailed"
log "→ bash scripts/dach_push_with_retry.sh um zu pushen"
