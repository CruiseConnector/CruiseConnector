#!/usr/bin/env python3
"""Disabled legacy route-pool curator.

This script used to call Mapbox Directions for manual seed-route curation.
Mapbox usage has been removed from CruiseConnect runtime and tooling; running
this file now fails closed so it cannot create unexpected Mapbox costs.
"""

import sys


def main() -> int:
    print(
        "curate_friedrichshafen.py is disabled: Mapbox route curation has "
        "been removed. Use the self-hosted GraphHopper/Supabase route tools "
        "instead.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
