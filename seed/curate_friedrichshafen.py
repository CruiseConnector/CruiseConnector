#!/usr/bin/env python3
"""
Curates a Friedrichshafen route pool by hitting Mapbox Directions API with
hand-designed waypoint sets. Writes SQL INSERT statements to /tmp/friedrichshafen_pool.sql
that the user can run in Supabase SQL Editor.

The Mapbox token is read from lib/config/secrets.dart at runtime and never
echoed to stdout. Only distance / coordinate counts / SQL inserts are printed.
"""
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

SECRETS_PATH = Path("/Users/vucko/Development/CruiserConnect/lib/config/secrets.dart")
OUTPUT_SQL = Path("/tmp/friedrichshafen_pool.sql")
FRIEDRICHSHAFEN = (9.4806, 47.6552)  # lng, lat


def read_mapbox_token() -> str:
    text = SECRETS_PATH.read_text()
    m = re.search(r"'(pk\.ey[A-Za-z0-9\-_\.]+)'", text)
    if not m:
        sys.exit("ERROR: Could not find Mapbox public token in secrets.dart")
    return m.group(1)


# Each waypoint set is (style_key, distance_bucket, avoid_highways, name, waypoints)
# Waypoints are [(lng, lat), ...] WITHOUT the start/end (we add Friedrichshafen).
# Designed to be CLEAN loops without tentacles: each waypoint is a real town,
# routed via roads that actually connect, no out-and-back stubs.
ROUTES = [
    # === SPORT 50 km ===
    # Sport AB-AUS (avoid_highways=True): no motorway, prefer Landstraßen
    ("sport_mode", 50, True, "Friedrichshafen-Tettnang-Wangen-Kressbronn",
     [(9.5876, 47.6711), (9.6705, 47.6500), (9.5995, 47.5836)]),
    ("sport_mode", 50, True, "Friedrichshafen-Markdorf-Oberteuringen-Tettnang",
     [(9.3909, 47.7195), (9.4753, 47.7090), (9.5876, 47.6711)]),
    ("sport_mode", 50, True, "Friedrichshafen-Ailingen-Bermatingen-Markdorf",
     [(9.5095, 47.6920), (9.3475, 47.7008), (9.3909, 47.7195)]),
    # Sport AB-AN (avoid_highways=False): A96/A98 OK
    ("sport_mode", 50, False, "Friedrichshafen-Tettnang-Lindau-Bodensee",
     [(9.5876, 47.6711), (9.6852, 47.6500), (9.6826, 47.5582)]),
    ("sport_mode", 50, False, "Friedrichshafen-Markdorf-Salem-Heiligenberg",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.3132, 47.8307)]),
    ("sport_mode", 50, False, "Friedrichshafen-Tettnang-Achberg-Kressbronn",
     [(9.5876, 47.6711), (9.7458, 47.6500), (9.5995, 47.5836)]),

    # === SPORT 75 km ===
    ("sport_mode", 75, True, "Friedrichshafen-Tettnang-Wangen-Isny",
     [(9.5876, 47.6711), (9.8338, 47.6878), (9.8307, 47.6068), (9.6995, 47.5836)]),
    ("sport_mode", 75, True, "Friedrichshafen-Markdorf-Salem-Überlingen-Bodanrück",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.1660, 47.7700), (9.1880, 47.7050)]),
    ("sport_mode", 75, True, "Friedrichshafen-Oberteuringen-Ravensburg-Tettnang",
     [(9.4753, 47.7090), (9.6111, 47.7822), (9.5876, 47.6711)]),
    ("sport_mode", 75, False, "Friedrichshafen-A96-Wangen-Lindau",
     [(9.6210, 47.6900), (9.8338, 47.6878), (9.6826, 47.5582)]),
    ("sport_mode", 75, False, "Friedrichshafen-Markdorf-Pfullendorf-Salem",
     [(9.3909, 47.7195), (9.2585, 47.9214), (9.2787, 47.7733)]),
    ("sport_mode", 75, False, "Friedrichshafen-Tettnang-Wangen-Kressbronn-Lindau",
     [(9.5876, 47.6711), (9.8338, 47.6878), (9.5995, 47.5836), (9.6826, 47.5582)]),

    # === SPORT 100 km ===
    ("sport_mode", 100, True, "Friedrichshafen-Markdorf-Pfullendorf-Aulendorf-Ravensburg",
     [(9.3909, 47.7195), (9.2585, 47.9214), (9.6394, 47.9520), (9.6111, 47.7822)]),
    ("sport_mode", 100, True, "Friedrichshafen-Tettnang-Wangen-Isny-Lindenberg-Lindau",
     [(9.5876, 47.6711), (9.8338, 47.6878), (9.9870, 47.6843), (9.8893, 47.6021), (9.6826, 47.5582)]),
    ("sport_mode", 100, True, "Friedrichshafen-Salem-Überlingen-Stockach-Bodanrück",
     [(9.2787, 47.7733), (9.1660, 47.7700), (9.0102, 47.8516), (9.1880, 47.7050)]),
    ("sport_mode", 100, False, "Friedrichshafen-A96-Wangen-Isny-A96-Lindau",
     [(9.6210, 47.6900), (9.8338, 47.6878), (9.9870, 47.6843), (9.6826, 47.5582)]),
    ("sport_mode", 100, False, "Friedrichshafen-Markdorf-Pfullendorf-Sigmaringen-Salem",
     [(9.3909, 47.7195), (9.2585, 47.9214), (9.2167, 48.0867), (9.2787, 47.7733)]),
    ("sport_mode", 100, False, "Friedrichshafen-Tettnang-Wangen-Kempten-Lindau",
     [(9.5876, 47.6711), (9.8338, 47.6878), (10.3171, 47.7267), (9.6826, 47.5582)]),

    # === KURVENJAGD === (twistier, prefer hilly back-roads)
    ("kurvenjagd", 50, True, "Friedrichshafen-Oberteuringen-Heiligenberg-Markdorf",
     [(9.4753, 47.7090), (9.3132, 47.8307), (9.3909, 47.7195)]),
    ("kurvenjagd", 50, False, "Friedrichshafen-Salem-Heiligenberg-Markdorf",
     [(9.2787, 47.7733), (9.3132, 47.8307), (9.3909, 47.7195)]),
    ("kurvenjagd", 75, True, "Friedrichshafen-Salem-Heiligenberg-Pfullendorf-Markdorf",
     [(9.2787, 47.7733), (9.3132, 47.8307), (9.2585, 47.9214), (9.3909, 47.7195)]),
    ("kurvenjagd", 75, False, "Friedrichshafen-Wangen-Isny-Argenbühl-Lindenberg",
     [(9.8338, 47.6878), (9.9870, 47.6843), (10.0107, 47.7350), (9.8893, 47.6021)]),
    ("kurvenjagd", 100, True, "Friedrichshafen-Heiligenberg-Pfullendorf-Sigmaringen-Salem",
     [(9.3132, 47.8307), (9.2585, 47.9214), (9.2167, 48.0867), (9.2787, 47.7733)]),
    ("kurvenjagd", 100, False, "Friedrichshafen-Wangen-Isny-Oberstaufen-Lindenberg-Lindau",
     [(9.8338, 47.6878), (9.9870, 47.6843), (10.0291, 47.5559), (9.8893, 47.6021), (9.6826, 47.5582)]),

    # === ABENDRUNDE === (calm, scenic, lake-views)
    ("abendrunde", 50, True, "Friedrichshafen-Kressbronn-Lindau-Bodenseeufer",
     [(9.5995, 47.5836), (9.6826, 47.5582), (9.5500, 47.5650)]),
    ("abendrunde", 50, False, "Friedrichshafen-Meersburg-Hagnau-Immenstaad",
     [(9.2700, 47.6950), (9.3258, 47.6783), (9.3725, 47.6713)]),
    ("abendrunde", 75, True, "Friedrichshafen-Kressbronn-Lindau-Wasserburg-Bregenz",
     [(9.5995, 47.5836), (9.6826, 47.5582), (9.6411, 47.5731), (9.7471, 47.5031)]),
    ("abendrunde", 75, False, "Friedrichshafen-Meersburg-Überlingen-Bodanrück-Hagnau",
     [(9.2700, 47.6950), (9.1660, 47.7700), (9.1880, 47.7050), (9.3258, 47.6783)]),
    ("abendrunde", 100, True, "Friedrichshafen-Lindau-Bregenz-Rorschach-Romanshorn",
     [(9.6826, 47.5582), (9.7471, 47.5031), (9.4904, 47.4783), (9.3789, 47.5658)]),
    ("abendrunde", 100, False, "Friedrichshafen-Überlingen-Konstanz-Meersburg",
     [(9.1660, 47.7700), (9.1732, 47.6779), (9.2700, 47.6950)]),

    # === ENTDECKER === (mix of scenic + cultural points)
    ("entdecker", 50, True, "Friedrichshafen-Markdorf-Salem-Meersburg-Hagnau",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.2700, 47.6950), (9.3258, 47.6783)]),
    ("entdecker", 50, False, "Friedrichshafen-Tettnang-Lindau-Wasserburg-Kressbronn",
     [(9.5876, 47.6711), (9.6826, 47.5582), (9.6411, 47.5731), (9.5995, 47.5836)]),
    ("entdecker", 75, True, "Friedrichshafen-Markdorf-Salem-Heiligenberg-Pfullendorf-Überlingen",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.3132, 47.8307), (9.2585, 47.9214), (9.1660, 47.7700)]),
    ("entdecker", 75, False, "Friedrichshafen-Lindau-Bregenz-Rorschach-Konstanz",
     [(9.6826, 47.5582), (9.7471, 47.5031), (9.4904, 47.4783), (9.1732, 47.6779)]),
    ("entdecker", 100, True, "Friedrichshafen-Markdorf-Heiligenberg-Pfullendorf-Sigmaringen-Salem-Überlingen",
     [(9.3909, 47.7195), (9.3132, 47.8307), (9.2585, 47.9214), (9.2167, 48.0867), (9.2787, 47.7733), (9.1660, 47.7700)]),
    ("entdecker", 100, False, "Friedrichshafen-Lindau-Bregenz-Dornbirn-Bodensee",
     [(9.6826, 47.5582), (9.7471, 47.5031), (9.7414, 47.4125), (9.6826, 47.5582)]),

    # === V2 RETRIES — fixed waypoints for out-of-band routes ===
    # Sport 50 AB-AN smaller loop (was Markdorf-Salem-Heiligenberg 70km)
    ("sport_mode", 50, False, "Friedrichshafen-Markdorf-Hagnau-Salem",
     [(9.3909, 47.7195), (9.3258, 47.6783), (9.2787, 47.7733)]),
    # Sport 75 AB-AUS without Bodanrück (was 131km)
    ("sport_mode", 75, True, "Friedrichshafen-Markdorf-Salem-Überlingen",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.1660, 47.7700)]),
    # Sport 75 AB-AUS bigger via Vogt (was 50km too short)
    ("sport_mode", 75, True, "Friedrichshafen-Oberteuringen-Ravensburg-Vogt-Tettnang",
     [(9.4753, 47.7090), (9.6111, 47.7822), (9.6717, 47.7300), (9.5876, 47.6711)]),
    # Sport 100 AB-AUS via Konstanz (was Stockach-Bodanrück 154km)
    ("sport_mode", 100, True, "Friedrichshafen-Salem-Überlingen-Konstanz-Hagnau",
     [(9.2787, 47.7733), (9.1660, 47.7700), (9.1732, 47.6779), (9.3258, 47.6783)]),
    # Sport 100 AB-AN Isny statt Kempten (was 208km)
    ("sport_mode", 100, False, "Friedrichshafen-Tettnang-Wangen-Isny-Lindau",
     [(9.5876, 47.6711), (9.8338, 47.6878), (9.9870, 47.6843), (9.6826, 47.5582)]),
    # Kurvenjagd 50 AB-AUS ohne Heiligenberg (was 70km)
    ("kurvenjagd", 50, True, "Friedrichshafen-Oberteuringen-Markdorf-Bermatingen",
     [(9.4753, 47.7090), (9.3909, 47.7195), (9.3475, 47.7008)]),
    # Kurvenjagd 50 AB-AN: Bermatingen-Heiligenberg-Markdorf (was 72km)
    ("kurvenjagd", 50, False, "Friedrichshafen-Bermatingen-Heiligenberg-Markdorf",
     [(9.3475, 47.7008), (9.3132, 47.8307), (9.3909, 47.7195)]),
    # Kurvenjagd 75 AB-AN ohne Argenbühl (was 134km)
    ("kurvenjagd", 75, False, "Friedrichshafen-Wangen-Isny-Lindenberg",
     [(9.8338, 47.6878), (9.9870, 47.6843), (9.8893, 47.6021)]),
    # Kurvenjagd 100 AB-AN ohne Oberstaufen (was 147km)
    ("kurvenjagd", 100, False, "Friedrichshafen-Wangen-Isny-Lindenberg-Lindau",
     [(9.8338, 47.6878), (9.9870, 47.6843), (9.8893, 47.6021), (9.6826, 47.5582)]),
    # Abendrunde 75 AB-AN ohne Bodanrück (was 147km)
    ("abendrunde", 75, False, "Friedrichshafen-Meersburg-Überlingen-Hagnau",
     [(9.2700, 47.6950), (9.1660, 47.7700), (9.3258, 47.6783)]),
    # Abendrunde 100 AB-AN via Stockach (was 168km)
    ("abendrunde", 100, False, "Friedrichshafen-Überlingen-Stockach-Meersburg",
     [(9.1660, 47.7700), (9.0102, 47.8516), (9.2700, 47.6950)]),
    # Entdecker 75 AB-AUS kleiner (war 107km, knapp out)
    ("entdecker", 75, True, "Friedrichshafen-Markdorf-Salem-Heiligenberg-Überlingen",
     [(9.3909, 47.7195), (9.2787, 47.7733), (9.3132, 47.8307), (9.1660, 47.7700)]),
    # Entdecker 75 AB-AN ohne Rorschach (war 177km)
    ("entdecker", 75, False, "Friedrichshafen-Lindau-Bregenz-Konstanz",
     [(9.6826, 47.5582), (9.7471, 47.5031), (9.1732, 47.6779)]),
    # Entdecker 100 AB-AUS ohne Sigmaringen (war 155km)
    ("entdecker", 100, True, "Friedrichshafen-Markdorf-Heiligenberg-Pfullendorf-Salem-Überlingen",
     [(9.3909, 47.7195), (9.3132, 47.8307), (9.2585, 47.9214), (9.2787, 47.7733), (9.1660, 47.7700)]),
]


def call_mapbox(token: str, waypoints, avoid_highways: bool):
    """Call Mapbox Directions API. Returns (distance_km, duration_s, coordinates, raw_payload)."""
    coords = [FRIEDRICHSHAFEN] + waypoints + [FRIEDRICHSHAFEN]
    coord_str = ";".join(f"{lng:.5f},{lat:.5f}" for lng, lat in coords)
    base = f"https://api.mapbox.com/directions/v5/mapbox/driving/{urllib.parse.quote(coord_str)}"
    params = {
        "access_token": token,
        "geometries": "geojson",
        "overview": "full",
        "steps": "false",
        "alternatives": "false",
        "continue_straight": "true",
    }
    if avoid_highways:
        params["exclude"] = "motorway"
    url = base + "?" + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=25) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        return None, None, None, {"error": str(e)}
    if "routes" not in data or not data["routes"]:
        return None, None, None, {"error": "no_routes", "raw": data.get("code")}
    r = data["routes"][0]
    return (
        r["distance"] / 1000.0,
        r["duration"],
        r["geometry"]["coordinates"],
        r,
    )


def build_fingerprint(coords, distance_km: float) -> str:
    """Build a fingerprint compatible with the app's RouteQualityValidator pattern.
    Format: n:<count>|d:<dist>|<sampled coords>"""
    n = len(coords)
    sample_count = 10
    if n <= sample_count:
        sampled = coords
    else:
        step = (n - 1) / (sample_count - 1)
        sampled = [coords[round(i * step)] for i in range(sample_count)]
    coord_part = "|".join(f"{lng:.4f},{lat:.4f}" for lng, lat in sampled)
    return f"n:{n}|d:{distance_km:.1f}|{coord_part}"


def subsample_coords(coords, target_count: int = 180):
    """Reduce coordinate count for storage. Keep first + last + evenly spaced middle.
    Target ~180 points = enough for good map rendering at all zoom levels."""
    n = len(coords)
    if n <= target_count:
        return coords
    step = (n - 1) / (target_count - 1)
    indices = sorted(set(round(i * step) for i in range(target_count)))
    return [coords[i] for i in indices]


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def main():
    token = read_mapbox_token()
    sql_lines = [
        "-- Curated Friedrichshafen route pool (generated by curate_friedrichshafen.py)",
        "BEGIN;",
    ]
    accepted = 0
    rejected = 0
    print("name | style | dist_bucket | avoid_hwy | actual_km | duration_min | coords | status")
    print("-" * 110)

    for style_key, dist_bucket, avoid_hwy, name, waypoints in ROUTES:
        dist_km, duration_s, coords, raw = call_mapbox(token, waypoints, avoid_hwy)
        if dist_km is None:
            print(f"{name:55s} | {style_key:11s} | {dist_bucket:3d} | {str(avoid_hwy):5s} | FAIL: {raw.get('error')}")
            rejected += 1
            continue

        # Acceptable distance band: ±35% of bucket (allows for routing detours)
        lo, hi = dist_bucket * 0.70, dist_bucket * 1.40
        if dist_km < lo or dist_km > hi:
            print(f"{name:55s} | {style_key:11s} | {dist_bucket:3d} | {str(avoid_hwy):5s} | "
                  f"{dist_km:6.1f} | {duration_s/60:5.0f} | {len(coords):4d} | OUT-OF-BAND ({lo:.0f}-{hi:.0f})")
            rejected += 1
            continue

        accepted += 1
        print(f"{name:55s} | {style_key:11s} | {dist_bucket:3d} | {str(avoid_hwy):5s} | "
              f"{dist_km:6.1f} | {duration_s/60:5.0f} | {len(coords):4d} | OK")

        # Subsample for storage — Mapbox returns 2000-5000 coords, App renders fine with ~180
        coords = subsample_coords(coords, target_count=180)
        fp = build_fingerprint(coords, dist_km)
        style_aliases = {
            "sport_mode": ["sport_mode", "sport"],
            "kurvenjagd": ["kurvenjagd", "kurvenreich"],
            "abendrunde": ["abendrunde", "panorama"],
            "entdecker": ["entdecker", "explorer"],
        }[style_key]
        style_tags_array = "ARRAY[" + ",".join(f"'{s}'" for s in style_aliases) + "]"

        geometry_json = json.dumps({"type": "LineString", "coordinates": coords})
        payload_json = json.dumps({
            "duration_seconds": duration_s,
            "distance_meters": int(dist_km * 1000),
            "source": "curated_friedrichshafen",
            "curated_name": name,
            "coordinate_count": len(coords),
            "route_source": "pool",
        })

        # has_highway: rough heuristic — if we did NOT exclude motorway, assume yes
        has_hwy = "false" if avoid_hwy else "true"
        avoids_hwy_sql = "true" if avoid_hwy else "false"

        sql_lines.append(
            "INSERT INTO route_pool (title, country_code, admin1_name, city_cluster, "
            "start_lat, start_lng, end_lat, end_lng, distance_km, distance_bucket, "
            "route_type, style_tags, avoids_highway, has_highway, quality_score, shape_score, "
            "source, verified, geometry, route_payload, route_fingerprint) VALUES ("
            f"'{sql_escape(name)}', "
            f"'DE', 'Baden-Württemberg', 'Friedrichshafen', "
            f"{FRIEDRICHSHAFEN[1]}, {FRIEDRICHSHAFEN[0]}, "
            f"{FRIEDRICHSHAFEN[1]}, {FRIEDRICHSHAFEN[0]}, "
            f"{dist_km:.2f}, {dist_bucket}, "
            f"'ROUND_TRIP', {style_tags_array}, "
            f"{avoids_hwy_sql}, {has_hwy}, "
            f"88.0, 82.0, "
            f"'curated', true, "
            f"'{sql_escape(geometry_json)}'::jsonb, "
            f"'{sql_escape(payload_json)}'::jsonb, "
            f"'{sql_escape(fp)}');"
        )

    sql_lines.append("COMMIT;")
    OUTPUT_SQL.write_text("\n".join(sql_lines))
    print("-" * 110)
    print(f"DONE. accepted={accepted} rejected={rejected} -> {OUTPUT_SQL}")


if __name__ == "__main__":
    main()
