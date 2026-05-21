# Mapbox-Hack Löschungs-Inventur (Task 9)

**Stand:** 2026-05-21
**Wartet auf:** Erfolgreicher App-Live-Test im Simulator/Device
**Total:** ~15.100 Zeilen Code in alter Edge-Function + abhängiger Server-Code

---

## Wichtige Sicherheitsregel

**❌ NICHT LÖSCHEN bis User explizit grünes Licht gibt nach dem App-Live-Test.**

Rollback-Path: Wenn ein Live-Test-Issue auftaucht, muss man Flutter über
`lib/data/services/route_service.dart:70` (Konstante `edgeFunction`)
auf `'generate-cruise-route'` zurücksetzen können. Das funktioniert nur
solange die alte Edge-Function noch existiert.

---

## Was wird gelöscht

### Edge Function `generate-cruise-route` (15.100 Zeilen)

| Datei | Zeilen | Zweck |
|---|---|---|
| `supabase/functions/generate-cruise-route/index.ts` | 3867 | HTTP-Handler + Mapbox-Orchestration |
| `supabase/functions/generate-cruise-route/roundtrip_search.ts` | 3799 | Mapbox Round-Trip Heuristik (15K-Hack) |
| `supabase/functions/generate-cruise-route/route_quality.ts` | 2564 | Post-hoc Quality-Scoring |
| `supabase/functions/generate-cruise-route/roundtrip_waypoints.ts` | 1869 | Sub-Waypoint-Generierung |
| `supabase/functions/generate-cruise-route/point_to_point.ts` | 645 | A→B Routing |
| `supabase/functions/generate-cruise-route/mapbox_client.ts` | 623 | Mapbox-Wrapper |
| `supabase/functions/generate-cruise-route/waypoint_roundtrip.ts` | 578 | Closed-Loop-Waypoints |
| `supabase/functions/generate-cruise-route/route_quality_test.ts` | 345 | Unit-Tests |
| `supabase/functions/generate-cruise-route/routing_utils.ts` | 296 | Helper-Funktionen |
| `supabase/functions/generate-cruise-route/routing_types.ts` | 283 | TypeScript-Types |
| `supabase/functions/generate-cruise-route/routing_request_utils.ts` | 114 | Request-Parsing |
| `supabase/functions/generate-cruise-route/mapbox_client_test.ts` | 72 | Mapbox-Unit-Tests |
| `supabase/functions/generate-cruise-route/routing_debug.ts` | 45 | Debug-Logging |
| `supabase/functions/generate-cruise-route/deno.json` | - | Deno-Manifest |
| `supabase/functions/generate-cruise-route/deno.lock` | - | Deno-Lockfile |
| `supabase/functions/generate-cruise-route/tsconfig.json` | - | TypeScript-Config |
| `supabase/functions/generate-cruise-route/.npmrc` | - | npm-Config |

### Verwandter Tooling-Code (Mapbox-Healing-Worker)

Diese könnten weiterhin nützlich sein für Pool-Healing oder migriert werden:

| Datei | Beibehalten? |
|---|---|
| `supabase/functions/tools/route_pool_healing_worker.ts` | **JA** (Pool-Healing existiert weiterhin, nutzt aber jetzt v2 via Edge-Adapter) |
| `supabase/functions/tools/route_pool_seed_builder.ts` | **JA** (für kuratierte Pool-Seeds) |

**Nach Migration v2 muss der Healing-Worker GraphHopper statt Mapbox verwenden — siehe separate Task wenn Pool-Healing nochmal genutzt werden soll.**

---

## Löschungs-Befehle (nur nach Approval)

```bash
# 1. Verify v2 ist deployed und aktiv
supabase functions list --project-ref tlcfaxvvqzobmzwvfnvb | grep generate-cruise-route

# 2. Optional: alte Edge-Function von Supabase entfernen
supabase functions delete generate-cruise-route --project-ref tlcfaxvvqzobmzwvfnvb

# 3. Lokalen Code löschen
rm -rf supabase/functions/generate-cruise-route/

# 4. Commit
git add -A && git commit -m "chore: remove 15K Mapbox-hack edge function (replaced by v2 GraphHopper-Adapter)"
```

---

## Verbleibende Mapbox-Abhängigkeiten (im Flutter)

Die Mapbox-SDK in Flutter wird **weiterhin benötigt** für:
- Map-Rendering (Tiles + Style)
- Offline-Map-Caching
- Geocoding (Adress-Suche)

Was NICHT mehr benötigt wird:
- Mapbox Directions API (jetzt GraphHopper)
- Mapbox Map-Matching (war Teil der 15K-Heuristik, nicht in v2)

`core/constants.dart` Mapbox-Token bleibt für die Maps drin — nicht löschen.

---

## Rollback-Plan

Falls nach dem App-Live-Test ein kritischer Bug auftaucht:

```dart
// lib/data/services/route_service.dart:70
static const String edgeFunction = 'generate-cruise-route';  // zurück zu v1
```

So lange `generate-cruise-route/` noch existiert, ist der Rollback ein 1-Zeilen-Commit.
**Erst nach 7 Tagen ohne kritische Bugs sollte die Löschung erfolgen.**
