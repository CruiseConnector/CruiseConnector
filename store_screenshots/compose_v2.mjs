// 2026-08-07 (vucko): „Mache sie neu im iOS-Design, ansprechender für Leute die
// die App herunterladen wollen, oben links mit echtem Logo. Man soll den Rahmen
// vom iPhone sehen, man soll sehen es ist ein iPhone. Und bei Android dass es
// ein Android ist."
//
// Eigene Datei neben compose.mjs — die alte Pipeline und ihre Ergebnisse
// bleiben unangetastet.
//
// ENTSCHEIDUNGEN, die man beim Lesen sonst nicht sieht:
//
// * GERÄT KOMPLETT SICHTBAR. Der erste Entwurf ließ das Telefon unten aus dem
//   Bild laufen — das wirkt größer, aber man erkennt kein Gerät mehr. Jetzt
//   steht das ganze Telefon im Bild: Metallrahmen, schwarzer Rand, Seiten-
//   tasten. Preis dafür: der Screen ist kleiner. Das ist der Punkt, den vucko
//   ausdrücklich wollte.
//
// * DIE INSEL LIEGT NICHT MEHR AUF DEM INHALT. Im ersten Entwurf verdeckte die
//   nachgebaute Dynamic Island die Kopfzeile der App („Route berechnet" war
//   weg). Jetzt bekommt der Bildschirm oben einen eigenen Streifen in der
//   App-Hintergrundfarbe, dort sitzt die Insel, und die Aufnahme beginnt
//   darunter. Nichts wird mehr überdeckt.
//
// * ERKENNUNGSMERKMALE STATT NUR EINES RECHTECKS. iPhone: sehr runde Ecken,
//   Dynamic Island, Action-Button und Lautstärkewippe links, Power rechts.
//   Android: flachere Ecken, Punch-Hole-Kamera, beide Tasten rechts. Genau
//   daran erkennt man die Plattform auf einen Blick.
//
// * Apple rendert in 1320x2868 (6,9 Zoll) — seit 2025 die von App Store
//   Connect GEFORDERTE Größe. Android in 1080x1920, exakt 9:16.
//
// * Kein Alphakanal in der Ausgabe: Apple lehnt Transparenz ab.
//
// Aufruf:  node store_screenshots/compose_v2.mjs

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const ROOT = dirname(fileURLToPath(import.meta.url));
const REPO = join(ROOT, '..');
const LOGO = join(REPO, 'assets/branding/cruiseconnect_logo_full.png');

const ZIEL = {
  apple: join(homedir(), 'Desktop/CruiseConnector_StoreBilder/neu_apple'),
  android: join(homedir(), 'Desktop/CruiseConnector_StoreBilder/neu_android'),
};

// Reihenfolge = Reihenfolge im Store. Das erste Bild entscheidet, ob jemand
// weiterwischt — deshalb steht die fertige Route vorn, nicht das Formular.
// *…* markiert den roten Teil der Überschrift.
const FEATURES = [
  { id: 'preview',    tag: 'ROUTENPLANUNG',       headline: ['Kurven, die', 'sich *lohnen.*'],              sub: 'Distanz, Dauer und Kurvenzahl auf einen Blick.' },
  { id: 'roundtrip',  tag: 'IN SEKUNDEN GEPLANT', headline: ['Sag wie weit.', 'Wir finden', 'die *Strecke.*'], sub: 'Distanz, Fahrstil, Autobahn an oder aus. Fertig.' },
  { id: 'navigation', tag: 'LIVE-NAVIGATION',     headline: ['Ansage vor', 'jeder *Kurve.*'],               sub: 'Klare Manöver, Restzeit und Route im Fahrmodus.' },
  { id: 'route_end',  tag: 'NACH DER FAHRT',      headline: ['Jede Fahrt', 'zählt *wirklich.*'],            sub: 'Echte Strecke, Tempo, Kurven und Bewertung.' },
  { id: 'stats',      tag: 'LEVEL & BADGES',      headline: ['Fahre. Steig auf.', '*Werde Legende.*'],      sub: 'XP, Streak und Badges für jede einzelne Fahrt.' },
  { id: 'group',      tag: 'GEMEINSAM FAHREN',    headline: ['Fahrt *zusammen.*', 'Bleibt synchron.'],      sub: 'Code teilen, Rollen verteilen, zusammen los.' },
  { id: 'share',      tag: 'TEILEN',              headline: ['Deine Fahrt', 'als *Story.*'],                sub: 'Strecke, Foto und Werte in einem Tap.' },
  { id: 'profile',    tag: 'DEIN PROFIL',         headline: ['Deine Garage.', 'Deine *Maschinen.*'],        sub: 'Fahrzeuge, Badges und alle Werte an einem Ort.' },
];

const PLATTFORM = {
  apple:   { w: 1320, h: 2868, geraet: 'iphone' },
  android: { w: 1080, h: 1920, geraet: 'android' },
};

const ROT = '#FF4D24';
const ROT_HELL = '#FF8B67';
const WEISS = '#FFFFFF';
const GRAU = '#9AA3B2';
const APP_BG = '#0B0E14';
const FONT = 'Helvetica Neue, Helvetica, Arial, sans-serif';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const r = (n) => Math.round(n);

// ── Textbreite MESSEN statt schaetzen ──────────────────────────────────────
// 2026-08-07 (vucko: „teilweise nicht schoen verarbeitet, schau dass alles
// schoen sitzt"): Die Unterzeile lief rechts aus dem Bild und die Pille sass
// zu eng. Grund: Die Breite war ueber die Zeichenzahl geschaetzt. Jetzt wird
// sie mit ImageMagick am echten Schriftschnitt gemessen. Arial ist metrisch
// nahezu deckungsgleich mit Helvetica (Neue) und liegt als eigene
// Fett-Datei vor, laesst sich also exakt messen.
const SCHRIFT = {
  normal: '/System/Library/Fonts/Supplemental/Arial.ttf',
  fett: '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
};
const SICHERHEIT = 1.035; // Puffer, weil rsvg Helvetica Neue nimmt
const _messCache = new Map();

function messe(text, groesse, fett = false) {
  if (!text) return 0;
  const key = `${fett ? 'B' : 'R'}|${text}`;
  let bei100 = _messCache.get(key);
  if (bei100 === undefined) {
    const out = execFileSync('magick', [
      '-background', 'none', '-fill', 'white',
      '-font', fett ? SCHRIFT.fett : SCHRIFT.normal,
      '-pointsize', '100', `label:${text}`,
      '-format', '%[fx:w]', 'info:',
    ]).toString().trim();
    bei100 = Number(out) || 0;
    _messCache.set(key, bei100);
  }
  return (bei100 / 100) * groesse * SICHERHEIT;
}

// Groesste Schriftgroesse <= start, bei der ALLE Zeilen in maxW passen.
function passendeGroesse(zeilen, maxW, start, fett) {
  let g = start;
  while (g > start * 0.62) {
    if (zeilen.every((z) => messe(z.replace(/\*/g, ''), g, fett) <= maxW)) return r(g);
    g -= 1;
  }
  return r(g);
}

// Unterzeile auf hoechstens zwei Zeilen umbrechen.
function umbrechen(text, maxW, groesse) {
  if (messe(text, groesse) <= maxW) return [text];
  const woerter = text.split(' ');
  for (let i = woerter.length - 1; i > 0; i--) {
    const a = woerter.slice(0, i).join(' ');
    const b = woerter.slice(i).join(' ');
    if (messe(a, groesse) <= maxW && messe(b, groesse) <= maxW) return [a, b];
  }
  return [text];
}

function b64(pfad) {
  const mime = /\.jpe?g$/i.test(pfad) ? 'image/jpeg' : 'image/png';
  return { mime, data: readFileSync(pfad).toString('base64') };
}

function rohBild(plattform, id) {
  for (const ext of ['png', 'jpg', 'jpeg', 'PNG', 'JPG']) {
    const p = join(ROOT, 'raw_norm', plattform, `${id}.${ext}`);
    if (existsSync(p)) return p;
  }
  for (const ext of ['png', 'jpg']) {
    const p = join(ROOT, 'raw_norm', 'apple', `${id}.${ext}`);
    if (existsSync(p)) return p;
  }
  return null;
}

function zeile(text, x, dy) {
  let inner = '';
  text.split('*').forEach((p, i) => {
    if (!p) return;
    inner += `<tspan fill="${i % 2 === 1 ? ROT : WEISS}">${esc(p)}</tspan>`;
  });
  return `<tspan x="${x}" dy="${dy}">${inner}</tspan>`;
}

// ── Das Gerät ──────────────────────────────────────────────────────────────
// Liefert die SVG-Gruppe für ein vollständig sichtbares Telefon inklusive
// Metallrahmen, Bildschirm mit Kamerastreifen und Seitentasten.
function geraet({ art, x, y, w, h, screen, id }) {
  const istApple = art === 'iphone';
  // Masse nach dem iPhone 17 Pro: sehr runde, durchgehende Ecken und
  // deutlich schmalere Raender als bei den Vorgaengern.
  const eckenR   = r(w * (istApple ? 0.152 : 0.098));
  const metall   = r(w * (istApple ? 0.0185 : 0.021));   // Rahmenbreite
  const rand     = r(w * (istApple ? 0.0115 : 0.019));   // schwarzer Rand innen
  const scX = x + metall + rand, scY = y + metall + rand;
  const scW = w - (metall + rand) * 2, scH = h - (metall + rand) * 2;
  const scR = r(eckenR - metall - rand * 0.6);

  // 2026-08-07 (vucko: „schau dass nichts abgeschnitten wird, vollscreen auf
  // dem Rahmen"): Die Aufnahme wird WEDER beschnitten NOCH mit Balken
  // aufgefuellt. Der Bildschirm hat exakt das Verhaeltnis der Aufnahme
  // (alle Rohbilder sind dafuer auf 0,4805 vereinheitlicht), der
  // Kamerastreifen kommt oben zusaetzlich dazu.
  const inselH = r(w * (istApple ? 0.076 : 0.060));
  const streifen = r(inselH * (istApple ? 1.85 : 2.05));
  const bildY = scY + streifen;
  const bildH = scH - streifen;

  const kamera = istApple
    ? `<rect x="${r(x + (w - w * 0.315) / 2)}" y="${r(scY + (streifen - inselH) / 2)}" width="${r(w * 0.315)}" height="${inselH}" rx="${r(inselH / 2)}" fill="#000000"/>
       <circle cx="${r(x + w / 2 + w * 0.105)}" cy="${r(scY + streifen / 2)}" r="${r(inselH * 0.20)}" fill="#0d1420"/>`
    : `<circle cx="${r(x + w / 2)}" cy="${r(scY + streifen / 2)}" r="${r(inselH * 0.42)}" fill="#000000"/>
       <circle cx="${r(x + w / 2)}" cy="${r(scY + streifen / 2)}" r="${r(inselH * 0.26)}" fill="#0d1420"/>`;

  // Seitentasten. iPhone: Action + Wippe links, Power rechts.
  // Android: alles rechts, Power kuerzer unter der Wippe.
  const tB = r(w * 0.011);              // wie weit sie herausstehen
  const tR = r(tB * 0.8);
  const taste = (tx, ty, tw, th) =>
    `<rect x="${tx}" y="${ty}" width="${tw}" height="${th}" rx="${tR}" fill="url(#metall)"/>`;
  let tasten = '';
  if (istApple) {
    // iPhone 17 Pro: LINKS Action-Button und Lautstaerkewippe, RECHTS die
    // Seitentaste und darunter Camera Control. Letzterer ist das
    // Erkennungszeichen der 16/17-Pro-Reihe — ohne ihn sieht der Rahmen aus
    // wie jedes beliebige Telefon.
    const ccY = r(y + h * 0.392), ccH = r(h * 0.058);
    tasten =
      taste(x - tB, r(y + h * 0.148), tB + 2, r(h * 0.040)) +   // Action
      taste(x - tB, r(y + h * 0.212), tB + 2, r(h * 0.072)) +   // Lauter
      taste(x - tB, r(y + h * 0.296), tB + 2, r(h * 0.072)) +   // Leiser
      taste(x + w - 2, r(y + h * 0.228), tB + 2, r(h * 0.105)) + // Seitentaste
      // Camera Control sitzt buendig im Rahmen und hat eine Saphirflaeche,
      // deshalb heller und mit eigener Kante statt als reine Ausbuchtung.
      `<rect x="${x + w - r(tB * 0.35)}" y="${ccY}" width="${r(tB * 1.35)}" height="${ccH}" rx="${r(tB * 0.45)}" fill="#aeb6c6"/>` +
      `<rect x="${x + w - r(tB * 0.15)}" y="${r(ccY + ccH * 0.12)}" width="${r(tB * 0.8)}" height="${r(ccH * 0.76)}" rx="${r(tB * 0.3)}" fill="#e6ebf5" fill-opacity="0.85"/>`;
  } else {
    tasten =
      taste(x + w - 2, r(y + h * 0.170), tB + 2, r(h * 0.082)) + // Wippe
      taste(x + w - 2, r(y + h * 0.272), tB + 2, r(h * 0.052));  // Power
  }

  return `
  ${tasten}
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${eckenR}" fill="url(#metall)"/>
  <rect x="${x + 1}" y="${y + 1}" width="${w - 2}" height="${h - 2}" rx="${eckenR - 1}" fill="none" stroke="#c3cad8" stroke-opacity="0.45" stroke-width="2"/>
  <rect x="${x + metall}" y="${y + metall}" width="${w - metall * 2}" height="${h - metall * 2}" rx="${r(eckenR - metall)}" fill="#000000"/>
  <rect x="${scX}" y="${scY}" width="${scW}" height="${scH}" rx="${scR}" fill="${APP_BG}"/>
  <image x="${scX}" y="${bildY}" width="${scW}" height="${bildH}" preserveAspectRatio="none" clip-path="url(#clip_${id})" xlink:href="data:${screen.mime};base64,${screen.data}"/>
  ${kamera}
  <rect x="${scX}" y="${scY}" width="${scW}" height="${scH}" rx="${scR}" fill="none" stroke="#ffffff" stroke-opacity="0.07" stroke-width="2"/>`;
}

function baueSvg(plattform, feature, idx) {
  const P = PLATTFORM[plattform];
  const W = P.w, H = P.h;
  const roh = rohBild(plattform, feature.id);
  if (!roh) return null;
  const screen = b64(roh);
  const logo = b64(LOGO);
  const istApple = plattform === 'apple';

  const M = r(W * 0.068);
  const logoW = r(W * (istApple ? 0.215 : 0.200));
  const logoH = r(logoW * (460 / 720));
  const logoY = r(H * (istApple ? 0.028 : 0.030));

  const maxW = W - M * 2;

  // Pille: Breite aus der GEMESSENEN Textbreite plus Innenabstand.
  const pFs = r(W * 0.0225);
  const pSperr = pFs * 0.15;                       // letter-spacing
  const pTextW = messe(feature.tag, pFs, true) + pSperr * (feature.tag.length - 1);
  const pPad = r(pFs * 1.25);
  const pH = r(pFs * 2.45);
  const pY = logoY + logoH + r(H * 0.021);
  const pW = r(pTextW + pPad * 2);

  // Ueberschrift: so gross wie moeglich, aber garantiert im Bild.
  const hFsFinal = passendeGroesse(
    feature.headline, maxW, istApple ? W * 0.0745 : W * 0.0700, true,
  );
  const hLh = r(hFsFinal * 1.09);
  const hY = pY + pH + r(hFsFinal * 1.02);

  // Unterzeile: erst umbrechen, bei Bedarf zusaetzlich verkleinern.
  let sFs = r(W * 0.0278);
  let sZeilen = umbrechen(feature.sub, maxW, sFs);
  while (sZeilen.some((z) => messe(z, sFs) > maxW) && sFs > W * 0.019) {
    sFs -= 1;
    sZeilen = umbrechen(feature.sub, maxW, sFs);
  }
  const sLh = r(sFs * 1.32);
  const sY = hY + (feature.headline.length - 1) * hLh + r(hFsFinal * 0.88);

  // Gerät: feste Position, damit alle acht Bilder in der Reihe fluchten.
  // 2026-08-07: Geraet hoeher und groesser. Im ersten Anlauf klaffte zwischen
  // Unterzeile und Telefon eine tote Flaeche von rund 350 Pixeln.
  // Geraetebreite ergibt sich aus dem Bildverhaeltnis, damit der Screen exakt
  // passt. VERH = Breite/Hoehe der vereinheitlichten Aufnahmen.
  const VERH = 0.4805;
  const devY = r(H * (istApple ? 0.318 : 0.322));
  const devH = r(H * (istApple ? 0.640 : 0.634));
  const mAnteil = istApple ? 0.0185 + 0.0115 : 0.021 + 0.019; // Rahmen + Rand
  const inselAnteil = (istApple ? 0.076 * 1.85 : 0.060 * 2.05);
  // devH = 2*m*devW + streifen(devW) + screenH ; screenH = (devW - 2*m*devW)/VERH
  // -> devH = devW * (2m + inselAnteil + (1 - 2m)/VERH)
  const faktor = 2 * mAnteil + inselAnteil + (1 - 2 * mAnteil) / VERH;
  const devW = r(devH / faktor);
  const devX = r((W - devW) / 2);

  const bodenY = devY + devH;

  return `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#171a24"/>
      <stop offset="0.45" stop-color="#0c0e15"/>
      <stop offset="1" stop-color="#050609"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="${ROT}" stop-opacity="0.50"/>
      <stop offset="0.5" stop-color="${ROT}" stop-opacity="0.15"/>
      <stop offset="1" stop-color="${ROT}" stop-opacity="0"/>
    </radialGradient>
    <!-- iPhone 17 Pro hat ein Aluminium-Unibody-Gehaeuse: heller und kuehler
         als das Titan der Vorgaenger, mit einer scharfen Lichtkante aussen. -->
    <linearGradient id="metall" x1="0" y1="0" x2="1" y2="0.2">
      <stop offset="0" stop-color="#d5dbe6"/>
      <stop offset="0.06" stop-color="#8e96a6"/>
      <stop offset="0.2" stop-color="#454c5c"/>
      <stop offset="0.5" stop-color="#2a2f3a"/>
      <stop offset="0.8" stop-color="#454c5c"/>
      <stop offset="0.94" stop-color="#8e96a6"/>
      <stop offset="1" stop-color="#d5dbe6"/>
    </linearGradient>
    <linearGradient id="streak" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="${ROT}" stop-opacity="0"/>
      <stop offset="0.3" stop-color="${ROT}" stop-opacity="1"/>
      <stop offset="1" stop-color="${ROT_HELL}" stop-opacity="0"/>
    </linearGradient>
    <radialGradient id="boden" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#000000" stop-opacity="0.75"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>
    <filter id="schatten" x="-70%" y="-30%" width="240%" height="190%">
      <feDropShadow dx="0" dy="${r(H * 0.010)}" stdDeviation="${r(W * 0.030)}" flood-color="#000000" flood-opacity="0.85"/>
    </filter>
    <clipPath id="clip_${idx}">
      <rect x="${devX + r(devW * 0.041)}" y="${devY + r(devW * 0.041)}" width="${devW - r(devW * 0.082)}" height="${devH - r(devW * 0.082)}" rx="${r(devW * 0.10)}"/>
    </clipPath>
  </defs>

  <rect width="${W}" height="${H}" fill="url(#bg)"/>
  <ellipse cx="${r(W * 0.5)}" cy="${r(devY + devH * 0.30)}" rx="${r(W * 0.88)}" ry="${r(H * 0.30)}" fill="url(#glow)"/>

  <!-- Geschwindigkeitsstreifen: verbinden die acht Bilder zu einer Serie -->
  <rect x="${r(-W * 0.05)}" y="${r(devY - H * 0.030)}" width="${r(W * 0.58)}" height="${Math.max(3, r(H * 0.0016))}" fill="url(#streak)" opacity="0.55"/>
  <rect x="${r(W * 0.46)}" y="${r(devY - H * 0.016)}" width="${r(W * 0.36)}" height="${Math.max(2, r(H * 0.0010))}" fill="url(#streak)" opacity="0.25"/>

  <image x="${M}" y="${logoY}" width="${logoW}" height="${logoH}" preserveAspectRatio="xMinYMid meet" xlink:href="data:${logo.mime};base64,${logo.data}"/>

  <rect x="${M}" y="${pY}" width="${pW}" height="${pH}" rx="${r(pH / 2)}" fill="${ROT}" fill-opacity="0.14" stroke="${ROT}" stroke-opacity="0.55" stroke-width="2"/>
  <text x="${M + pPad}" y="${pY + r(pH * 0.685)}" font-family="${FONT}" font-size="${pFs}" font-weight="700" letter-spacing="${pSperr.toFixed(1)}" fill="${ROT_HELL}">${esc(feature.tag)}</text>

  <text xml:space="preserve" x="${M}" y="${hY}" font-family="${FONT}" font-size="${hFsFinal}" font-weight="800" letter-spacing="${(-hFsFinal * 0.024).toFixed(1)}">
    ${feature.headline.map((l, i) => zeile(l, M, i === 0 ? 0 : hLh)).join('\n    ')}
  </text>

  <text xml:space="preserve" x="${M}" y="${sY}" font-family="${FONT}" font-size="${sFs}" font-weight="500" fill="${GRAU}">
    ${sZeilen.map((z, i) => `<tspan x="${M}" dy="${i === 0 ? 0 : sLh}">${esc(z)}</tspan>`).join('\n    ')}
  </text>

  <!-- Standschatten unter dem Geraet -->
  <ellipse cx="${r(W / 2)}" cy="${r(bodenY + H * 0.012)}" rx="${r(devW * 0.62)}" ry="${r(H * 0.016)}" fill="url(#boden)"/>

  <g filter="url(#schatten)">
    ${geraet({ art: P.geraet, x: devX, y: devY, w: devW, h: devH, screen, id: idx })}
  </g>
</svg>`;
}

// ── Rendern ────────────────────────────────────────────────────────────────
let gebaut = 0;
for (const [plattform, P] of Object.entries(PLATTFORM)) {
  const out = ZIEL[plattform];
  mkdirSync(out, { recursive: true });
  FEATURES.forEach((f, i) => {
    const svg = baueSvg(plattform, f, i);
    if (!svg) { console.log(`  uebersprungen (kein Rohbild): ${plattform}/${f.id}`); return; }
    const nr = String(i + 1).padStart(2, '0');
    const tmp = join(ROOT, `.tmp_${plattform}_${f.id}.svg`);
    const png = join(out, `${nr}_${f.id}.png`);
    writeFileSync(tmp, svg);
    execFileSync('rsvg-convert', ['-w', String(P.w), '-h', String(P.h), '-o', png, tmp]);
    execFileSync('magick', [png, '-background', '#050609', '-alpha', 'remove', '-alpha', 'off', png]);
    execFileSync('rm', ['-f', tmp]);
    gebaut++;
    console.log(`  ${plattform}/${nr}_${f.id}.png  ${P.w}x${P.h}`);
  });
}
console.log(`\nFertig: ${gebaut} Bilder.`);
console.log(`  Apple:   ${ZIEL.apple}`);
console.log(`  Android: ${ZIEL.android}`);
