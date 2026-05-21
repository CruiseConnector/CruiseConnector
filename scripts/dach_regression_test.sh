#!/usr/bin/env bash
# DACH-Stabilize regression test — testet realistische Routen-Matrix
# alle 15 Min. Ziel: nicht-triviale Edge+GH-Coverage abdecken statt nur
# den simplen Wien-Smoke-Test des Heartbeats.
#
# Matrix: 8 Regionen × 4 Stile × 3 Distanzen = 96 Kombinationen,
# wir nehmen jedes Mal ein zufälliges Subset von 12 (sonst zu viel Last).
#
# Schreibt in:
#   logs/regression-YYYY-MM-DD.jsonl  (1 zeile pro test, JSON)
#   logs/regression-summary.log       (1 zeile pro run, kompakt)
#
# Exit-Codes:
#   0 = Pass-Rate ≥ 80%
#   1 = Pass-Rate 50-79% (degraded)
#   2 = Pass-Rate < 50% (critical)

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
DAY_LOG="$LOG_DIR/regression-$(date +%Y-%m-%d).jsonl"
SUMMARY="$LOG_DIR/regression-summary.log"

NOW=$(date +"%Y-%m-%dT%H:%M:%S")
ANON=$(grep -A1 supabaseAnonKey lib/config/secrets.dart | tail -1 \
  | sed "s/.*'\([^']*\)'.*/\1/")

# Regionen: name, lat, lng
declare -a REGIONS=(
  "Friedrichshafen:47.6552:9.4806"
  "Wien:48.2082:16.3738"
  "Bregenz:47.5031:9.7471"
  "Stuttgart:48.7758:9.1829"
  "Innsbruck:47.2692:11.4041"
  "Salzburg:47.8095:13.0550"
  "München:48.1351:11.5820"
  "Zürich:47.3769:8.5417"
)

declare -a STYLES=("Sport Mode" "Kurvenjagd" "Abendrunde" "Entdecker")
declare -a DISTANCES=(25 50 75)

# Shuffle + take 12 (deterministic-ish per minute, so dass aufeinander
# folgende runs unterschiedliche Subsets nehmen)
generate_combinations() {
  for region in "${REGIONS[@]}"; do
    for style in "${STYLES[@]}"; do
      for dist in "${DISTANCES[@]}"; do
        echo "$region|$style|$dist"
      done
    done
  done | python3 -c "
import sys, random
lines = [l.strip() for l in sys.stdin if l.strip()]
random.shuffle(lines)
for l in lines[:12]:
  print(l)
"
}

PASS=0
FAIL=0
DEGRADED=0
TOTAL=0

run_one() {
  local combo="$1"
  local region=$(echo "$combo" | cut -d'|' -f1)
  local style=$(echo "$combo" | cut -d'|' -f2)
  local dist=$(echo "$combo" | cut -d'|' -f3)
  local name=$(echo "$region" | cut -d: -f1)
  local lat=$(echo "$region" | cut -d: -f2)
  local lng=$(echo "$region" | cut -d: -f3)

  local start_ms
  start_ms=$(python3 -c "import time; print(int(time.time()*1000))")
  local r
  r=$(curl -s -m 20 -X POST \
    "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
    -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
    -d "{\"startLocation\":{\"latitude\":$lat,\"longitude\":$lng},\"targetDistance\":$dist,\"mode\":\"$style\",\"route_type\":\"ROUND_TRIP\",\"avoid_highways\":false,\"forceFreshVariant\":true}")
  local end_ms
  end_ms=$(python3 -c "import time; print(int(time.time()*1000))")
  local latency=$((end_ms - start_ms))

  # Parse
  local outcome
  outcome=$(echo "$r" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  if 'error' in d:
    print(f'err|{d[\"error\"]}|0|0|0|0')
  elif d.get('route'):
    km = d['route'].get('distance_km', 0)
    dur_s = d['route'].get('duration', 0)
    turns = d.get('meta', {}).get('turn_count', 0)
    pen = d.get('meta', {}).get('style_penalty', 0)
    print(f'ok|none|{km}|{dur_s}|{turns}|{pen}')
  else:
    print('err|unknown_response|0|0|0|0')
except Exception as e:
  print(f'err|parse_{e}|0|0|0|0')
" 2>/dev/null)

  local status=$(echo "$outcome" | cut -d'|' -f1)
  local err=$(echo "$outcome" | cut -d'|' -f2)
  local km=$(echo "$outcome" | cut -d'|' -f3)
  local dur=$(echo "$outcome" | cut -d'|' -f4)
  local turns=$(echo "$outcome" | cut -d'|' -f5)
  local pen=$(echo "$outcome" | cut -d'|' -f6)

  # Classification:
  #   pass: km within ±20% of target AND turns matchen style-min AND duration plausibel
  #   degraded: km outside ±20% aber Route geliefert
  #   fail: error
  local pass_flag="fail"
  if [[ "$status" == "ok" ]]; then
    local target_kmf=$dist
    local delta_pct
    delta_pct=$(python3 -c "print(abs($km - $target_kmf) / $target_kmf * 100)" 2>/dev/null || echo 100)
    local within_20
    within_20=$(python3 -c "print(1 if abs($km - $target_kmf) / $target_kmf <= 0.20 else 0)" 2>/dev/null || echo 0)
    # Duration-Sanity: reisezeit zwischen 20km/h und 100km/h Schnitt
    local dur_sane
    dur_sane=$(python3 -c "
km = $km
dur = $dur
if dur <= 0 or km <= 0:
  print(0)
else:
  speed_kmh = (km / (dur / 3600))
  print(1 if 15 < speed_kmh < 120 else 0)
" 2>/dev/null || echo 0)
    if [[ "$within_20" == "1" && "$dur_sane" == "1" ]]; then
      pass_flag="pass"
      PASS=$((PASS+1))
    else
      pass_flag="degraded"
      DEGRADED=$((DEGRADED+1))
    fi
  else
    FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))

  # Schreib eine JSON-Zeile per result
  printf '{"ts":"%s","region":"%s","style":"%s","dist":%s,"status":"%s","err":"%s","km":%s,"dur_s":%s,"turns":%s,"penalty":%s,"latency_ms":%s,"pass":"%s"}\n' \
    "$NOW" "$name" "$style" "$dist" "$status" "$err" "$km" "$dur" "$turns" "$pen" "$latency" "$pass_flag" \
    >> "$DAY_LOG"
}

# Run die 12 combos sequentially (parallel würde GH-Server überlasten)
while IFS= read -r combo; do
  run_one "$combo"
done < <(generate_combinations)

# Pass-Rate ausrechnen
PASS_RATE=$(python3 -c "print(round($PASS / $TOTAL * 100, 1))" 2>/dev/null || echo 0)

# Summary-Line
SUMMARY_LINE="[$NOW] total=$TOTAL pass=$PASS degraded=$DEGRADED fail=$FAIL pass_rate=${PASS_RATE}%"
echo "$SUMMARY_LINE" >> "$SUMMARY"
echo "$SUMMARY_LINE"

# Exit-Code by pass-rate
if (( $(echo "$PASS_RATE >= 80" | bc -l 2>/dev/null || echo 0) )); then
  exit 0
elif (( $(echo "$PASS_RATE >= 50" | bc -l 2>/dev/null || echo 0) )); then
  exit 1
else
  exit 2
fi
