#!/usr/bin/env bash
# DACH Pool-Seeder — generiert Pool-Routes via Edge v2 + INSERT in DB.
#
# Usage:
#   bash scripts/dach_pool_seed.sh <region-name> <lat> <lng> <buckets> <styles> <count_per_combo>
#
# Beispiel:
#   bash scripts/dach_pool_seed.sh "Friedrichshafen" 47.6552 9.4806 "25,75" "Sport Mode,Kurvenjagd,Abendrunde,Entdecker" 3
#
# Schreibt jeden generierten Route als SQL INSERT in
#   /tmp/dach_pool_seed_<region>.sql
# danach kann der User es via psql/supabase mcp anwenden.

set -uo pipefail

ROOT="/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
cd "$ROOT" || exit 1

REGION="$1"
LAT="$2"
LNG="$3"
BUCKETS_CSV="$4"
STYLES_CSV="$5"
COUNT="${6:-3}"

ANON=$(grep -A1 supabaseAnonKey lib/config/secrets.dart | tail -1 \
  | sed "s/.*'\([^']*\)'.*/\1/")

OUT="/tmp/dach_pool_seed_${REGION// /_}.sql"
> "$OUT"
echo "-- Pool-Seed für $REGION ($LAT, $LNG) generiert $(date)" >> "$OUT"
echo "" >> "$OUT"

IFS=',' read -ra BUCKETS <<< "$BUCKETS_CSV"
IFS=',' read -ra STYLES <<< "$STYLES_CSV"

TOTAL_OK=0
TOTAL_FAIL=0

for bucket in "${BUCKETS[@]}"; do
  for style in "${STYLES[@]}"; do
    style_lower=$(echo "$style" | tr 'A-Z ' 'a-z_')
    echo "=== $REGION ${bucket}km $style ==="
    for i in $(seq 1 "$COUNT"); do
      r=$(curl -s -m 20 -X POST \
        "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2" \
        -H "Authorization: Bearer $ANON" -H "Content-Type: application/json" \
        -d "{\"startLocation\":{\"latitude\":$LAT,\"longitude\":$LNG},\"targetDistance\":$bucket,\"mode\":\"$style\",\"route_type\":\"ROUND_TRIP\",\"avoid_highways\":false,\"forceFreshVariant\":true}")
      sql=$(echo "$r" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        print(f'ERR:{d[\"error\"]}')
        sys.exit()
    if not d.get('route'):
        print('ERR:no_route_in_response')
        sys.exit()
    route = d['route']
    meta = d.get('meta', {})
    km = route.get('distance_km')
    dur = route.get('duration')
    geom_json = json.dumps(route['geometry'])
    coords = route['geometry']['coordinates']
    start = coords[0]
    end = coords[-1]
    style_tags = ['$style_lower']
    style_tags_pg = '{' + ','.join(f'\"{s}\"' for s in style_tags) + '}'
    payload = {
        'route_source': 'pool_seed_${REGION// /_}',
        'engine': meta.get('engine', 'graphhopper-8'),
        'turn_count': meta.get('turn_count'),
        'avg_speed_kmh': meta.get('avg_speed_kmh'),
        'seed_origin': 'graphhopper_v2_curated_2026_05_21',
    }
    print('SQL_OK:' + json.dumps({
        'distance_bucket': $bucket,
        'distance_km': float(km),
        'duration_seconds': int(dur),
        'start_lat': float(start[1]),
        'start_lng': float(start[0]),
        'end_lat': float(end[1]),
        'end_lng': float(end[0]),
        'geometry': geom_json,
        'style_tags_pg': style_tags_pg,
        'payload': json.dumps(payload),
    }))
except Exception as e:
    print(f'ERR:parse_{e}')
")
      if [[ "$sql" == SQL_OK:* ]]; then
        json_data="${sql#SQL_OK:}"
        # Build SQL INSERT
        python3 -c "
import json
d = json.loads('''$json_data''')
geom_escaped = d['geometry'].replace(\"'\", \"''\")
payload_escaped = d['payload'].replace(\"'\", \"''\")
print(f'''INSERT INTO public.route_pool (
  distance_bucket, distance_km, duration_seconds,
  start_lat, start_lng, end_lat, end_lng,
  geometry, style_tags, verified, is_active, route_payload,
  shape_score, average_rating, user_rating
) VALUES (
  {d[\"distance_bucket\"]}, {d[\"distance_km\"]}, {d[\"duration_seconds\"]},
  {d[\"start_lat\"]}, {d[\"start_lng\"]}, {d[\"end_lat\"]}, {d[\"end_lng\"]},
  '{geom_escaped}'::jsonb, '{d[\"style_tags_pg\"]}'::text[], true, true,
  '{payload_escaped}'::jsonb,
  78.0, 4.2, 4.2
);''')" >> "$OUT"
        echo "  ✓ attempt $i: ${bucket}km $style"
        TOTAL_OK=$((TOTAL_OK+1))
      else
        echo "  ❌ attempt $i: $sql"
        TOTAL_FAIL=$((TOTAL_FAIL+1))
      fi
      sleep 0.5  # GH-Server nicht überlasten
    done
  done
done

echo ""
echo "=== SUMMARY ==="
echo "OK: $TOTAL_OK  FAIL: $TOTAL_FAIL"
echo "SQL geschrieben nach: $OUT"
echo "Lines:"
wc -l "$OUT"
