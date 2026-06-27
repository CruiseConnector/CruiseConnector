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
  { id: 'route_end',  headline: ['Speichere', 'deine besten', '*Strecken.*'], sub: 'Nach der Fahrt: echte Strecke, Stats und Bewertung.' },
  { id: 'dashboard',  headline: ['Fahre. Steige auf.', '*Werde Legende.*'],   sub: 'XP, Level, Badges und Wochenstatistik fuer jede Fahrt.' },
  { id: 'roundtrip',  headline: ['Finde *Rundkurse*', 'die wirklich', 'Spass machen.'], sub: 'Plane Distanz, Stil und Autobahn-Regeln in Sekunden.' },
  { id: 'navigation', headline: ['*Live*-Navigation', 'fuer jede Kurve.'],    sub: 'Klare Manoever, Restzeit und Route direkt im Fahrmodus.' },
  { id: 'community',  headline: ['Vernetze dich', 'mit anderen', '*Fahrern.*'], sub: 'Finde Fahrer, Gruppen und Ausfahrten in deiner Naehe.' },
  { id: 'group',      headline: ['Fahre *zusammen.*', 'Bleibt synchron.'],    sub: 'Gruppenpositionen und Route bleiben live im Blick.' },
  { id: 'garage',     headline: ['Deine *Garage.*', 'Deine Maschinen.'],      sub: 'Verwalte deine Fahrzeuge und zeig, was du faehrst.' },
  { id: 'stats',      headline: ['Behalte den', '*Ueberblick.*'],            sub: 'Statistiken, Streak und Verlauf all deiner Touren.' },
  { id: 'share',      headline: ['*Teile* deine', 'Fahrten.'],               sub: 'Strecke, Foto und Stats als Story in einem Tap.' },
  { id: 'offline',    headline: ['Ganz DACH.', '*Offline.*'],                sub: 'Die Karte laedt ohne Netz, ueberall scharf.' },
];

const PLATFORMS = {
  apple:   { w: 1242, h: 2688 },
  android: { w: 1080, h: 2340 },
};

const RED = '#FF3B30';
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

function buildSvg(W, H, feat, rawPath) {
  const M = Math.round(0.066 * W);                 // linker Rand
  const logoSize = Math.round(0.035 * W);
  const logoY = Math.round(0.052 * H);
  const hSize = Math.round(0.082 * W);             // Headline-Groesse
  const hTop = Math.round(0.118 * H);              // Headline 1. Baseline
  const hGap = Math.round(0.0455 * H);             // Zeilenabstand
  const nLines = feat.headline.length;
  const subSize = Math.round(0.0305 * W);
  const subY = hTop + (nLines - 1) * hGap + Math.round(0.052 * H);

  // Telefon-Rahmen unten, zentriert.
  const phoneW = Math.round(0.70 * W);
  const phoneX = Math.round((W - phoneW) / 2);
  const bezel = Math.round(0.02 * W);
  const radius = Math.round(0.085 * phoneW);
  const screenW = phoneW - 2 * bezel;
  const screenAspect = 2.165;                      // ~19.5:9
  const screenH = Math.round(screenW * screenAspect);
  const phoneH = screenH + 2 * bezel;
  let phoneY = subY + Math.round(0.05 * H);
  const maxBottom = H - Math.round(0.03 * H);
  if (phoneY + phoneH > maxBottom) phoneY = maxBottom - phoneH;
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
      <stop offset="0" stop-color="#7d1322" stop-opacity="0.55"/>
      <stop offset="1" stop-color="#7d1322" stop-opacity="0"/>
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
  <rect x="${phoneX}" y="${phoneY}" width="${phoneW}" height="${phoneH}" rx="${radius}" fill="#15171f" stroke="#2b2f3b" stroke-width="${Math.round(0.0025 * W)}"/>
  <image x="${screenX}" y="${screenY}" width="${screenW}" height="${screenH}" preserveAspectRatio="xMidYMid slice" clip-path="url(#sc)" xlink:href="data:${mime};base64,${b64}"/>
  <rect x="${screenX}" y="${screenY}" width="${screenW}" height="${screenH}" rx="${screenR}" fill="none" stroke="#000000" stroke-opacity="0.5" stroke-width="2"/>
</svg>`;
}

let made = 0;
const missing = [];
for (const [platform, { w, h }] of Object.entries(PLATFORMS)) {
  mkdirSync(join(ROOT, 'out', platform), { recursive: true });
  let idx = 0;
  for (const feat of FEATURES) {
    const raw = findRaw(platform, feat.id);
    if (!raw) { missing.push(`${platform}/${feat.id}`); continue; }
    idx += 1;
    const svg = buildSvg(w, h, feat, raw);
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
console.log(`\nFertig: ${made} Bild(er) gerendert.`);
if (missing.length) console.log(`Fehlende raw-Screenshots (uebersprungen): ${missing.length}`);
