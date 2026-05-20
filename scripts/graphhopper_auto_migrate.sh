#!/bin/bash
# GraphHopper Autonomous Migration & Test Script
# Läuft autonom auf vucko@linux: merget AT+LI, restartet GH, testet 20 Routes,
# tunt sich selbst nach falls Distanzen daneben sind.
#
# Start (auf dem Linux-PC):
#   tmux new-session -d -s gh-auto '~/graphhopper/auto.sh'
#
# Live mitschauen:
#   tmux attach -t gh-auto
#
# Final-Ergebnis lesen:
#   cat ~/graphhopper/auto-result.json | jq

set -u
WORKDIR=~/graphhopper
LOG=$WORKDIR/auto.log
STATUS=$WORKDIR/auto-status.json
RESULT=$WORKDIR/auto-result.json
GH_LOG=$WORKDIR/gh.log

# ---------- Helper functions ----------
log() {
  local msg="[$(date +%H:%M:%S)] $*"
  echo "$msg" | tee -a "$LOG"
}

set_status() {
  local phase="$1" message="$2"
  cat > "$STATUS" <<EOF
{
  "phase": "$phase",
  "message": "$message",
  "updated_at": "$(date -Iseconds)",
  "pid": $$
}
EOF
}

abort() {
  log "FATAL: $*"
  set_status "error" "$*"
  exit 1
}

# Wait for GraphHopper /health to return 200, with timeout
wait_for_gh() {
  local max_wait="${1:-1800}"  # 30 min default
  local start_ts=$(date +%s)
  while ! curl -sf http://localhost:8989/health > /dev/null 2>&1; do
    local elapsed=$(($(date +%s) - start_ts))
    if [ "$elapsed" -gt "$max_wait" ]; then
      return 1
    fi
    # Check GH process is still alive
    if ! pgrep -f graphhopper-web.jar > /dev/null; then
      log "GraphHopper process died during startup"
      return 2
    fi
    if [ $((elapsed % 60)) -lt 5 ]; then
      log "  GH not ready yet ($elapsed s)"
    fi
    sleep 5
  done
  echo $(($(date +%s) - start_ts))
}

# Test ein Sub-Profil/Seed-Combo, gibt JSON-Object zurück
run_one_test() {
  local profile="$1" seed="$2" lat="$3" lng="$4" dist="$5"
  curl -s "http://localhost:8989/route?point=${lat},${lng}&profile=${profile}&algorithm=round_trip&round_trip.distance=${dist}&round_trip.seed=${seed}&points_encoded=false&ch.disable=true" \
    | python3 -c "
import sys, json
try:
    r = json.load(sys.stdin)
except Exception as e:
    print(json.dumps({'error': 'parse', 'detail': str(e)}))
    sys.exit(0)
if 'paths' not in r:
    print(json.dumps({'error': r.get('message', 'unknown')[:200]}))
    sys.exit(0)
p = r['paths'][0]
print(json.dumps({
    'distance_km': round(p['distance']/1000, 1),
    'time_min': round(p['time']/60000),
    'coords': len(p['points']['coordinates']),
    'ascent_m': round(p.get('ascend', 0))
}))
"
}

# Run all 20 tests (4 profiles × 5 seeds), write to a JSON file
run_full_test_suite() {
  local out="$1" lat="$2" lng="$3" target_dist="$4" label="$5"
  log "=== Test suite ($label): origin=$lat,$lng target=${target_dist}m ==="
  local first=true
  echo "{" > "$out"
  echo "  \"label\": \"$label\"," >> "$out"
  echo "  \"origin\": \"$lat,$lng\"," >> "$out"
  echo "  \"target_km\": $((target_dist/1000))," >> "$out"
  echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$out"
  echo "  \"tests\": [" >> "$out"
  for profile in motorcycle_scenic motorcycle_kurvenjagd motorcycle_abendrunde motorcycle_entdecker; do
    for seed in 1 99 234 567 9999; do
      local res
      res=$(run_one_test "$profile" "$seed" "$lat" "$lng" "$target_dist")
      if $first; then first=false; else echo "    ," >> "$out"; fi
      echo "    {\"profile\":\"$profile\",\"seed\":$seed,\"result\":$res}" >> "$out"
    done
  done
  echo "  ]" >> "$out"
  echo "}" >> "$out"
  python3 -c "
import json
d = json.load(open('$out'))
ok=0; fail=0; sum_d=0.0
for t in d['tests']:
    r = t['result']
    if 'error' in r:
        fail += 1
    else:
        ok += 1
        sum_d += r['distance_km']
target = d['target_km']
avg = round(sum_d/max(1,ok), 1)
delta_pct = round((avg-target)/target*100, 1) if ok else None
d['summary'] = {'total': ok+fail, 'ok': ok, 'failed': fail,
                'avg_distance_km': avg, 'delta_pct': delta_pct,
                'target_km': target}
json.dump(d, open('$out','w'), indent=2)
print(f'  -> {ok}/20 OK, avg {avg}km vs target {target}km (delta {delta_pct}%)')
" | tee -a "$LOG"
}

# ---------- Main pipeline ----------

echo "=== AUTO MIGRATE START $(date) ===" > "$LOG"
set_status "init" "Starting autonomous GraphHopper migration"
log "Workdir: $WORKDIR | Logfile: $LOG"

# Step 1: Stop any running GraphHopper
log "Step 1/8: Killing any running GraphHopper process..."
set_status "cleanup" "Stopping old GraphHopper process"
pkill -f graphhopper-web.jar || true
sleep 3

# Step 2: Ensure osmium-tool is installed
log "Step 2/8: Checking osmium-tool..."
if ! command -v osmium &> /dev/null; then
  set_status "install" "Installing osmium-tool (need sudo)"
  log "  osmium not found, installing via apt (this needs sudo - script may pause)"
  sudo -n apt install -y osmium-tool >> "$LOG" 2>&1 || {
    log "  Could not install osmium-tool without password. Falling back to skip-merge mode."
    SKIP_MERGE=1
  }
fi

# Step 3: Merge Austria + Liechtenstein (unless we have to skip)
cd "$WORKDIR/data"
if [ -z "${SKIP_MERGE:-}" ] && command -v osmium &> /dev/null; then
  log "Step 3/8: Merging Austria + Liechtenstein..."
  set_status "merge" "Merging OSM data (~30s)"
  rm -f at-li-merged.osm.pbf
  if osmium merge austria-latest.osm.pbf liechtenstein-latest.osm.pbf \
       -o at-li-merged.osm.pbf 2>> "$LOG"; then
    log "  Merged: $(ls -lh at-li-merged.osm.pbf | awk '{print $5}')"
    OSM_FILE="at-li-merged.osm.pbf"
  else
    log "  Merge failed, falling back to Austria-only"
    OSM_FILE="austria-latest.osm.pbf"
  fi
else
  log "Step 3/8: Skipping merge, using Austria-only"
  OSM_FILE="austria-latest.osm.pbf"
fi

# Step 4: Update config.yml to point to right file
log "Step 4/8: Updating config.yml..."
# Make sure datareader.file matches OSM_FILE
sed -i "s|datareader.file: /home/vucko1/graphhopper/data/.*\.osm\.pbf|datareader.file: /home/vucko1/graphhopper/data/$OSM_FILE|" \
  "$WORKDIR/config/config.yml"
log "  Config now points to: $(grep datareader.file $WORKDIR/config/config.yml)"

# Step 5: Wipe graph cache so GH rebuilds with new OSM
log "Step 5/8: Wiping graph cache..."
rm -rf "$WORKDIR/data/graph-cache"

# Step 6: Start GraphHopper in background
log "Step 6/8: Starting GraphHopper (import + LM-prep will take 10-25 min)..."
set_status "import" "GraphHopper importing OSM + building landmarks (10-25 min)"
cd "$WORKDIR/config"
nohup java -Xmx10g -Xms2g -server \
  -jar "$WORKDIR/bin/graphhopper-web.jar" \
  server config.yml > "$GH_LOG" 2>&1 &
GH_PID=$!
log "  GraphHopper PID: $GH_PID, log: $GH_LOG"
sleep 5

# Step 7: Wait for GH to be ready
log "Step 7/8: Waiting for GraphHopper to come up..."
STARTUP_TIME=$(wait_for_gh 1800)
WAIT_RC=$?
if [ "$WAIT_RC" -ne 0 ]; then
  abort "GraphHopper did not come up in 30 min (rc=$WAIT_RC). Check $GH_LOG"
fi
log "  GraphHopper UP after ${STARTUP_TIME}s"
set_status "testing" "GraphHopper ready, running 20-route diversity test"

# Step 8: Initial test suite (Bregenz, 50 km, where Liechtenstein won't be in radius)
log "Step 8/8: Running 20-route test suite (Bregenz)..."
TEST_BREGENZ=$WORKDIR/auto-test-bregenz.json
run_full_test_suite "$TEST_BREGENZ" 47.5031 9.7471 50000 "Bregenz 50km initial"

# Read summary
AVG_DIST=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary']['avg_distance_km'])")
OK_COUNT=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary']['ok'])")
DELTA=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary'].get('delta_pct') or 0)")

log "Initial test: $OK_COUNT/20 OK, avg ${AVG_DIST}km, delta ${DELTA}%"

# Self-tuning loop: if avg distance is >15% over target, bump distance_influence
TUNE_ROUND=0
while (( $(python3 -c "print(1 if abs($DELTA) > 15 else 0)") )) && [ "$TUNE_ROUND" -lt 3 ]; do
  TUNE_ROUND=$((TUNE_ROUND + 1))
  log "=== Self-tuning round $TUNE_ROUND/3 (delta=${DELTA}% out of target ±15%) ==="
  set_status "tuning" "Auto-tuning distance_influence (round $TUNE_ROUND/3)"

  # Bump distance_influence
  cd "$WORKDIR/config"
  for f in motorcycle_*.json; do
    CURRENT=$(grep -oP '(?<="distance_influence": )\d+' "$f")
    if [ -z "$CURRENT" ]; then continue; fi
    if (( $(python3 -c "print(1 if $DELTA > 15 else 0)") )); then
      # Distanzen zu lang -> distance_influence höher
      NEW=$((CURRENT + 50))
    else
      # Distanzen zu kurz -> distance_influence niedriger
      NEW=$(( CURRENT > 50 ? CURRENT - 30 : 30 ))
    fi
    sed -i "s|\"distance_influence\": $CURRENT|\"distance_influence\": $NEW|" "$f"
    log "  $f: $CURRENT -> $NEW"
  done

  # Restart GH (cache stays - only custom models re-read)
  log "  Restarting GraphHopper to pick up tuned custom models..."
  pkill -f graphhopper-web.jar || true
  sleep 3
  cd "$WORKDIR/config"
  nohup java -Xmx10g -Xms2g -server \
    -jar "$WORKDIR/bin/graphhopper-web.jar" \
    server config.yml > "$GH_LOG" 2>&1 &
  sleep 5

  if ! wait_for_gh 600 > /dev/null; then
    log "  Restart failed, aborting tuning loop"
    break
  fi
  log "  GH ready, re-running test suite..."

  run_full_test_suite "$TEST_BREGENZ" 47.5031 9.7471 50000 "Bregenz 50km tune-round-$TUNE_ROUND"
  AVG_DIST=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary']['avg_distance_km'])")
  OK_COUNT=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary']['ok'])")
  DELTA=$(python3 -c "import json; print(json.load(open('$TEST_BREGENZ'))['summary'].get('delta_pct') or 0)")
  log "Tune $TUNE_ROUND result: $OK_COUNT/20 OK, avg ${AVG_DIST}km, delta ${DELTA}%"
done

# Final test from Feldkirch (now that we have Liechtenstein)
TEST_FELDKIRCH=$WORKDIR/auto-test-feldkirch.json
log "=== Final test: Feldkirch 50 km (the original problem region) ==="
run_full_test_suite "$TEST_FELDKIRCH" 47.2386 9.5986 50000 "Feldkirch 50km final"

# Build summary
python3 <<PYEOF > "$RESULT"
import json
bregenz = json.load(open('$TEST_BREGENZ'))
feldkirch = json.load(open('$TEST_FELDKIRCH'))
summary = {
    "completed_at": "$(date -Iseconds)",
    "osm_file": "$OSM_FILE",
    "startup_seconds": $STARTUP_TIME,
    "tuning_rounds": $TUNE_ROUND,
    "tests": {
        "bregenz": bregenz['summary'],
        "feldkirch": feldkirch['summary']
    },
    "verdict": "ready_for_migration" if (
        bregenz['summary']['ok'] >= 16 and
        feldkirch['summary']['ok'] >= 12 and
        abs(bregenz['summary'].get('delta_pct') or 0) <= 20
    ) else "needs_more_work",
    "next_steps": []
}
if bregenz['summary']['ok'] < 16:
    summary['next_steps'].append("Bregenz pass rate <80% — Custom Models zu strikt")
if feldkirch['summary']['ok'] < 12:
    summary['next_steps'].append("Feldkirch pass rate <60% — Schweiz oder Bayern dazu mergen")
if abs(bregenz['summary'].get('delta_pct') or 0) > 20:
    summary['next_steps'].append(f"Distanz-Abweichung {bregenz['summary']['delta_pct']}% — distance_influence weiter tunen")
if not summary['next_steps']:
    summary['next_steps'].append("OK — Edge-Function-Adapter bauen, Tunnel-Setup für Supabase, Migration starten")
json.dump(summary, open('$RESULT', 'w'), indent=2)
print(json.dumps(summary, indent=2))
PYEOF

log "=== AUTO MIGRATE COMPLETE ==="
set_status "complete" "Migration test complete. Verdict in $RESULT"
log "Final result file: $RESULT"
log "Per-test details: $TEST_BREGENZ, $TEST_FELDKIRCH"
