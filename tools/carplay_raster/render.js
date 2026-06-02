import puppeteer from 'puppeteer';
import fs from 'fs';
import path from 'path';

// ── Konfig ───────────────────────────────────────────────────────────────
const STYLE = JSON.parse(fs.readFileSync('/tmp/cc_raster/style.json', 'utf8'));
const OUT = '/tmp/cc_raster/tiles';
const MAPLIBRE_JS = '/tmp/cc_raster/node_modules/maplibre-gl/dist/maplibre-gl.js';
const PMTILES_JS = '/tmp/cc_raster/node_modules/pmtiles/dist/pmtiles.js';

// Region + Zoombereich aus argv: bbox=minLon,minLat,maxLon,maxLat  minz maxz
const bbox = (process.argv[2] || '9.35,47.18,9.95,47.62').split(',').map(Number);
const minZ = parseInt(process.argv[3] || '9', 10);
const maxZ = parseInt(process.argv[4] || '13', 10);
const [minLon, minLat, maxLon, maxLat] = bbox;

const lon2x = (lon, z) => Math.floor(((lon + 180) / 360) * 2 ** z);
const lat2y = (lat, z) =>
  Math.floor(
    ((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z
  );
const x2lon = (x, z) => (x / 2 ** z) * 360 - 180;
const y2lat = (y, z) => {
  const n = Math.PI - (2 * Math.PI * y) / 2 ** z;
  return (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
};

const tiles = [];
for (let z = minZ; z <= maxZ; z++) {
  const x0 = lon2x(minLon, z), x1 = lon2x(maxLon, z);
  const y0 = lat2y(maxLat, z), y1 = lat2y(minLat, z);
  for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) tiles.push({ z, x, y });
}
console.log(`Tiles zu rendern: ${tiles.length} (z${minZ}-${maxZ}, bbox ${bbox})`);

const browser = await puppeteer.launch({
  headless: true,
  args: [
    '--no-sandbox',
    '--disable-web-security',
    '--enable-unsafe-swiftshader', // Chrome >=119: erlaubt Software-WebGL headless
    '--use-angle=swiftshader',
    '--ignore-gpu-blocklist',
    '--enable-webgl',
  ],
});
const page = await browser.newPage();
await page.setViewport({ width: 512, height: 512, deviceScaleFactor: 2 });
page.on('console', (m) => { const t = m.text(); if (/error|fail/i.test(t)) console.log('  [page]', t); });
await page.setContent('<div id="map" style="width:512px;height:512px"></div>');
await page.addStyleTag({ path: '/tmp/cc_raster/node_modules/maplibre-gl/dist/maplibre-gl.css' });
await page.addScriptTag({ path: PMTILES_JS });
await page.addScriptTag({ path: MAPLIBRE_JS });

await page.evaluate((style) => {
  const proto = new pmtiles.Protocol();
  maplibregl.addProtocol('pmtiles', proto.tile);
  window._map = new maplibregl.Map({
    container: 'map', style, center: [9.65, 47.4], zoom: 11,
    interactive: false, attributionControl: false, fadeDuration: 0, preserveDrawingBuffer: true,
  });
  window._ready = new Promise((res) => window._map.on('load', res));
}, STYLE);
await page.evaluate(() => window._ready);

let done = 0, t0 = Date.now();
for (const { z, x, y } of tiles) {
  const cLon = x2lon(x + 0.5, z), cLat = y2lat(y + 0.5, z);
  await page.evaluate((lon, lat, zoom) => new Promise((res) => {
    window._map.jumpTo({ center: [lon, lat], zoom });
    window._map.once('idle', () => requestAnimationFrame(() => requestAnimationFrame(res)));
  }), cLon, cLat, z);
  const dataUrl = await page.evaluate(() => window._map.getCanvas().toDataURL('image/png'));
  const dir = path.join(OUT, String(z), String(x));
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${y}.png`), Buffer.from(dataUrl.split(',')[1], 'base64'));
  if (++done % 20 === 0 || done === tiles.length) {
    const rate = done / ((Date.now() - t0) / 1000);
    console.log(`  ${done}/${tiles.length}  (${rate.toFixed(1)} tiles/s)`);
  }
}
await browser.close();
console.log(`FERTIG: ${done} Tiles → ${OUT}`);
