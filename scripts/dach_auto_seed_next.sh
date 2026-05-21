#!/usr/bin/env bash
# DACH Auto-Seed — wählt nächste un-seeded Stadt aus Master-Liste, seedet, applied.
#
# Aufruf vom Cron-Job (z.B. jede Stunde). Idempotent: prüft welche Städte
# schon im Pool sind, nimmt die erste noch nicht-seedete.
#
# Master-Liste: scripts/dach_master_cities.txt (eine Zeile pro Stadt:
#   name:lat:lng)

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

MASTER="$ROOT/scripts/dach_master_cities.txt"
LOG="$ROOT/logs/auto-seed.log"
mkdir -p "$(dirname "$LOG")"

if [[ ! -f "$MASTER" ]]; then
  echo "[$(date)] no master file" >> "$LOG"
  exit 1
fi

# Lese Pool-DB welche city_clusters schon existieren
ANON=$(grep -A1 supabaseAnonKey lib/config/secrets.dart | tail -1 \
  | sed "s/.*'\([^']*\)'.*/\1/")

seeded=$(curl -s -X POST "https://tlcfaxvvqzobmzwvfnvb.supabase.co/rest/v1/rpc/get_seeded_cities" \
  -H "apikey: $ANON" \
  -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" 2>/dev/null || echo "[]")

# Fallback: Liste aus existierenden Migration-Files
seeded_files=$(ls supabase/migrations/2026052*_*_pool.sql 2>/dev/null \
  | xargs -n1 basename 2>/dev/null \
  | sed -E 's/^[0-9]+_(.+)_pool\.sql$/\1/' | tr '[:lower:]' '[:upper:]')

# Wähle erste Stadt aus Master die NICHT geseedet
chosen=""
while IFS=: read -r name lat lng; do
  [[ -z "$name" || "$name" == "#"* ]] && continue
  slug=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/_/g')
  upper=$(echo "$slug" | tr '[:lower:]' '[:upper:]')
  if ! echo "$seeded_files" | grep -qi "^$upper$"; then
    chosen="$name:$lat:$lng:$slug"
    break
  fi
done < "$MASTER"

if [[ -z "$chosen" ]]; then
  echo "[$(date)] ALL_SEEDED — alle Master-Städte sind durch" >> "$LOG"
  exit 0
fi

name=$(echo "$chosen" | cut -d: -f1)
lat=$(echo "$chosen" | cut -d: -f2)
lng=$(echo "$chosen" | cut -d: -f3)
slug=$(echo "$chosen" | cut -d: -f4)

echo "[$(date)] SEEDING $name ($lat, $lng)" >> "$LOG"

# Seed via Python script
python3 "$ROOT/scripts/dach_pool_seed.py" "$name" $lat $lng \
  "25,50,75,100" "Sport Mode,Kurvenjagd,Abendrunde,Entdecker" 3 \
  > /dev/null 2>&1

src="/tmp/dach_pool_seed_${name}.sql"
if [[ ! -f "$src" ]]; then
  src=$(ls /tmp/dach_pool_seed_${name}*.sql 2>/dev/null | head -1)
fi

if [[ -z "$src" || ! -f "$src" ]]; then
  echo "[$(date)] FAIL seed_no_output for $name" >> "$LOG"
  exit 2
fi

n=$(grep -c "^INSERT" "$src")
if [[ "$n" -eq 0 ]]; then
  echo "[$(date)] FAIL seed_zero_routes for $name" >> "$LOG"
  exit 2
fi

# Migration-File anlegen mit timestamp NEUER als existierende Seed-Migrations.
# Existing seeds enden bei 20260522017000 (zuerich). Wir starten bei 20260522030000+
# damit Supabase die Reihenfolge stabil hält.
last_seed=$(ls supabase/migrations/2026052[12]*_*_pool.sql 2>/dev/null | sort | tail -1)
if [[ -n "$last_seed" ]]; then
  last_ts=$(basename "$last_seed" | grep -oE '^[0-9]+')
  next_ts=$((last_ts + 100))  # +100 für nächstes seed
else
  next_ts=$(date +%Y%m%d%H%M%S)
fi
migration="supabase/migrations/${next_ts}_${slug}_pool.sql"
# Mit ON CONFLICT
python3 -c "
import re
with open('$src') as f: content = f.read()
new = re.sub(r'\);\n', ') ON CONFLICT (route_fingerprint) DO NOTHING;\n', content)
with open('$migration', 'w') as f:
    f.write('-- Auto-Seed $name $(date)\n' + new)
"

echo "[$(date)] CREATED $migration ($n routes)" >> "$LOG"
echo "  → run 'supabase db push' um in DB zu laden"
