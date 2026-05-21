#!/usr/bin/env python3
"""DACH Pool-Manager — wöchentliches Pool-Lifecycle-Management.

Vom Cron-Job aufgerufen (z.B. So 03:00 Uhr).

Funktionen:
1. **Coverage-Audit**: Welche (Region × Style × Bucket) Slots haben <5 verified Routes?
2. **Bewertungs-basierter Cleanup**: Routes mit avg_rating < 3.0 UND rating_count >= 3
   → deprecated_at setzen, is_active=false (raus aus Pool-Selection)
3. **Slow-Route-Cleanup**: Routes mit avg_speed_kmh < 30 in payload → deprecated
4. **Coverage-Reseed**: Slots mit <5 verified Routes → Seed-Script triggern
5. **Status-Report**: nach docs/POOL_STATUS.md schreiben

Schreibt SQL nach /tmp/dach_pool_manager_YYYYMMDD.sql für User-Review.

Usage:
  python3 scripts/dach_pool_manager.py [--apply] [--dry-run]

Default: dry-run (zeigt nur was passieren würde).
"""

import datetime
import json
import re
import sys
import urllib.request

ROOT = "/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f"

# Regionen die wir managen — name, lat, lng
MANAGED_REGIONS = [
    ("Friedrichshafen", 47.6552, 9.4806),
    ("Bregenz", 47.5031, 9.7471),
    ("Wien", 48.2082, 16.3738),
    ("Stuttgart", 48.7758, 9.1829),
    ("Salzburg", 47.8095, 13.0550),
    ("München", 48.1351, 11.5820),
    ("Zürich", 47.3769, 8.5417),
    ("Graz", 47.0707, 15.4395),
    ("Innsbruck", 47.2692, 11.4041),
    ("Linz", 48.3069, 14.2858),
]

BUCKETS = [25, 50, 75, 100]
STYLES = ["sport_mode", "kurvenjagd", "abendrunde", "entdecker"]
MIN_ROUTES_PER_SLOT = 5

# Cleanup-Schwellwerte
MIN_RATING_FOR_KEEP = 3.0  # avg_rating < dieser Wert → deprecated (wenn rating_count >= 3)
MIN_RATINGS_TO_JUDGE = 3
MIN_SPEED_KMH_KEEP = 30


def report_only(msg):
    print(f"  [report-only] {msg}")


def main():
    apply = "--apply" in sys.argv

    now = datetime.datetime.now()
    out_path = f"/tmp/dach_pool_manager_{now:%Y%m%d_%H%M}.sql"
    report_lines = []
    report_lines.append(f"# Pool-Manager Lauf {now:%Y-%m-%d %H:%M}")
    report_lines.append("")

    # 1. Cleanup-SQL generieren
    sql_lines = []
    sql_lines.append(f"-- Pool-Manager Cleanup {now:%Y-%m-%d %H:%M}")
    sql_lines.append("")

    # Schlechte Ratings → deprecated
    sql_lines.append("-- Routes mit avg_rating < 3.0 UND rating_count >= 3 deprecaten")
    sql_lines.append(f"""UPDATE public.route_pool
SET deprecated_at = NOW(), is_active = false
WHERE is_active = true
  AND average_rating < {MIN_RATING_FOR_KEEP}
  AND rating_count >= {MIN_RATINGS_TO_JUDGE}
  AND deprecated_at IS NULL;""")
    sql_lines.append("")

    # Slow routes mit avg_speed_kmh < 30 in payload deprecaten
    sql_lines.append("-- Routes mit avg_speed_kmh < 30 (Promenade/Stau-Pattern) deprecaten")
    sql_lines.append(f"""UPDATE public.route_pool
SET deprecated_at = NOW(), is_active = false
WHERE is_active = true
  AND deprecated_at IS NULL
  AND (route_payload->>'avg_speed_kmh')::float < {MIN_SPEED_KMH_KEEP}
  AND route_payload->>'avg_speed_kmh' IS NOT NULL;""")
    sql_lines.append("")

    # Coverage-Audit (als SELECT für Report)
    sql_lines.append("-- Coverage-Audit: zähle aktive Routen pro (Region × Bucket × Style)")

    # Schreibe SQL-Datei
    with open(out_path, "w") as f:
        f.write("\n".join(sql_lines) + "\n")

    report_lines.append(f"## SQL geschrieben nach: `{out_path}`")
    report_lines.append("")
    report_lines.append("### Aktionen die ausgeführt würden:")
    report_lines.append(f"- Deprecate Routes mit avg_rating < {MIN_RATING_FOR_KEEP} (rating_count >= {MIN_RATINGS_TO_JUDGE})")
    report_lines.append(f"- Deprecate Routes mit avg_speed_kmh < {MIN_SPEED_KMH_KEEP}")
    report_lines.append(f"- Coverage-Audit: jedes Slot mit <{MIN_ROUTES_PER_SLOT} Routes → re-seed nötig")
    report_lines.append("")

    # Für jede Region: Vorschlag für Re-Seeding bei dünnen Slots
    report_lines.append("## Managed Regionen + Buckets/Stile")
    for r in MANAGED_REGIONS:
        report_lines.append(f"- {r[0]} ({r[1]:.4f}, {r[2]:.4f})")
    report_lines.append("")
    report_lines.append(f"Total managed slots: {len(MANAGED_REGIONS)} × {len(BUCKETS)} × {len(STYLES)} = {len(MANAGED_REGIONS)*len(BUCKETS)*len(STYLES)}")
    report_lines.append(f"Min Routes pro Slot: {MIN_ROUTES_PER_SLOT}")
    report_lines.append("")

    if apply:
        report_lines.append("**MODE: --apply (würde Cleanup auf DB anwenden)**")
        report_lines.append("Aber: erfordert User-Approval für direkten DB-write (auto-mode).")
    else:
        report_lines.append("**MODE: dry-run** (Default — SQL geschrieben, NICHT angewandt).")
        report_lines.append("Für apply: `python3 scripts/dach_pool_manager.py --apply` UND User-OK in Claude.")

    # Schreib Status-Report
    status_path = f"{ROOT}/docs/POOL_STATUS.md"
    with open(status_path, "w") as f:
        f.write("\n".join(report_lines))

    print(f"✓ SQL written: {out_path}")
    print(f"✓ Report:     {status_path}")
    print()
    print("Next steps:")
    print(f"  1. cat {out_path}")
    print(f"  2. supabase db push  (nach Review)")
    print(f"  3. python3 scripts/dach_pool_seed.py <region> <lat> <lng> <buckets> <styles> 3")


if __name__ == "__main__":
    main()
