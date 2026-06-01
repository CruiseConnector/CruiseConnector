# Self-hosted Map-Tiles — Setup & Aktivierung

> Ziel: die teuren Mapbox-Tile-Requests ablösen. Die App hat bereits eine
> umschaltbare Tile-Quelle + Auto-Mapbox-Fallback. Es fehlt nur noch **eine
> Tile-Datei** + ihre URL.

---

## TL;DR (der schnelle Weg)
1. **Eine `.pmtiles`-Datei für DACH** in ~Minuten erstellen (`pmtiles extract` aus dem fertigen Protomaps-Build — **kein** stundenlanger eigener Build).
2. Die Datei auf **Cloudflare R2** legen (öffentlich, mit CORS + Range).
3. Mir die **URL geben** → ich baue den App-Teil (Vektor-Rendering + Dark-Style + Mapbox-Fallback).

→ Danach: **0 € pro Tile, kein laufender Server, unbegrenzt skalierbar.**

---

## Welches Gerät macht was?

| Aufgabe | Gerät | Häufigkeit |
|---|---|---|
| `pmtiles`-Datei erstellen (`extract`) | **dein Mac** | einmalig (Update alle paar Monate) |
| Datei hosten | **Cloudflare R2** (Cloud) | läuft von allein |
| App-Teil (Rendering) | **ich** im Code | einmalig |
| GraphHopper | bleibt auf **PC1/PC2** | unverändert |

→ **PC1/PC2 fasst du dafür nicht an** (das war deine „packen die PCs das?"-Sorge — die Antwort: sie müssen es nicht). Der Mac macht nur den einmaligen Download-Schnitt; gehostet wird in der Cloud.

---

## Vorab-Entscheidung: Vektor (empfohlen) vs. Raster

**A) Vektor-PMTiles — empfohlen.** Eine `.pmtiles`-Datei (Vektor), die App rendert
den Style live. Vorteile: **kein** Vorrender-Schritt, eine Datei (~5 GB DACH bei
Zoom 14), **scharf bei jedem Zoom**, Dark-Style frei anpassbar, App liest die Datei
direkt per HTTP-Range — **kein Server, kein Worker**. Nachteil: einmaliger App-Umbau
(`vector_map_tiles_pmtiles`) — **den mache ich**.

**B) Raster — nur falls kein App-Umbau gewünscht.** Bräuchte einen
Vektor→PNG-Render-Schritt (tileserver-gl) — aufwändiger, größer. Passt zwar
exakt zur jetzigen Raster-Infrastruktur, lohnt aber selten.

→ **Wir nehmen A.**

---

## Schritt 1 — DACH-`.pmtiles` erstellen (auf dem Mac, ~Minuten)

```bash
# pmtiles-CLI installieren (offizielle Homebrew-Formula — KEIN Tap!)
brew install pmtiles
# Alternativ ohne Homebrew: Binary von github.com/protomaps/go-pmtiles/releases laden.
# Prüfen, dass es läuft:
pmtiles version

# Erst die Größe abschätzen (lädt nichts herunter, nur --dry-run):
GODEBUG=http2client=0 pmtiles extract https://build.protomaps.com/20260601.pmtiles dach.pmtiles \
  --bbox=5.5,45.7,17.2,55.1 --maxzoom=14 --dry-run

# Dann wirklich nur DACH herausschneiden (lädt via HTTP-Range NUR die DACH-Tiles):
# --bbox = minLon,minLat,maxLon,maxLat  (DACH inkl. LI + Puffer)
GODEBUG=http2client=0 pmtiles extract https://build.protomaps.com/20260601.pmtiles dach.pmtiles \
  --bbox=5.5,45.7,17.2,55.1 --maxzoom=14
```
- Den aktuellen Build-Dateinamen (z. B. `20260601.pmtiles`) findest du unter <https://maps.protomaps.com/builds/> — nimm den neuesten und setze ihn oben ein.
- **Verifizierte DACH-Größen (2026-06-01):** `--maxzoom=13` ≈ **2,6 GB**, `--maxzoom=14` ≈ **5,1 GB** (empfohlen — Straßen/Kurven klar), `--maxzoom=15` ≈ **10 GB** (Hausnummern-Ebene, fürs Cruisen Overkill). `--dry-run` zeigt dir die Größe immer vorab.
- Diese Größe ist die Datei **auf R2** — der Nutzer lädt sie **nicht** komplett, die App streamt per HTTP-Range nur die paar sichtbaren Tiles (wenige MB pro Fahrt).

> **WICHTIG — `GODEBUG=http2client=0` davorsetzen:** Der Protomaps-Build liegt
> hinter Cloudflare, und dessen HTTP/2 bricht den Range-Stream nach ~Minuten mit
> `stream error: INTERNAL_ERROR; received from peer` ab (verifiziert — passiert
> auch mit `--download-threads=1`). Das `GODEBUG=http2client=0` zwingt den
> pmtiles-Downloader auf **HTTP/1.1**, das kein Stream-Multiplexing kennt — damit
> lief der Extract sofort in Sekunden durch. Immer voranstellen.
> Falls es trotzdem klemmt: Source-Cooperative-Mirror nutzen
> (<https://beta.source.coop/repositories/protomaps/openstreetmap/>).

---

## Schritt 2 — Auf Cloudflare R2 hochladen

1. Cloudflare → **R2** → Bucket anlegen (z. B. `cruise-tiles`).
2. `dach.pmtiles` hochladen (Dashboard-Upload oder `rclone`/`wrangler r2 object put`).
3. **Öffentlichen Zugriff** aktivieren: Bucket → Settings → *Public access* (r2.dev-URL) **oder** eigene Domain (`tiles.cruiseconnect.app`).
4. **CORS** erlauben (die App liest per Range aus dem Browser/Client):
   ```json
   [{ "AllowedOrigins": ["*"], "AllowedMethods": ["GET","HEAD"],
      "AllowedHeaders": ["range","if-match"], "ExposeHeaders": ["etag","content-range","content-length"] }]
   ```
   (R2 unterstützt HTTP-Range nativ — genau das braucht PMTiles.)
5. Du bekommst eine URL wie:
   `https://<bucket>.r2.dev/dach.pmtiles` oder `https://tiles.cruiseconnect.app/dach.pmtiles`.

---

## Schritt 3 — URL an mich → App-Teil

Gib mir die `.pmtiles`-URL. Dann baue ich:
- `vector_map_tiles_pmtiles` als Quelle (liest die Datei direkt per Range),
- einen **Dark-Style** (`ProtomapsThemes.dark` als Basis, an unseren Look angepasst),
- den **Mapbox-Fallback** beibehalten (wenn die R2-Datei mal nicht erreichbar ist → Mapbox),
- einen **Umschalter Mapbox ↔ self-hosted**, damit du den Look **vergleichst, bevor** Mapbox abgedreht wird.

---

## Style-Hinweis (ehrlich)
Mapbox `dark-v11` ist proprietär und **nicht 1:1** kopierbar. Der Protomaps-Dark-
Theme kommt nah dran; mit Feintuning ~90–95 % desselben Looks. Da der Style hier
**clientseitig** liegt, kann ich ihn frei nachjustieren (Farben, Straßenbreiten).

## Kosten & Skalierung
- **R2:** Speicher ~0,015 $/GB/Monat, **keine Egress-Kosten**, Gratis-Tier großzügig.
- **Pro Tile: 0 €.** Egal ob 10 oder 10.000 Nutzer.
- PCs unbelastet (nur GraphHopper).

## Wichtig
- PMTiles-**Schema muss zum Style passen**: Protomaps-Build → Protomaps-Theme.
  Mapbox-/OpenMapTiles-Styles sind **nicht** mit Protomaps-Tiles kompatibel — darum
  baue ich den Style passend zum Protomaps-Schema.

---

### Quellen
- [Protomaps – Building a custom basemap / Downloads](https://docs.protomaps.com/basemaps/downloads)
- [pmtiles CLI (extract)](https://docs.protomaps.com/pmtiles/cli)
- [Protomaps auf Cloudflare](https://docs.protomaps.com/deploy/cloudflare)
- [vector_map_tiles_pmtiles (pub.dev)](https://pub.dev/packages/vector_map_tiles_pmtiles)
- [planetiler (eigener Build, Alternative)](https://github.com/onthegomap/planetiler)
