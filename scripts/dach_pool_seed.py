#!/usr/bin/env python3
"""DACH Pool-Seeder — generiert Pool-Routes via Edge v2 + Output SQL INSERTs.

Usage:
  python3 scripts/dach_pool_seed.py <region> <lat> <lng> <buckets-csv> <styles-csv> <count>

Beispiel:
  python3 scripts/dach_pool_seed.py "Friedrichshafen" 47.6552 9.4806 "25,75" "Sport Mode,Kurvenjagd,Abendrunde,Entdecker" 3

Schreibt SQL nach /tmp/dach_pool_seed_<region>.sql für späteren apply.
"""

import json
import re
import sys
import time
import urllib.request

ROOT = "/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"
EDGE = "https://tlcfaxvvqzobmzwvfnvb.supabase.co/functions/v1/generate-cruise-route-v2"


def read_anon():
    with open(f"{ROOT}/lib/config/secrets.dart") as f:
        text = f.read()
    m = re.search(r"supabaseAnonKey\s*=\s*'([^']+)'", text)
    return m.group(1) if m else ""


def call_edge(anon, lat, lng, km, style):
    body = json.dumps({
        "startLocation": {"latitude": lat, "longitude": lng},
        "targetDistance": km,
        "mode": style,
        "route_type": "ROUND_TRIP",
        "avoid_highways": False,
        "forceFreshVariant": True,
    }).encode("utf-8")
    req = urllib.request.Request(
        EDGE,
        data=body,
        headers={
            "Authorization": f"Bearer {anon}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": "fetch_failed", "detail": str(e)}


# Region → (country_code, admin1_name) — für NOT NULL constraints
REGION_META = {
    "Friedrichshafen": ("DE", "Baden-Württemberg"),
    "Stuttgart": ("DE", "Baden-Württemberg"),
    "Heilbronn": ("DE", "Baden-Württemberg"),
    "Mannheim": ("DE", "Baden-Württemberg"),
    "München": ("DE", "Bayern"),
    "Munich": ("DE", "Bayern"),
    "Bregenz": ("AT", "Vorarlberg"),
    "Feldkirch": ("AT", "Vorarlberg"),
    "Innsbruck": ("AT", "Tirol"),
    "Salzburg": ("AT", "Salzburg"),
    "Wien": ("AT", "Wien"),
    "Vienna": ("AT", "Wien"),
    "Linz": ("AT", "Oberösterreich"),
    "Graz": ("AT", "Steiermark"),
    "Klagenfurt": ("AT", "Kärnten"),
    "Leoben": ("AT", "Steiermark"),
    "Bruck-Mur": ("AT", "Steiermark"),
    "Liezen": ("AT", "Steiermark"),
    "Mariazell": ("AT", "Steiermark"),
    "Schladming": ("AT", "Steiermark"),
    "Zürich": ("CH", "Zürich"),
    "Zurich": ("CH", "Zürich"),
    "Bern": ("CH", "Bern"),
    "Basel": ("CH", "Basel-Stadt"),
    "Lugano": ("CH", "Tessin"),
    "Vaduz": ("LI", "Vaduz"),
}


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        sys.exit(1)

    region = sys.argv[1]
    lat = float(sys.argv[2])
    lng = float(sys.argv[3])
    buckets = [int(b) for b in sys.argv[4].split(",")]
    styles = sys.argv[5].split(",")
    count = int(sys.argv[6]) if len(sys.argv) > 6 else 3

    country_code, admin1_name = REGION_META.get(region, ("DE", "Unknown"))

    anon = read_anon()
    if not anon:
        print("ERR: Konnte supabaseAnonKey nicht lesen")
        sys.exit(2)

    region_slug = re.sub(r"[^a-zA-Z0-9]+", "_", region)
    out_path = f"/tmp/dach_pool_seed_{region_slug}.sql"
    out = open(out_path, "w")
    out.write(f"-- Pool-Seed für {region} ({lat}, {lng}) generiert {time.ctime()}\n\n")

    total_ok = 0
    total_fail = 0
    seen_fingerprints = set()

    for bucket in buckets:
        for style in styles:
            style_lower = style.lower().replace(" ", "_")
            print(f"=== {region} {bucket}km {style} ===")
            ok_for_combo = 0
            tries = 0
            max_tries = count * 3  # extra Versuche für diversity

            while ok_for_combo < count and tries < max_tries:
                tries += 1
                d = call_edge(anon, lat, lng, bucket, style)
                if "error" in d:
                    print(f"  ❌ attempt {tries}: {d['error']}")
                    total_fail += 1
                    continue
                route = d.get("route")
                if not route:
                    print(f"  ❌ attempt {tries}: no route in response")
                    total_fail += 1
                    continue

                meta = d.get("meta", {})
                km = route.get("distance_km", 0)
                dur = route.get("duration", 0)
                geom = route["geometry"]
                coords = geom["coordinates"]
                fp = meta.get("route_fingerprint", "")
                if fp in seen_fingerprints:
                    print(f"  · attempt {tries}: duplicate fp, skip")
                    continue
                seen_fingerprints.add(fp)

                # Qualitätsfilter: strenger seit 2026-05-21-v2
                avg_speed = meta.get("avg_speed_kmh", 0) or 0
                turns = meta.get("turn_count", 0) or 0
                turns_per_km = turns / km if km > 0 else 0
                # Speed: ≥40 für ≥75km Routes, ≥35 für 25-50km
                min_speed = 40 if bucket >= 75 else 35
                if avg_speed < min_speed:
                    print(f"  · attempt {tries}: avg_speed={avg_speed} < {min_speed}, skip")
                    continue
                if turns_per_km < 0.5:
                    print(f"  · attempt {tries}: turns/km={turns_per_km:.2f} too few, skip")
                    continue
                # Distance must be within ±18% of bucket target (vorher 25%)
                delta_pct = abs(km - bucket) / bucket * 100
                if delta_pct > 18:
                    print(f"  · attempt {tries}: distance {km:.1f}km vs {bucket}km ({delta_pct:.0f}%) skip")
                    continue

                start = coords[0]
                end = coords[-1]
                payload = {
                    "route_source": f"pool_seed_{region_slug}",
                    "engine": meta.get("engine", "graphhopper-8"),
                    "turn_count": meta.get("turn_count"),
                    "avg_speed_kmh": meta.get("avg_speed_kmh"),
                    "duration_seconds": int(dur),
                    "seed_origin": "graphhopper_v2_curated_2026_05_21",
                    "edge_version": "v2",
                }
                geom_sql = json.dumps(geom).replace("'", "''")
                payload_sql = json.dumps(payload).replace("'", "''")
                style_tag = style_lower
                title = f"{region} {bucket}km {style} ({avg_speed:.0f}km/h, {turns} Kurven)"
                title_sql = title.replace("'", "''")
                fingerprint = meta.get("route_fingerprint", "")[:60].replace("'", "''")

                out.write(
                    "INSERT INTO public.route_pool ("
                    "title, distance_bucket, distance_km, "
                    "country_code, admin1_name, city_cluster, "
                    "start_lat, start_lng, end_lat, end_lng, "
                    "route_type, geometry, style_tags, avoids_highway, has_highway, "
                    "verified, is_active, source, route_payload, route_fingerprint, "
                    "quality_score, shape_score, user_rating, average_rating, "
                    "usage_count, rating_count, completion_rate, weekly_rotation_score"
                    ") VALUES ("
                    f"'{title_sql}', {bucket}, {km:.2f}, "
                    f"'{country_code}', '{admin1_name}', '{region.replace(chr(39), chr(39)+chr(39))}', "
                    f"{start[1]:.6f}, {start[0]:.6f}, {end[1]:.6f}, {end[0]:.6f}, "
                    f"'ROUND_TRIP', '{geom_sql}'::jsonb, ARRAY['{style_tag}']::text[], true, false, "
                    f"true, true, 'pool_seed_v2', '{payload_sql}'::jsonb, '{fingerprint}', "
                    f"82.0, 78.0, 4.2, 4.2, "
                    f"0, 0, 0.0, 70.0"
                    ");\n"
                )
                print(
                    f"  ✓ attempt {tries}: {km:.1f}km {meta.get('turn_count','?')} turns "
                    f"{meta.get('avg_speed_kmh','?')}km/h fp={fp[:16]}"
                )
                ok_for_combo += 1
                total_ok += 1
                time.sleep(0.4)

            if ok_for_combo < count:
                print(f"  ⚠ Only {ok_for_combo}/{count} routes for {bucket}km {style}")

    out.close()
    print()
    print("=== SUMMARY ===")
    print(f"OK: {total_ok}  FAIL: {total_fail}")
    print(f"SQL: {out_path}")


if __name__ == "__main__":
    main()
