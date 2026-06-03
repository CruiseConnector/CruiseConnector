# Compact-Resume — CruiseConnect

> ## ⭐ 2026-06-03 — ROUTING-STABILISIERUNG (laufende Session)
>
> **Symptom (User):** Rundkurs + A→B seit Mapbox→GraphHopper-Umstieg kaputt:
> „keine Route" auf dem Gerät (im Simulator unsichtbar), Autobahn-Regel ignoriert,
> hässliche U-Turns, komische Formen.
>
> **3 ROOT CAUSES gefunden + gefixt (alle live bewiesen, Edge v2 neu deployt):**
> 1. **Auth/„keine Route":** `generate-cruise-route-v2` war als EINZIGE Funktion
>    mit `verify_jwt:true` deployt (config.toml-Block fehlte). Die App schickt
>    einen `sb_publishable_…`-Key (kein JWT) → Gateway wies ihn als „Invalid JWT"
>    ab. Im Simulator unsichtbar (frische Session = gültiger JWT), auf dem Gerät
>    nach Token-Ablauf → 401. **Fix:** `[functions.generate-cruise-route-v2]
>    verify_jwt=false` in `supabase/config.toml` + neu deployt. **DURABLE** —
>    ohne diesen Block setzt JEDER künftige Deploy den Bug neu.
> 2. **custom_model wurde IGNORIERT (DER große Fix):** Edge schickte GraphHopper
>    per **GET**-Query → GH ehrt `custom_model` NUR per **POST**-Body (an PC1+PC2
>    direkt bewiesen: GET avoid=true≡avoid=false; POST → Autobahn weg). Darum
>    wirkten Autobahn-Block, Stil-Overlays, Track/Service-Penalty, Ferry NIE.
>    **Fix:** `callGraphHopper` komplett auf POST umgestellt (points als [lng,lat],
>    round_trip-Params als dotted keys `round_trip.distance`/`.seed`, custom_model
>    als Objekt). → **Autobahn-Verletzungen 43→0** über 96-Suchen-Matrix.
> 3. **Selektion liess Autobahn/U-Turns durch:** `isAcceptable`/Best-of-N prüften
>    weder `uses_motorway` noch U-Turns. **Fix:** motorway split von trunk,
>    `u_turn_count` aus Instructions, isAcceptable rejectet beides, Best-of-N
>    highwayPenalty 1000 + uTurnPenalty 40. Motorway hart `priority:0` (trunk
>    bleibt erlaubt = Bundesstraße). Seed-Bump 5→6/8.
>
> **Matrix-Stand (96 Suchen, 6 Regionen × 4 Stile × 25/50/75/100km, Autobahn aus):**
> Autobahn **0/96** ✅ · Latenz alle <2.3s ✅ · Loop-Closure 0m ✅ · alle 200 ✅ ·
> 25/50km **sauber**. OFFEN: 75/100km je 1 U-Turn (GH-round_trip Tip-Turnaround am
> Via-Punkt), 100km Distanz-Überschuss in einigen Regionen (FH 100km +42%).
>
> **NÄCHSTE SCHRITTE:** (a) Simulator-Test iPhone 17 Pro Max — jeder Modus+km,
> Routen visuell prüfen (User-Pflicht-Gate vor Commit). (b) ggf. 75/100km-U-Turns
> via Wegpunkt-Polygon-Loop (start==end + via-Punkte als Point-to-Point statt
> GH-round_trip) — ehrt custom_model + kein Tip-Turnaround. (c) `flutter analyze`,
> dann commit+push in `graphhopper-dach-stabilize`.
> **Test-Harness:** `/tmp/cc_matrix.py all` (nutzt Publishable-Key, MW/TR/UT-Spalten).
> Edge-Quelle: `supabase/functions/generate-cruise-route-v2/index.ts` (callGraphHopper).

**Letztes Update**: 2026-06-03 (Routing-Stabilisierung — Auth+POST+Selektion gefixt)
**Branch**: `graphhopper-dach-stabilize`
**Worktree**: `/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f`
**Supabase Project-ID**: `tlcfaxvvqzobmzwvfnvb`
**App-Version**: `1.0.3+4` (pubspec + iOS pbxproj — synchron)

---

## 🚨 OFFENE AKTION (User ist weg, kommt zurück) — PC2-PBF-Migration

**Stand**: User hat `europe-latest.osm.pbf` (32 GB) auf PC2 heruntergeladen, ABER der **osmium extract Schritt fehlt** noch. Container-Start fail mit "Your specified OSM file does not exist: /data/dach-italy-balkan.osm.pbf".

**Was der User auf PC2 ausführen muss (wenn er zurück ist)**:

```bash
cd ~/gh-eu

# 1. Wo liegt europe-latest.osm.pbf?
ls -lh ~/gh-eu/europe-latest.osm.pbf ~/gh-eu/data/europe-latest.osm.pbf 2>&1

# 2. osmium extract (~5-10 Min Wartezeit, kein Progress visible)
osmium extract -b 5.5,42.0,18.5,50.5 europe-latest.osm.pbf -o data/dach-italy-balkan.osm.pbf --overwrite

# 3. Verifizieren (~5-6 GB erwartet)
ls -lh data/dach-italy-balkan.osm.pbf

# 4. Container starten (~30-45 Min Graph-Build)
docker rm -f gh-eu
docker run -d --name gh-eu --restart unless-stopped \
  -p 8989:8989 -p 8990:8990 \
  -v $PWD/data:/data \
  -v $PWD/config.yml:/graphhopper/config.yml \
  -v $PWD/custom_models:/graphhopper/custom_models \
  my-gh:8.0 \
  java -Xmx12g -Xms2g -jar graphhopper.jar server /graphhopper/config.yml
docker logs -f gh-eu

# 5. NACH Build → europe-latest löschen (spart 32 GB Disk)
rm ~/gh-eu/europe-latest.osm.pbf
```

**Ziel**: `Server started, listening on 0.0.0.0:8989` — dann routet Edge automatisch Cross-Border über PC2.

**Sofort danach Verifizieren** (von Mac):
```bash
python3 /tmp/test_cross_border.py
# Erwartung: München→Mailand, Bregenz→Verona, Graz→Ljubljana ALLE OK statt cross_border_unsupported
```

---

## 🏗 Architektur — wie es JETZT läuft

### Server-Topologie
- **PC1 (vucko1@vucko)** — DACH-Server (DE+AT+CH+LI), Port 8989
- **PC2 (vucko2@vucko2-HP-ProDesk)** — EU-Server, läuft AKTUELL noch mit `eu-south.osm.pbf` (IT+SI+HR+FR-Süd ohne DACH). Tailscale Funnel-URL: `https://vucko2-hp-prodesk-600-g5-desktop-mini.taildddd94.ts.net`
- Nach PC2-Migration: `dach-italy-balkan.osm.pbf` (DE+AT+CH+IT+SI+HR+FR-Süd in einer dedupzierten PBF aus europe-latest.osm.pbf bbox-extract 5.5,42.0,18.5,50.5)

### Edge-Function Routing-Logik (`generate-cruise-route-v2`)
- **DACH-only Routen** → PC1 primary (schneller, weniger Daten)
- **Alle anderen Routen** (EU-only ODER Cross-Border) → PC2 primary
- **PC1 ist Fallback** wenn PC2 offline
- **Cross-Border-Detection** in `chooseGraphhopperUrlForRoute` mit GeoRegion enum (dach/euSouth/euWest/euEast/unknown)
  - Region-Klassifikation Alpen-Linie lat 46.5 (Italien ≤46.5, AT ≥45.8)
  - Slowenien-Box explizit (45.42-46.55, 13.38-16.61) damit Klagenfurt (46.62) als AT erkennt

### Supabase Secrets
- `GRAPHHOPPER_URL` → PC1 (Tailscale)
- `GRAPHHOPPER_DE_URL` → ungenutzt (legacy)
- `GRAPHHOPPER_EU_URL` → PC2 Tailscale Funnel

---

## 📦 App-State

### Letzte Commits (neueste zuerst)
```
8c7eb12 feat(routing): PC2 wird primary für Cross-Border (dach-italy-balkan-pbf)
04a3bad chore: bump version to 1.0.3+4
c6373c4 perf(routing): Live-First default statt 50/50 Pool/Live Coin-Flip
eceab38 fix(routing): Region-Klassifikation mit Alpen-Linie 46.5 + Cross-Border-Prio
e315e3f feat(routing): Cross-Border-Detection + PC1-priority bei DACH-Mix
b1a4701 feat: aggressive Offline-Tiles + Reroute-UX + Vorarlberg-Speed
1e82bcc chore: bump version to 1.0.2+3 in pubspec + Xcode pbxproj
c661552 feat: Region-aware Route-Empfehlung + abwechslungsreiche Push-Texte
888d62a feat(routing): 3-Server-Architektur + Ultimate car-Fallback + Ferry-Fix
ec05e35 feat: Tour-Modus + Wetter-Inline + POI-Details + Home-Carousel
```

### Was 1.0.3 alles drin hat (über 1.0.0)
- **Tour-Modus** mit Pause/Resume (TripService + UI Carousel)
- **POI-Detail-Sheet** mit Live-Status (Jetzt offen / Schließt bald) + Wochentag-Tabelle
- **POI-Marker** Material-Icons statt Emoji
- **Wetter inline** als 5. Metric im Route-Banner (statt fette Glas-Card)
- **Mode-Explainer-Bubble** beim Klick auf bereits-aktiven Routen-Modus
- **Home-Carousel** für Trip-Resume + Heute-für-dich
- **Region-aware Recommendation** (100km Radius)
- **Push-Texte mit Varianten** (Wetter context-aware nach Temp + Tageszeit)
- **Live-First-Default** statt 50/50 Pool/Live → Vorarlberg <2s statt mehrere Min
- **Cross-Border-Detection** mit klarer User-Message
- **FH→Wien (695km)** funktioniert (Ferry-False-Positive Fix)
- **Offline-Map aggressiver** (Korridor um Route, 8000 Tiles, 100km Radius)
- **TopToast statt Snackbar** ("Keine Verbindung" + Reroute-Feedback)
- **Trip-Save+Resume UTC-Fix** (negative "läuft seit X Min" Bug)

---

## 🔧 Kritische Code-Locations

| Datei | Zweck | Größe |
|---|---|---|
| `lib/presentation/pages/cruise_mode_page.dart` | Routing-Hub + GPS-Tracking | ~8500 LoC |
| `lib/data/services/route_service.dart` | Edge-Wrapper + Pool-Logik | ~9300 LoC |
| `lib/data/services/trip_service.dart` | Tour-Save/Resume CRUD | ~174 LoC |
| `lib/data/services/offline_map_service.dart` | Tile-Cache | ~480 LoC |
| `lib/data/services/smart_reroute_engine.dart` | Off-Route-Logic | ~300 LoC |
| `lib/data/services/opening_hours_parser.dart` | OSM-Hours-Parser | ~250 LoC |
| `lib/data/services/notification_service.dart` | Realtime + Push-Texte | ~430 LoC |
| `lib/data/services/home_route_recommendation_service.dart` | Region-aware Empfehlung | ~510 LoC |
| `lib/presentation/pages/home_content_page.dart` | Home + Carousel | ~1860 LoC |
| `lib/presentation/widgets/cruise/poi_detail_sheet.dart` | POI-Popup | ~440 LoC |
| `lib/presentation/widgets/cruise/cruise_setup_card.dart` | Modus-Buttons + Explainer | ~860 LoC |
| `lib/presentation/widgets/cruise/mode_explainer_bubble.dart` | Tap-to-Explain | ~150 LoC |
| `lib/presentation/widgets/weather_inline.dart` | Inline-Wetter + Warning | ~250 LoC |
| `supabase/functions/generate-cruise-route-v2/index.ts` | Edge-Routing | ~1180 LoC |

---

## ⚠ Bekannte Edge-Cases / Pending

### Task #55 (pending) — München-OSM-Snap-Bug auf PC1-DACH
München-Stadt-Koordinaten (Marienplatz 48.13/11.58, Sendling, Garching) snappen asymmetrisch auf PC1: als END klappt München, als START oder Multi-Stop-WP nicht. PC2-Migration wird das wahrscheinlich automatisch lösen weil das `dach-italy-balkan.osm.pbf` saubere Daten hat.

### Test-Trip in DB (group_id=null)
Es liegt ein Test-Trip in `trips` mit id=`7bb95a29-9a4f-401b-aadb-2bd8734a4d01`, status=active, group_id=NULL. Mein Code-Filter `groupOnly:true` blendet ihn aus, aber falls Cleanup gewünscht:
```sql
update trips set status='completed', finished_at=now()
where id='7bb95a29-9a4f-401b-aadb-2bd8734a4d01';
```

---

## 🛠 User-Stil + Regeln (kritisch)

- Vucko schreibt Deutsch → Antworten auf Deutsch
- "Autobahn an / Autobahn aus" NICHT "AB-AN / AB-AUS"
- Ehrliche Diagnose, klare Optionen, dann User-Entscheidung
- User pushed selber nach größeren Sweeps (manchmal — heute meist commit+push selber)
- NIEMALS API-Keys aus core/constants.dart ausgeben
- Auto-Mode classifier blockt prod-DB-Writes ohne explizite User-Erlaubnis
- Worktree-Path: `/Users/vucko/Development/CruiserConnect/.claude/worktrees/admiring-hawking-3afe1f`
- supabase functions deploy LÄUFT lokal ohne Login (nicht aus Haupt-Repo, aus Worktree)
- SSH-Permission OK für vucko1@vucko + vucko2@vucko2-HP-ProDesk
- Cocoapods install braucht UTF-8 Locale: `cd ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install`

---

## 🚀 App-Build-Befehle (Version 1.0.3+4 ready)

### iOS (TestFlight)
```bash
flutter clean && flutter pub get
cd ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install && cd ..
flutter build ipa --release
# Upload via Transporter App: build/ios/ipa/cruise_connect.ipa
```

Falls Xcode-direkt-Archive: vorher in Xcode → Runner → General → Identity → Version 1.0.3, Build 4 manuell setzen wenn nicht aus pbxproj kommt.

### Android (Play Console)
```bash
flutter build appbundle --release --no-tree-shake-icons
# Output: build/app/outputs/bundle/release/app-release.aab
# Upload: Play Console → Internal Test
```

Keystore: `/Users/vucko/cruiseconnect-upload-keystore.jks` (NICHT im Git, in `android/key.properties` referenziert).

---

## 🧪 Test-Scripts (alle in /tmp/)

- `/tmp/full_route_test.py` — 14 Standard-Szenarien (Round-Trip + A→B + Trips + OOB)
- `/tmp/test_cross_border.py` — Cross-Border-Detection-Tests
- `/tmp/test_final.py` — Erwartet `cross_border_unsupported` als PASS
- `/tmp/test_vorarlberg_speed.py` — 32 Vorarlberg-Round-Trips Timing
- `/tmp/test_fh_wien.py` — FH→Wien (695km) Sanity-Check

---

## 📍 Coverage-Status nach PC2-Migration (Ziel)

| Land | PC1 | PC2 (jetzt) | PC2 (nach Migration) |
|---|---|---|---|
| 🇩🇪 Deutschland | ✅ | ❌ | ✅ |
| 🇦🇹 Österreich | ✅ | ❌ | ✅ |
| 🇨🇭 Schweiz | ✅ | ❌ | ✅ |
| 🇱🇮 Liechtenstein | ✅ | ❌ | ✅ |
| 🇮🇹 Italien | ❌ | ✅ | ✅ |
| 🇸🇮 Slowenien | ❌ | ✅ | ✅ |
| 🇭🇷 Kroatien | ❌ | ✅ | ✅ |
| 🇫🇷 Côte d'Azur + Elsass | ❌ | ✅ | ✅ |
| 🇫🇷 Restliches Frankreich (bis lat 50.5) | ❌ | ❌ | ✅ (bbox enthält Teil) |

---

## 🔄 Rückkehr nach Compact — Workflow

1. **Lies diese Datei zuerst** (`docs/COMPACT_RESUME.md`)
2. Frag User: "Hast du den `osmium extract` auf PC2 ausgeführt? Container läuft mit `dach-italy-balkan.osm.pbf`?"
3. `git log --oneline -10` für aktuelle Commit-State
4. `git status` für uncommitted Changes
5. Wenn PC2 noch nicht migriert: User-Anleitung von oben „🚨 OFFENE AKTION" geben
6. Wenn PC2 migriert: `python3 /tmp/test_cross_border.py` ausführen → bestätigen dass München→Mailand etc. jetzt routen
7. Bei Routing-Fragen: erst Edge-Function curl-Test machen, dann tiefer

## Cron-Worker

- `process_route_search_sessions_every_minute` — `* * * * *` (jede Min)
- `process_route_seed_jobs_every_2_minutes` — `* * * * *` (eigentlich jede Min trotz des Namens, max 5 jobs/run)
- `dach_pool_auto_seeder` — `*/15 * * * *`
- `daily-weather-push` — täglich 06:00 UTC

## Heartbeat (optional)
Aktuell pausiert (Task #12 completed). Kann via cron reaktiviert werden falls User es will.
