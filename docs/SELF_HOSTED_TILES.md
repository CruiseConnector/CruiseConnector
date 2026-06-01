# Self-hosted Map-Tiles — Setup & Aktivierung

> Ziel: die teuren Mapbox-Tile-Requests ablösen. Die App ist bereits umgebaut
> (umschaltbare Quelle + Auto-Mapbox-Fallback). Es fehlt nur noch die
> self-hosted Tile-Quelle + 1 Zeile Konfiguration.

## Aktueller Stand (App-Code, schon erledigt)
- `OfflineMapService.selfHostedTileUrlTemplate` = `null` → **reines Mapbox** (kein Risiko).
- Sobald hier eine URL steht **und** der Health-Check sie erreicht → self-hosted aktiv.
- Fällt sie aus (Health-Check / gehäufte Tile-Fehler) → **automatisch Mapbox**.
- Cache wird **pro Quelle getrennt** gehalten (kein Style-Mix).

---

## Wichtige Vorab-Entscheidung: Raster vs. Vektor
Die App rendert aktuell **Raster-Tiles** (`{z}/{x}/{y}.png`, wie Mapbox). Zwei Wege:

**A) Raster-Tiles vorgerendert + CDN (minimaler App-Umbau — empfohlen für den Start)**
Ein Tile-Server rendert PNGs aus OSM-Daten + Dark-Style; ein CDN cacht jedes
gerenderte Tile. → App ändert nur die URL. Server rendert jedes Tile **einmal**,
danach liefert das CDN (0 Last, unbegrenzt skalierbar).

**B) Vektor-PMTiles + clientseitiges Rendering (später, beste Qualität)**
Eine `.pmtiles`-Datei (Vektor) auf dem CDN, die App rendert den Style live
(schärfer, kleiner, frei stylebar). Braucht App-seitig `vector_map_tiles` —
das baue ich dann ein. Größerer Umbau, aber langfristig sauberer.

→ **Start mit A.** Umstieg auf B später möglich.

---

## Weg A — Schritt für Schritt

### 1. OSM-Daten holen (DACH)
```bash
# DACH-Extrakt von Geofabrik (DE+AT+CH separat oder europe + clip)
wget https://download.geofabrik.de/europe/dach-latest.osm.pbf   # falls vorhanden
# sonst: germany + austria + switzerland einzeln + osmium merge
```

### 2. Vektor-Tiles bauen (planetiler — schnell, 1 JAR)
```bash
java -Xmx8g -jar planetiler.jar --download \
  --osm-path=dach-latest.osm.pbf --output=dach.mbtiles
```

### 3. Dark-Style + Raster-Server (tileserver-gl, Docker)
```bash
# CARTO Dark Matter Style (nah an Mapbox-dark) als style.json ablegen
docker run --rm -it -v $(pwd):/data -p 8080:80 maptiler/tileserver-gl \
  --mbtiles dach.mbtiles
# liefert Raster unter: http://<server>:8080/styles/dark/256/{z}/{x}/{y}.png
```

### 4. CDN davorschalten (Cloudflare, Gratis-Tier)
- Domain (z. B. `tiles.cruiseconnect.app`) als Cloudflare-Proxy auf den Tile-Server.
- Cache-Regel: `*/styles/*` → **Cache Everything**, Edge-TTL hoch (Tiles sind statisch).
- → erste Anfrage rendert (Server), alle weiteren liefert das CDN.

### 5. URL in der App eintragen (1 Zeile)
`lib/data/services/offline_map_service.dart`:
```dart
static const String? selfHostedTileUrlTemplate =
    'https://tiles.cruiseconnect.app/styles/dark/256/{z}/{x}/{y}.png';
```
→ `flutter pub get` nicht nötig, nur neu bauen. Beim Start prüft der Health-Check
die URL; klappt sie, läuft self-hosted mit Auto-Fallback.

### 6. Vor dem Abdrehen von Mapbox: Style vergleichen
Ich baue dir einen **Umschalter** (Mapbox ↔ self-hosted) in die Karte, damit du
den Look direkt am Gerät vergleichst. Erst wenn dir der Style passt, bleibt es an.

---

## Style-Hinweis (wichtig)
Mapbox `dark-v11` ist proprietär und **nicht 1:1** kopierbar. **CARTO Dark Matter**
(OSM-basiert) kommt sehr nah; mit Feintuning ~90–95 % desselben Looks.

## Kosten
- Cloudflare CDN + R2: Gratis-Tier deckt sehr viel ab.
- Tile-Server-Rendering: einmalig pro Tile (dann CDN-cached) → vernachlässigbar.
- **Mapbox-Tile-Kosten: ~0 €**, sobald self-hosted aktiv.
