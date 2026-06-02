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
    // Flächen (Wald/Grün/Nutzung) nur bis Zoom 15 — darüber (Straßen-Level)
    // würden die großen Polygone überzoomt als Schlieren gestreckt.
    // 2026-06-02 (vucko): Flächen NAH an der Erdfarbe (#0d1117) gehalten —
    // vorher hoben sich Wald-/Nutzungs-Polygone als deutliche hellere Blöcke
    // ab („Kontrast-Flächen", User-markiert). Jetzt nur noch ein Hauch
    // Unterschied → einheitlicher dunkler Look, Nebenstraßen bleiben sichtbar.
    {
      'id': 'landcover',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'landcover',
      'maxzoom': 15,
      'paint': {'fill-color': '#0d1219', 'fill-opacity': 0.35},
    },
    {
      'id': 'landuse',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'landuse',
      'maxzoom': 15,
      'paint': {'fill-color': '#0e131b', 'fill-opacity': 0.28},
    },
    {
      'id': 'water',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'water',
      'paint': {'fill-color': '#16212f'},
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
        // 2026-06-02 (vucko): noch erkennbarer — heller, breiter, dichtere
        // Striche (mehr Linie/weniger Lücke), volle Deckkraft.
        'line-color': '#b3bdce',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          3, 1.4, 6, 2.4, 9, 3.4, 13, 4.8,
        ],
        'line-dasharray': [3, 1.1],
        'line-opacity': 1.0,
      },
    },
    // ── Straßen: dunkel→hell nach Wichtigkeit, Breite bis Zoom 20 ──
    {
      'id': 'roads-minor',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['in', 'kind', 'minor_road', 'other', 'path'],
      'minzoom': 12,
      'paint': {
        'line-color': '#38404c',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          12, 0.6, 14, 1.6, 16, 3.4, 20, 11.0,
        ],
      },
    },
    {
      'id': 'roads-medium',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'medium_road'],
      'paint': {
        'line-color': '#48515f',
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          9, 0.6, 14, 2.4, 16, 5.0, 20, 16.0,
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
      // 2026-06-02 (vucko): NUR echte Siedlungen — Stadt/Ort/Dorf
      // (kind_detail = city/town/village). Weiler/Ortsteile/Quartiere
      // (hamlet, suburb, neighbourhood, locality, isolated_dwelling …) und
      // Flur-/Einzelnamen wie „Plattentöbele"/„Suldis"/„Sportplatz" raus —
      // das war viel zu viel Info für den User.
      'filter': ['in', 'kind_detail', 'city', 'town', 'village'],
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
