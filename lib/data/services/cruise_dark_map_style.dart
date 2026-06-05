// Cruise-Dark-Kartenstil für die self-hosted Protomaps-Vektor-Tiles.
//
// 2026-06-02 (vucko): Eigenes Mapbox-GL-Style-JSON, das die 9 Protomaps-Layer
// (earth, landcover, landuse, water, roads, buildings, boundaries, places, pois)
// im Mapbox-Dark-v11-Look rendert — dunkler Grund, abgestufte Straßenhelligkeit
// für Kontrast, dezentes Wasser/Gebäude, helle Orts-Labels. Wird per
// ThemeReader().read(cruiseDarkMapStyle) in ein vector_tile_renderer-Theme
// übersetzt und der VectorTileLayer übergeben. Source-Key MUSS 'protomaps' sein
// (passt zu TileProviders({'protomaps': ...})).
//
// 2026-06-02 (vucko) — Überarbeitung „gut bei JEDEM Zoom":
//   • Straßen heller + breiter + Breite bis Zoom 20 interpoliert (vorher nur bis
//     16 → nah reingezoomt wirkten Straßen dünn/dunkel/„leer").
//   • Casing (dunkle Unterlinie) für Haupt-/Autobahnen → Straßen „poppen" wie
//     bei Mapbox, klare Kanten gegen den dunklen Grund.
//   • landcover/landuse mit maxzoom 15 gekappt → die großen Flächen-Polygone
//     werden beim starken Reinzoomen NICHT mehr als graue Schlieren über den
//     Bildschirm gestreckt (das war das „komische alte Design").
//   • Orts-Labels größer + heller + stärkerer Halo → Bregenz/Hohenems usw. klar
//     lesbar.
// Zusammen mit layerMode: vector (statt raster) ist die Karte damit bei jeder
// Zoomstufe scharf, ohne dass man erst pannen muss.

const Map<String, dynamic> cruiseDarkMapStyle = {
  'version': 8,
  'name': 'Cruise Dark',
  'sources': {
    'protomaps': {'type': 'vector'},
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': '#0b0e13'},
    },
    {
      'id': 'earth',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'earth',
      'paint': {'fill-color': '#0d1117'},
    },
    // 2026-06-03 (vucko): landcover + landuse Layer KOMPLETT ENTFERNT (nicht nur
    // fill-opacity 0). Der vector_tile_renderer der App zeichnete die Wald-/
    // Feld-Polygone TROTZ opacity 0 als helle, eckige Facetten auf den Hügeln
    // (User-Screenshot „komische Muster/Kontraste"). Ein ENTFERNTER Layer kann
    // gar nicht rendern → garantiert weg. Nur noch earth (einheitlich dunkel)
    // + water + Straßen + Labels.
    {
      'id': 'water',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'water',
      // 2026-06-05 (vucko): NUR echtes Wasser (Seen/Flüsse/Bodensee/Rhein/Kanäle).
      // Fake-Wasser raus — swimming_pool/fountain/dock/basin (+ water/kind_detail=
      // basin) sind Pools/Brunnen/Rückhaltebecken: als Wasser markiert, aber keine
      // Seen. Streams/Rivers/Canals sind ohnehin LINES (rendern nicht im fill).
      // Gleicher Filter wie in assets/map/cruise_dark.json (Single Source of Truth).
      'filter': [
        'all',
        ['in', 'kind', 'ocean', 'lake', 'river', 'water'],
        ['!in', 'kind_detail', 'basin'],
      ],
      'paint': {'fill-color': '#16273b'},
    },
    {
      'id': 'buildings',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'buildings',
      'minzoom': 13,
      'paint': {'fill-color': '#1c2430', 'fill-opacity': 0.85},
    },
    {
      // 2026-06-02 (vucko): Ländergrenzen deutlich sichtbarer (User-Wunsch).
      // Vorher dunkel (#3a4452) + dünn (0.9) → kaum erkennbar. Jetzt hell,
      // zoom-skaliert breiter + leichter Glanz, damit man die Grenze CH/AT/DE/LI
      // (Hohenems liegt am Dreiländereck) klar sieht.
      'id': 'boundaries',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'boundaries',
      // 2026-06-02 (vucko): NUR Ländergrenzen (kind=country) — Bundesland-/
      // Regionsgrenzen (kind=region) raus, das war zu viel (User-Wunsch).
      'filter': ['in', 'kind', 'country', 'unrecognized_country'],
      'paint': {
        // 2026-06-03 (vucko): Grenze KLAR sichtbar, aber nicht grell. Weiß
        // (#b3bdce) war zu hart, Schiefer-Grau (#2e3742@0.5) kaum erkennbar.
        // Jetzt ein klares mittleres Grau-Blau, deutliche Striche, etwas breiter,
        // fast volle Deckkraft → die Grenze CH/AT/DE/LI ist eindeutig erkennbar.
        'line-color': '#8c99b3',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          3, 1.0, 6, 1.8, 9, 2.6, 13, 3.6,
        ],
        'line-dasharray': [3, 2],
        'line-opacity': 0.92,
      },
    },
    // ── Straßen: dunkel→hell nach Wichtigkeit, Breite bis Zoom 20 ──
    {
      'id': 'roads-minor',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      // 2026-06-03 (vucko): NUR echte Nebenstraßen — 'path' + 'other' (Wander-/
      // Feld-/Forstwege) ENTFERNT, minzoom 12 → 13. Die zeichneten in alpinem
      // Gelände ein dichtes Linien-Netz über alle Hänge (das „komische Muster"
      // aus dem User-Screenshot Schwarzenberg/Bregenzerwald). Eine Cruise-Karte
      // braucht keine Trampelpfade — nur befahrbare Straßen.
      'filter': ['==', 'kind', 'minor_road'],
      'minzoom': 13,
      'paint': {
        'line-color': '#363e4a',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          13, 0.5, 15, 1.4, 16, 2.6, 20, 9.0,
        ],
      },
    },
    {
      'id': 'roads-medium',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      // 2026-06-03 (vucko): minzoom 12. medium_road hatte KEIN minzoom → in den
      // Alpen ein dichtes Linien-Netz schon beim Überblick (z≈11, genau die
      // User-Ansicht „Kontrast/Muster"). Bei Überblick (z<12) zeigt die Karte
      // jetzt NUR earth (einheitlich) + Wasser + Grenzen + Haupt-/Autobahnen +
      // Labels → garantiert clean, kein Web. Ab z12 (Detail/Routen-Inspektion)
      // kommen die Nebenstraßen sauber dazu.
      'filter': ['==', 'kind', 'medium_road'],
      'minzoom': 12,
      'paint': {
        'line-color': '#48515f',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          12, 0.8, 14, 2.4, 16, 5.0, 20, 16.0,
        ],
      },
    },
    // Casing (dunkle, breitere Unterlinie) für Hauptstraßen → klare Kante.
    {
      'id': 'roads-major-casing',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'major_road'],
      'paint': {
        'line-color': '#1c222b',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          6, 1.8, 14, 5.2, 16, 9.5, 20, 26.0,
        ],
      },
    },
    {
      'id': 'roads-major',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'major_road'],
      'paint': {
        'line-color': '#545f6e',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          6, 1.0, 14, 3.4, 16, 6.5, 20, 20.0,
        ],
      },
    },
    {
      'id': 'roads-highway-casing',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'highway'],
      'paint': {
        'line-color': '#262e3a',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          5, 2.4, 14, 6.8, 16, 12.0, 20, 30.0,
        ],
      },
    },
    {
      'id': 'roads-highway',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'highway'],
      'paint': {
        'line-color': '#6f7f99',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          5, 1.4, 14, 4.8, 16, 8.8, 20, 24.0,
        ],
      },
    },
    // ── Orts-Labels: größer + heller + starker Halo für Lesbarkeit ──
    {
      'id': 'places',
      'type': 'symbol',
      'source': 'protomaps',
      'source-layer': 'places',
      // 2026-06-05 (vucko): NUR Städte/Hauptorte — city/town. „village" raus
      // (User: nur Hauptorte wie Dornbirn/Götzis, keine Dörfer). Synchron zu
      // assets/map/cruise_dark.json + carplay style.json. Weiler/Ortsteile/
      // Flurnamen (hamlet, suburb, locality …) waren ohnehin schon draußen.
      'filter': ['in', 'kind_detail', 'city', 'town'],
      'layout': {
        'text-field': ['get', 'name'],
        // 2026-06-02 (vucko): Orte sollen klar HERAUSSTECHEN — größer als die
        // Straßen, damit man den Überblick behält (Hohenems/Götzis/Altach …).
        'text-size': [
          'interpolate', ['linear'], ['zoom'],
          6, 13, 9, 16, 12, 20, 15, 24, 18, 27,
        ],
        'text-max-width': 7,
      },
      'paint': {
        'text-color': '#f3f6fa',
        'text-halo-color': '#04070b',
        'text-halo-width': 2.8,
      },
    },
  ],
};
