// App-Store / Play-Store Marketing-Screenshots im CruiseConnector-Design.
// Nimmt echte App-Screenshots aus raw/{apple,android}/<id>.(png|jpg) und rendert
// sie in das Marken-Design (Verlauf + rote Streaks + Logo + Headline + Telefon-
// Rahmen) per SVG -> rsvg-convert -> PNG nach out/{apple,android}/.
//
// Aufruf:  node store_screenshots/compose.mjs
// Es werden nur Features gerendert, deren raw-Datei existiert (Teilmengen ok).

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));

// Reihenfolge = Reihenfolge im Store. Headline: *…* markiert den roten Teil.
const FEATURES = [
  { id: 'roundtrip',  headline: ['Finde *Rundkurse*', 'die wirklich', 'Spaß machen.'], sub: 'Plane Distanz, Stil und Autobahn-Regeln in Sekunden.' },
  { id: 'navigation', headline: ['*Live*-Navigation', 'für jede Kurve.'],     sub: 'Klare Manöver, Restzeit und Route direkt im Fahrmodus.' },
  { id: 'preview',    headline: ['Jede Route,', '*perfekt geplant.*'],        sub: 'Distanz, Dauer und Kurven auf einen Blick, bevor du losfährst.' },
  { id: 'group',      headline: ['Fahrt *zusammen.*', 'Bleibt synchron.'],    sub: 'Gruppen-Code teilen, Rollen verteilen, gemeinsam losfahren.' },
  { id: 'stats',      headline: ['Fahre. Steig auf.', '*Werde Legende.*'],    sub: 'Level, XP, Streak und Badges für jede einzelne Fahrt.' },
  { id: 'route_end',  headline: ['Speichere', 'deine besten', '*Strecken.*'], sub: 'Nach der Fahrt: echte Strecke, Stats und Bewertung.' },
  { id: 'share',      headline: ['*Teile* deine', 'Fahrten.'],                sub: 'Strecke, Foto und Stats als Story in einem Tap.' },
  { id: 'profile',    headline: ['Dein Profil.', 'Deine *Maschinen.*'],       sub: 'Garage, Badges und alle deine Stats an einem Ort.' },
];

const PLATFORMS = {
  apple:   { w: 1242, h: 2688, chrome: 'island' },
  android: { w: 1080, h: 1920, chrome: 'punch' },
};

const RED = '#FF4D24';
const WHITE = '#FFFFFF';
const MUTED = '#9AA2B0';
const FONT = 'Helvetica Neue, Helvetica, Arial, sans-serif';

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// Headline-Zeile mit *…*-Rotmarkierung in tspans aufloesen.
function lineSpans(line, x, dy, size) {
  const parts = line.split('*');
  let inner = '';
  parts.forEach((p, i) => {
    if (!p) return;
    const fill = i % 2 === 1 ? RED : WHITE;
    inner += `<tspan fill="${fill}">${esc(p)}</tspan>`;
  });
  return `<tspan x="${x}" dy="${dy}">${inner}</tspan>`;
}

function findRaw(platform, id) {
  for (const ext of ['png', 'jpg', 'jpeg', 'PNG', 'JPG']) {
    const p = join(ROOT, 'raw', platform, `${id}.${ext}`);
    if (existsSync(p)) return p;
  }
  return null;
}

// Seitentasten am Rahmen (plattform-typisch), straddeln die Bezel-Kante.
function chromeButtons(chrome, phoneX, phoneY, phoneW, phoneH, W) {
  const bw = Math.round(0.011 * W);
  const rx = phoneX + phoneW;
  const lx = phoneX;
  const col = '#3a3f4d';
  const mk = (x, y, h) => `<rect x="${Math.round(x - bw / 2)}" y="${y}" width="${bw}" height="${h}" rx="${Math.round(bw * 0.35)}" fill="${col}"/>`;
  let s = '';
  if (chrome === 'island') {
    const lvolY = phoneY + Math.round(0.17 * phoneH);
    s += mk(lx, lvolY, Math.round(0.055 * phoneH));
    s += mk(lx, lvolY + Math.round(0.075 * phoneH), Math.round(0.055 * phoneH));
    s += mk(rx, phoneY + Math.round(0.21 * phoneH), Math.round(0.095 * phoneH));
  } else {
    const rvolY = phoneY + Math.round(0.15 * phoneH);
    s += mk(rx, rvolY, Math.round(0.10 * phoneH));
    s += mk(rx, rvolY + Math.round(0.125 * phoneH), Math.round(0.05 * phoneH));
  }
  return s;
}

function buildSvg(W, H, feat, rawPath, chrome) {
  const M = Math.round(0.066 * W);                 // linker Rand
  const logoSize = Math.round(0.035 * W);
  const logoY = Math.round(0.052 * H);
  const hSize = Math.round(0.082 * W);             // Headline-Groesse
  const hTop = Math.round(0.118 * H);              // Headline 1. Baseline
  const hGap = Math.round(0.0455 * H);             // Zeilenabstand
  const nLines = feat.headline.length;
  const subSize = Math.round(0.0305 * W);
  const subY = hTop + (nLines - 1) * hGap + Math.round(0.052 * H);

  // Telefon-Rahmen unten, zentriert. Skaliert bei Bedarf herunter, damit es NIE
  // die Subline ueberlappt (wichtig bei kurzen 2:1-Formaten wie Android 1080x2160).
  const bezel = Math.round(0.02 * W);
  const screenAspect = 2.165;                      // ~19.5:9
  const phoneY = subY + Math.round(0.05 * H);
  const maxBottom = H - Math.round(0.03 * H);
  const availH = maxBottom - phoneY;
  let phoneW = Math.round(0.70 * W);
  let screenW = phoneW - 2 * bezel;
  let screenH = Math.round(screenW * screenAspect);
  let phoneH = screenH + 2 * bezel;
  if (phoneH > availH) {                            // zu hoch -> proportional verkleinern
    phoneH = availH;
    screenH = phoneH - 2 * bezel;
    screenW = Math.round(screenH / screenAspect);
    phoneW = screenW + 2 * bezel;
  }
  const phoneX = Math.round((W - phoneW) / 2);
  const radius = Math.round(0.085 * phoneW);
  const screenX = phoneX + bezel;
  const screenY = phoneY + bezel;
  const screenR = Math.round(radius * 0.78);

  const b64 = readFileSync(rawPath).toString('base64');
  const mime = /\.jpe?g$/i.test(rawPath) ? 'image/jpeg' : 'image/png';

  const headlineTspans = feat.headline
    .map((line, i) => lineSpans(line, M, i === 0 ? 0 : hGap, hSize))
    .join('');

  return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.25" y2="1">
      <stop offset="0" stop-color="#15151f"/>
      <stop offset="0.5" stop-color="#0c0d13"/>
      <stop offset="1" stop-color="#08080d"/>
    </linearGradient>
    <radialGradient id="gr" cx="0.82" cy="0.10" r="0.55">
      <stop offset="0" stop-color="#8a2a14" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#8a2a14" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="gb" cx="0.12" cy="0.06" r="0.45">
      <stop offset="0" stop-color="#173763" stop-opacity="0.40"/>
      <stop offset="1" stop-color="#173763" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="sc"><rect x="${screenX}" y="${screenY}" width="${screenW}" height="${screenH}" rx="${screenR}"/></clipPath>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <rect width="${W}" height="${H}" fill="url(#gr)"/>
  <rect width="${W}" height="${H}" fill="url(#gb)"/>
  <g transform="rotate(-30 ${W * 0.2} ${H * 0.86})">
    <rect x="${-W * 0.1}" y="${H * 0.855}" width="${W * 0.9}" height="${Math.round(0.006 * H)}" fill="${RED}" opacity="0.85"/>
    <rect x="${W * 0.05}" y="${H * 0.885}" width="${W * 0.55}" height="${Math.round(0.004 * H)}" fill="#ff6a5a" opacity="0.55"/>
  </g>
  <text x="${M}" y="${logoY}" font-family="${FONT}" font-size="${logoSize}" font-weight="700"><tspan fill="${WHITE}">Cruise</tspan><tspan fill="${RED}">Connector</tspan></text>
  <text x="${M}" y="${hTop}" font-family="${FONT}" font-size="${hSize}" font-weight="800" letter-spacing="-1">${headlineTspans}</text>
  <text x="${M}" y="${subY}" font-family="${FONT}" font-size="${subSize}" font-weight="400" fill="${MUTED}">${esc(feat.sub)}</text>
  ${chromeButtons(chrome, phoneX, phoneY, phoneW, phoneH, W)}
  <rect x="${phoneX}" y="${phoneY}" width="${phoneW}" height="${phoneH}" rx="${radius}" fill="#15171f" stroke="#2b2f3b" stroke-width="${Math.round(0.0025 * W)}"/>
  <image x="${screenX}" y="${screenY}" width="${screenW}" height="${screenH}" preserveAspectRatio="xMidYMid slice" clip-path="url(#sc)" xlink:href="data:${mime};base64,${b64}"/>
  <rect x="${screenX}" y="${screenY}" width="${screenW}" height="${screenH}" rx="${screenR}" fill="none" stroke="#000000" stroke-opacity="0.5" stroke-width="2"/>
</svg>`;
}

// Play-Store-Vorstellungsgrafik / Feature Graphic (1024x500, Querformat).
// Wird im Store als Banner ueber den Screenshots gezeigt — Pflichtfeld, anderes
// Format als die 1080x2340-Phone-Shots.
function buildFeatureGraphic(W, H) {
  const M = Math.round(0.055 * W);
  const logoSize = Math.round(0.040 * W);
  const titleSize = Math.round(0.092 * W);
  const lineGap = Math.round(0.205 * H);
  const subSize = Math.round(0.031 * W);
  return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="#15151f"/><stop offset="0.55" stop-color="#0c0d13"/><stop offset="1" stop-color="#08080d"/>
    </linearGradient>
    <radialGradient id="gr" cx="0.88" cy="0.14" r="0.8">
      <stop offset="0" stop-color="#8a2a14" stop-opacity="0.6"/><stop offset="1" stop-color="#8a2a14" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <rect width="${W}" height="${H}" fill="url(#gr)"/>
  <path d="M ${W * 0.72} ${H * 1.04} C ${W * 0.82} ${H * 0.68}, ${W * 0.76} ${H * 0.46}, ${W * 0.90} ${H * 0.30} S ${W * 1.02} ${H * 0.10}, ${W * 1.08} ${-H * 0.05}" fill="none" stroke="${RED}" stroke-width="${Math.round(0.012 * W)}" stroke-linecap="round" opacity="0.85"/>
  <circle cx="${W * 0.90}" cy="${H * 0.30}" r="${Math.round(0.013 * W)}" fill="${WHITE}" stroke="${RED}" stroke-width="${Math.round(0.006 * W)}"/>
  <g transform="rotate(-27 ${W * 0.15} ${H * 0.88})">
    <rect x="${-W * 0.1}" y="${H * 0.84}" width="${W * 0.58}" height="${Math.round(0.011 * H)}" fill="${RED}" opacity="0.7"/>
  </g>
  <text x="${M}" y="${Math.round(0.17 * H)}" font-family="${FONT}" font-size="${logoSize}" font-weight="700"><tspan fill="${WHITE}">Cruise</tspan><tspan fill="${RED}">Connector</tspan></text>
  <text x="${M}" y="${Math.round(0.45 * H)}" font-family="${FONT}" font-size="${titleSize}" font-weight="800" letter-spacing="-1"><tspan fill="${WHITE}">Kurven, die</tspan><tspan x="${M}" dy="${lineGap}" fill="${RED}">Spaß machen.</tspan></text>
  <text x="${M}" y="${Math.round(0.90 * H)}" font-family="${FONT}" font-size="${subSize}" font-weight="400" fill="${MUTED}">Rundkurse · Live-Navigation · Community für Cruiser</text>
</svg>`;
}

let made = 0;
const missing = [];
for (const [platform, { w, h, chrome }] of Object.entries(PLATFORMS)) {
  rmSync(join(ROOT, 'out', platform), { recursive: true, force: true }); // Altstand wegräumen
  mkdirSync(join(ROOT, 'out', platform), { recursive: true });
  let idx = 0;
  for (const feat of FEATURES) {
    const raw = findRaw(platform, feat.id);
    if (!raw) { missing.push(`${platform}/${feat.id}`); continue; }
    idx += 1;
    const svg = buildSvg(w, h, feat, raw, chrome);
    const tmp = join(ROOT, 'out', platform, `.${feat.id}.svg`);
    writeFileSync(tmp, svg);
    const outName = `${String(idx).padStart(2, '0')}_${feat.id}.png`;
    const out = join(ROOT, 'out', platform, outName);
    execFileSync('rsvg-convert', ['-w', String(w), '-h', String(h), tmp, '-o', out]);
    rmSync(tmp, { force: true });
    console.log(`✓ ${platform}/${outName}`);
    made += 1;
  }
}

// Vorstellungsgrafik (1024x500) — plattformunabhaengig, einmal nach out/.
{
  const fg = buildFeatureGraphic(1024, 500);
  const tmp = join(ROOT, 'out', '.feature.svg');
  writeFileSync(tmp, fg);
  const out = join(ROOT, 'out', 'feature_graphic_1024x500.png');
  execFileSync('rsvg-convert', ['-w', '1024', '-h', '500', tmp, '-o', out]);
  rmSync(tmp, { force: true });
  console.log('✓ feature_graphic_1024x500.png');
  made += 1;
}

console.log(`\nFertig: ${made} Bild(er) gerendert.`);
if (missing.length) console.log(`Fehlende raw-Screenshots (uebersprungen): ${missing.length}`);
