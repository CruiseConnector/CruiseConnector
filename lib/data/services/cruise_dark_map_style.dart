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
// Look angelehnt an Mapbox dark-v11, damit der gewohnte Cruise-Look erhalten
// bleibt — nur eben kostenlos aus eigenen Tiles statt teuren Mapbox-Requests.

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
    {
      'id': 'landcover',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'landcover',
      'paint': {'fill-color': '#101822', 'fill-opacity': 0.55},
    },
    {
      'id': 'landuse',
      'type': 'fill',
      'source': 'protomaps',
      'source-layer': 'landuse',
      'paint': {'fill-color': '#111922', 'fill-opacity': 0.5},
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
      'paint': {'fill-color': '#19212c', 'fill-opacity': 0.9},
    },
    // ── Straßen: dunkel→hell nach Wichtigkeit, für klaren Kontrast ──
    {
      'id': 'roads-minor',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['in', 'kind', 'minor_road', 'other', 'path'],
      'minzoom': 12,
      'paint': {
        'line-color': '#2a313d',
        'line-width': ['interpolate', ['linear'], ['zoom'], 12, 0.5, 16, 2.5],
      },
    },
    {
      'id': 'roads-medium',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'medium_road'],
      'paint': {
        'line-color': '#39434f',
        'line-width': ['interpolate', ['linear'], ['zoom'], 8, 0.6, 16, 4.0],
      },
    },
    {
      'id': 'roads-major',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'major_road'],
      'paint': {
        'line-color': '#46515f',
        'line-width': ['interpolate', ['linear'], ['zoom'], 6, 0.8, 16, 5.0],
      },
    },
    {
      'id': 'roads-highway',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'roads',
      'filter': ['==', 'kind', 'highway'],
      'paint': {
        'line-color': '#5b6a82',
        'line-width': ['interpolate', ['linear'], ['zoom'], 5, 1.0, 16, 6.5],
      },
    },
    {
      'id': 'boundaries',
      'type': 'line',
      'source': 'protomaps',
      'source-layer': 'boundaries',
      'paint': {
        'line-color': '#323b48',
        'line-width': 0.8,
        'line-dasharray': [2, 2],
      },
    },
    // ── Orts-Labels für Orientierung ──
    {
      'id': 'places',
      'type': 'symbol',
      'source': 'protomaps',
      'source-layer': 'places',
      'layout': {
        'text-field': ['get', 'name'],
        'text-size': ['interpolate', ['linear'], ['zoom'], 6, 11, 12, 14],
      },
      'paint': {
        'text-color': '#9aa4b2',
        'text-halo-color': '#0b0e13',
        'text-halo-width': 1.4,
      },
    },
  ],
};
