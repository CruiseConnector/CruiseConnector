# Friedrichshafen Curated Pool Seed

Hand-designed Mapbox-Routen für Friedrichshafen/Bodensee-Region, da Live-Generation
in flachen Regionen strukturell tentakelige Sport-Loops liefert.

## Was hier liegt

- **`curate_friedrichshafen.py`** — Python-Skript, das hand-designed Waypoint-Sets durch die
  Mapbox Directions API schickt, Distanz validiert (±35% Toleranz pro distance_bucket) und
  SQL-INSERTs für `route_pool` schreibt. Token wird aus `lib/config/secrets.dart` gelesen,
  niemals ausgegeben.
- **`friedrichshafen_pool.sql`** — Generierte 33 INSERTs (4 Stile × 3 Distanzen × 2
  Highway-Optionen, gefiltert auf die mit passender Distanz). Geometrien subsampled auf
  ~180 Koordinaten pro Route für Storage-Effizienz.

## Was schon in der DB ist (Stand commit dieser Datei)

3 von 33 routes wurden bereits via mcp `execute_sql` eingefügt:
- Sport 50 km AB-AUS: `Friedrichshafen-Tettnang-Wangen-Kressbronn` (45 km)
- Sport 50 km AB-AUS: `Friedrichshafen-Markdorf-Oberteuringen-Tettnang` (47 km)
- Sport 50 km AB-AUS: `Friedrichshafen-Ailingen-Bermatingen-Markdorf` (42 km)

Plus 5 Routes vom Cron-Worker davor.
**= 9 Pool-Routes total** für Friedrichshafen.

## Die restlichen 30 Routes einspielen

Auto-Mode blockt große SQL-Writes von Claude aus. Du musst es selbst runen:

**Variante A — Supabase SQL Editor:**
1. Öffne https://supabase.com/dashboard/project/tlcfaxvvqzobmzwvfnvb/sql
2. Inhalt von `friedrichshafen_pool.sql` reinkopieren
3. "Run"
4. INSERTs mit Sport-Routes, die schon in der DB sind, schlagen mit duplicate-key fehl wenn
   du UNIQUE constraints hast — sind aber harmlos. Sonst werden sie einfach doppelt.

**Variante B — Direkt mit `psql`:**
```bash
psql "$(supabase status -o env | grep DB_URL | cut -d= -f2)" -f seed/friedrichshafen_pool.sql
```
(funktioniert nur wenn supabase lokal verbunden ist)

## Skript neu laufen lassen / erweitern

Wenn du andere Städte machen willst (Konstanz, Lindau, Wien…), kopier
`curate_friedrichshafen.py` und passe:
- `FRIEDRICHSHAFEN` Tuple (lng, lat) → neuer Stadt-Center
- `ROUTES` Liste → neue Waypoint-Sets
- `OUTPUT_SQL` Path

Dann `python3 curate_xyz.py`. Mapbox-Call-Limit beachten: 36 Routes ≈ 36 API-Calls.

## Coverage-Status

Mit den 33 Routes (wenn alle inserted):
- **Sport** — 50/75/100 km × AB-AN/AUS → ~12 Routes (3 schon drin)
- **Kurvenjagd** — 50/75/100 km × AB-AN/AUS → ~6 Routes (manche out-of-band gestrichen)
- **Abendrunde** — 50/75/100 km × AB-AN/AUS → ~6 Routes
- **Entdecker** — 50/75/100 km × AB-AN/AUS → ~5 Routes

Plus Bregenz-Cross-Border-Match (113 Routes) deckt automatisch den meisten Friedrichshafen-
Verkehr ab.

## Warum hand-designed?

`process-route-seed-jobs` (Worker) nutzt die gleichen Edge-Plan-Templates wie Live-Search.
In flacher Region (Bodensee) erzeugen diese Templates strukturell u-turn-y Routes oder
Distance-Bugs (100 km Plan → 200 km Route). Daher: für Bodensee-Stadt-Cluster die Pool-
Routes manuell mit echten Cities als Waypoints (Tettnang, Wangen, Lindau, Markdorf, Salem,
Überlingen etc.) generieren — Mapbox berechnet sauber zwischen ihnen.

Spätere Iterationen: dasselbe für Konstanz, Lindau, Stuttgart, Karlsruhe, Augsburg.
