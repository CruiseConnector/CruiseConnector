# Pool-Manager Lauf 2026-05-21 23:36

## SQL geschrieben nach: `/tmp/dach_pool_manager_20260521_2336.sql`

### Aktionen die ausgeführt würden:
- Deprecate Routes mit avg_rating < 3.0 (rating_count >= 3)
- Deprecate Routes mit avg_speed_kmh < 30
- Coverage-Audit: jedes Slot mit <5 Routes → re-seed nötig

## Managed Regionen + Buckets/Stile
- Friedrichshafen (47.6552, 9.4806)
- Bregenz (47.5031, 9.7471)
- Wien (48.2082, 16.3738)
- Stuttgart (48.7758, 9.1829)
- Salzburg (47.8095, 13.0550)
- München (48.1351, 11.5820)
- Zürich (47.3769, 8.5417)
- Graz (47.0707, 15.4395)
- Innsbruck (47.2692, 11.4041)
- Linz (48.3069, 14.2858)

Total managed slots: 10 × 4 × 4 = 160
Min Routes pro Slot: 5

**MODE: dry-run** (Default — SQL geschrieben, NICHT angewandt).
Für apply: `python3 scripts/dach_pool_manager.py --apply` UND User-OK in Claude.