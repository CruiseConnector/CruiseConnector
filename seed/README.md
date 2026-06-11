# Friedrichshafen Curated Pool Seed

Historischer, bereits generierter Route-Pool für Friedrichshafen/Bodensee.
Die alte Mapbox-Kuration ist deaktiviert, damit keine neuen Mapbox-Kosten
mehr durch lokale Tools entstehen.

## Was hier liegt

- **`curate_friedrichshafen.py`** — bewusst deaktivierter Stub. Er liest keinen Token
  und ruft keinen externen Karten-/Routinganbieter mehr auf.
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

## Neue Seeds erzeugen

Neue Seeds sollen nur noch über die selbst gehostete GraphHopper/Supabase-v2
Route-Generierung erzeugt werden. Dieser Ordner enthält nur historische SQL-
Artefakte; `curate_friedrichshafen.py` bricht absichtlich ab.

## Coverage-Status

Mit den 33 Routes (wenn alle inserted):
- **Sport** — 50/75/100 km × AB-AN/AUS → ~12 Routes (3 schon drin)
- **Kurvenjagd** — 50/75/100 km × AB-AN/AUS → ~6 Routes (manche out-of-band gestrichen)
- **Abendrunde** — 50/75/100 km × AB-AN/AUS → ~6 Routes
- **Entdecker** — 50/75/100 km × AB-AN/AUS → ~5 Routes

Plus Bregenz-Cross-Border-Match (113 Routes) deckt automatisch den meisten Friedrichshafen-
Verkehr ab.

## Warum hand-designed?

`process-route-seed-jobs` (Worker) nutzte historisch die gleichen Edge-Plan-Templates wie
Live-Search. In flacher Region (Bodensee) erzeugten diese Templates strukturell u-turn-y
Routes oder Distance-Bugs (100 km Plan → 200 km Route). Daher wurden fuer Bodensee-
Stadt-Cluster manuelle Pool-Routes mit echten Cities als Waypoints erzeugt.

Spätere Iterationen: dasselbe für Konstanz, Lindau, Stuttgart, Karlsruhe, Augsburg.
