// 2026-08-18 (Aufgabe 1.4 + 1.3): Reine Rechenprobe fuer die Selbst-
// Ueberlappungsformel und fuer die Umweg-Basisdistanz.
//
// Der Code wird NICHT abgeschrieben, sondern zur Laufzeit aus
// supabase/functions/generate-cruise-route-v2/index.ts ausgeschnitten und als
// Modul geladen. Damit kann die Probe nicht von der echten Fassung abdriften.
//
// Start:  deno run --allow-read test/route/edge_ueberlappung_rechenprobe.ts
// (wird auch von test/route/edge_selbstueberlappung_test.dart aufgerufen)

const QUELLE = new URL(
  '../../supabase/functions/generate-cruise-route-v2/index.ts',
  import.meta.url,
);

const datei = await Deno.readTextFile(QUELLE);
const von = datei.indexOf('function distanceMeters(');
const bis = datei.indexOf('// ─────────────────── Style-Quality Metriken');
if (von < 0 || bis < 0 || bis <= von) {
  console.error('FEHLER: Ausschnitt nicht gefunden — wurde index.ts umgebaut?');
  Deno.exit(2);
}
const ausschnitt = datei.slice(von, bis) +
  '\nexport { distanceMeters, selbstUeberlappungAnteil, ueberlappRaster };\n';
const modul = await import(
  'data:application/typescript;base64,' + btoa(unescape(encodeURIComponent(ausschnitt)))
);
const anteil = modul.selbstUeberlappungAnteil as (c: [number, number][]) => number;
const umwegBasisKm = modul.umwegBasisKm as (o: {
  directKm: number; detourLevel: number; detourFactor: number;
  requestedTargetKm: number; profileMultiplier: number;
}) => { km: number; term: string };

// ── Geometrie-Helfer: Meter -> [lng, lat] um einen Bezugspunkt ───────────
const LAT0 = 47.4, LNG0 = 9.7;
const M_PRO_LAT = 110540;
const M_PRO_LNG = 111320 * Math.cos((LAT0 * Math.PI) / 180);
const pkt = (xM: number, yM: number): [number, number] =>
  [LNG0 + xM / M_PRO_LNG, LAT0 + yM / M_PRO_LAT];

/// Legt Punkte im Abstand `schrittM` entlang der Strecke A->B.
function strecke(
  x1: number, y1: number, x2: number, y2: number, schrittM = 100,
): [number, number][] {
  const laenge = Math.hypot(x2 - x1, y2 - y1);
  const n = Math.max(1, Math.round(laenge / schrittM));
  const out: [number, number][] = [];
  for (let i = 1; i <= n; i++) out.push(pkt(x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n));
  return out;
}

function laengeKm(c: [number, number][]): number {
  let m = 0;
  for (let i = 1; i < c.length; i++) {
    m += (modul.distanceMeters as (a: number, b: number, cc: number, d: number) => number)(
      c[i - 1][1], c[i - 1][0], c[i][1], c[i][0],
    );
  }
  return m / 1000;
}

const zeilen: string[] = [];
function pruefe(name: string, c: [number, number][], min: number, max: number) {
  const t0 = performance.now();
  const wert = anteil(c);
  const ms = performance.now() - t0;
  const ok = wert >= min && wert <= max;
  zeilen.push(
    `${ok ? 'OK  ' : 'ROT '} ${name.padEnd(46)} Anteil=${wert.toFixed(3)} ` +
    `(erwartet ${min}..${max})  ${c.length} Punkte, ${laengeKm(c).toFixed(0)} km, ${ms.toFixed(1)} ms`,
  );
  return ok;
}

let allesOk = true;

// (a) Gerade Strecke ohne Ueberlappung -> nahe 0
{
  const c: [number, number][] = [pkt(0, 0), ...strecke(0, 0, 120000, 0)];
  allesOk = pruefe('(a) gerade Strecke 120 km', c, 0, 0.001) && allesOk;
}

// (b) Hin- und Rueckweg ueber dieselbe Linie -> nahe 1
{
  const hin: [number, number][] = [pkt(0, 0), ...strecke(0, 0, 60000, 0)];
  const zurueck = [...hin].reverse().slice(1);
  allesOk = pruefe('(b) 60 km hin, dieselbe Linie zurueck', [...hin, ...zurueck], 0.9, 1.0) && allesOk;
}

// (b2) Kurze Hin-und-Rueckfahrt: zeigt die bekannte Luecke am Wendepunkt.
{
  const hin: [number, number][] = [pkt(0, 0), ...strecke(0, 0, 10000, 0)];
  const zurueck = [...hin].reverse().slice(1);
  allesOk = pruefe('(b2) nur 10 km hin und zurueck (Luecke)', [...hin, ...zurueck], 0.6, 0.8) && allesOk;
}

// (c) Rundkurs, der sich nur einmal kreuzt -> klein
// Gerono-Lemniskate: x = R*sin(2t), y = R*sin(t) — kreuzt sich genau einmal.
{
  const R = 25000;
  const c: [number, number][] = [];
  for (let i = 0; i <= 4000; i++) {
    const t = (i / 4000) * 2 * Math.PI;
    c.push(pkt(R * Math.sin(2 * t), R * Math.sin(t)));
  }
  allesOk = pruefe('(c) Rundkurs mit genau einer Kreuzung', c, 0, 0.05) && allesOk;
}

// (c2) Sauberer Rundkurs (Kreis) -> 0
{
  const R = 20000;
  const c: [number, number][] = [];
  for (let i = 0; i <= 2000; i++) {
    const t = (i / 2000) * 2 * Math.PI;
    c.push(pkt(R * Math.cos(t), R * Math.sin(t)));
  }
  allesOk = pruefe('(c2) sauberer Kreis-Rundkurs 126 km', c, 0, 0.001) && allesOk;
}

// (d) Teilweise doppelt: 40 km raus, 40 km zurueck, dann 80 km weiter.
{
  const c: [number, number][] = [
    pkt(0, 0),
    ...strecke(0, 0, 40000, 0),
    ...strecke(40000, 0, 0, 0),
    ...strecke(0, 0, 0, 80000),
  ];
  allesOk = pruefe('(d) 80 von 160 km doppelt', c, 0.40, 0.55) && allesOk;
}

// (e) Parallelfahrbahn 25 m daneben zurueck -> zaehlt (Vuckos Fall)
{
  const hin: [number, number][] = [pkt(0, 0), ...strecke(0, 0, 60000, 0)];
  const zurueck = strecke(60000, 25, 0, 25);
  allesOk = pruefe('(e) zurueck auf der Parallelfahrbahn (25 m)', [...hin, ...zurueck], 0.9, 1.0) && allesOk;
}

// (f) Parallele Strasse 300 m daneben -> zaehlt NICHT
{
  const hin: [number, number][] = [pkt(0, 0), ...strecke(0, 0, 60000, 0)];
  const zurueck = strecke(60000, 300, 0, 300);
  allesOk = pruefe('(f) andere Strasse 300 m daneben', [...hin, ...zurueck], 0, 0.001) && allesOk;
}

// (g) Doppelte Stuetzpunkte und eine 5-km-Kante ohne Zwischenpunkte.
// GraphHopper liefert beides: identische Punkte hintereinander und lange
// Autobahnkanten zwischen Anschlussstellen. Ergebnis darf weder NaN noch von
// der Stuetzpunkt-Dichte abhaengig sein.
{
  const hin: [number, number][] = [pkt(0, 0), pkt(0, 0), ...strecke(0, 0, 30000, 0)];
  hin.push(pkt(35000, 0)); // 5 km ohne Zwischenpunkt
  const zurueck: [number, number][] = [pkt(30000, 0), ...strecke(30000, 0, 0, 0)];
  const c = [...hin, ...zurueck];
  const wert = anteil(c);
  const ok = Number.isFinite(wert) && wert >= 0.8 && wert <= 1.0;
  zeilen.push(
    `${ok ? 'OK  ' : 'ROT '} ${'(g) doppelte Punkte + 5-km-Kante ohne Stuetzpunkte'.padEnd(46)} ` +
    `Anteil=${wert.toFixed(3)} (erwartet 0.8..1, nicht NaN)`,
  );
  if (!ok) allesOk = false;
}

// ── LAUFZEIT: Gitter gegen naive O(n^2)-Schleife, gleicher Datensatz ────
const raster = modul.ueberlappRaster as (
  c: [number, number][], schrittM: number,
) => { xs: Float64Array; ys: Float64Array; n: number };

/// Dieselbe Kennzahl, aber OHNE Gitter: jeder Rasterpunkt gegen jedes Segment.
/// Dient zwei Zwecken: Laufzeitvergleich und Gegenprobe auf das Ergebnis.
function naivO2(coords: [number, number][]): number {
  const { xs, ys, n } = raster(coords, 100);
  if (n <= 61) return 0;
  const rx = new Float64Array(n), ry = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const a2 = i > 0 ? i - 1 : 0, b2 = i < n - 1 ? i + 1 : n - 1;
    let dx = xs[b2] - xs[a2], dy = ys[b2] - ys[a2];
    const l = Math.sqrt(dx * dx + dy * dy);
    if (l > 0) { dx /= l; dy /= l; }
    rx[i] = dx; ry[i] = dy;
  }
  let treffer = 0;
  for (let i = 0; i < n; i++) {
    let gefunden = false;
    for (let j = 0; j + 1 < n && !gefunden; j++) {
      if (Math.abs(j - i) < 60 || Math.abs(j + 1 - i) < 60) continue;
      const sx = xs[j], sy = ys[j];
      let ex = xs[j + 1] - sx, ey = ys[j + 1] - sy;
      const lq = ex * ex + ey * ey;
      let t = lq > 0 ? ((xs[i] - sx) * ex + (ys[i] - sy) * ey) / lq : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      const ddx = xs[i] - (sx + ex * t), ddy = ys[i] - (sy + ey * t);
      if (ddx * ddx + ddy * ddy >= 1600) continue;
      const l = Math.sqrt(lq);
      if (l === 0) continue;
      ex /= l; ey /= l;
      if (rx[i] * ex + ry[i] * ey <= -0.5) gefunden = true;
    }
    if (gefunden) treffer++;
  }
  return Number((treffer / n).toFixed(3));
}

const serpentine: [number, number][] = [];
for (let i = 0; i <= 20000; i++) {
  const t = (i / 20000) * 2 * Math.PI;
  serpentine.push(pkt(40000 * Math.cos(t) + 900 * Math.sin(60 * t), 40000 * Math.sin(t)));
}
const laufzeitFaelle: Array<[string, [number, number][]]> = [
  ['200 km hin und zurueck (25-m-Stuetzpunkte)', [
    pkt(0, 0), ...strecke(0, 0, 100000, 0, 25), ...strecke(100000, 0, 0, 0, 25),
  ]],
  ['Serpentinen-Rundkurs mit 20.001 Punkten', serpentine],
];
for (const [name, c] of laufzeitFaelle) {
  anteil(c); // aufwaermen
  const t0 = performance.now();
  let wert = 0;
  for (let i = 0; i < 14; i++) wert = anteil(c);
  const ms = performance.now() - t0;
  const t1 = performance.now();
  const naiv = naivO2(c);
  const naivMs = performance.now() - t1;
  const gleich = Math.abs(wert - naiv) < 0.002;
  zeilen.push(
    `${gleich ? 'OK  ' : 'ROT '} ${name}: ${laengeKm(c).toFixed(0)} km, ` +
    `Gitter ${(ms / 14).toFixed(2)} ms je Kandidat (14 Stueck ${ms.toFixed(1)} ms) | ` +
    `naiv O(n^2) ${naivMs.toFixed(0)} ms einmal → 14 waeren ${(naivMs * 14 / 1000).toFixed(1)} s | ` +
    `Anteil ${wert.toFixed(3)} vs naiv ${naiv.toFixed(3)}`,
  );
  if (!gleich) allesOk = false;
}

// ── Umweg-Basisdistanz (Aufgabe 1.3, Punkt 3) ───────────────────────────
zeilen.push('');
zeilen.push('── Umweg-Basisdistanz: welcher Term gewinnt? ──');

/// Die ALTE Formel, wortgleich aus dem Stand vor der Aenderung.
function altBaseKm(
  directKm: number, detourLevel: number, detourFactor: number,
  requestedTargetKm: number, mult: number,
): number {
  const baseFactor = detourLevel === 1 ? 0.15 : detourLevel === 2 ? 0.30 : 0.50;
  const factorKm = directKm * Math.max(0.08, (detourFactor - 1) * 0.55);
  const targetExtraKm = Math.max(0, requestedTargetKm - directKm) * 0.48;
  return Math.max(2, directKm * baseFactor * mult, factorKm * mult, targetExtraKm);
}

// Was der Client wirklich schickt (route_service.dart:1879 ff.)
const clientFaktor: Record<number, number> = { 1: 2.0, 2: 3.0, 3: 4.0 };
const clientMindestExtra: Record<number, number> = { 1: 8.0, 2: 20.0, 3: 35.0 };
const multVarianten = [0.7, 1.0, 1.15, 1.4]; // Abendrunde .. Kurvenjagd

let untergrenzeGewann = 0, gesamt = 0, abweichung = 0;
const termZaehler: Record<string, number> = {};
for (const level of [1, 2, 3]) {
  for (const mult of multVarianten) {
    for (let d = 5; d <= 80; d += 1) {
      const ziel = Math.max(d * clientFaktor[level], d + clientMindestExtra[level]);
      const neu = umwegBasisKm({
        directKm: d, detourLevel: level, detourFactor: clientFaktor[level],
        requestedTargetKm: ziel, profileMultiplier: mult,
      });
      const alt = altBaseKm(d, level, clientFaktor[level], ziel, mult);
      gesamt++;
      termZaehler[neu.term] = (termZaehler[neu.term] ?? 0) + 1;
      if (neu.term === 'untergrenze') untergrenzeGewann++;
      if (Math.abs(neu.km - alt) > 1e-9) abweichung++;
    }
  }
}
zeilen.push(
  `${abweichung === 0 ? 'OK  ' : 'ROT '} Ergebnis identisch zur alten Formel in ` +
  `${gesamt - abweichung}/${gesamt} Faellen (5..80 km, Stufe 1-3, 4 Profile)`,
);
zeilen.push(
  `${untergrenzeGewann === 0 ? 'OK  ' : 'ROT '} Untergrenze gewinnt mit echten ` +
  `Client-Faktoren 2/3/4 in ${untergrenzeGewann}/${gesamt} Faellen ` +
  `(Terme: ${Object.entries(termZaehler).map(([k, v]) => `${k}=${v}`).join(', ')})`,
);
if (abweichung !== 0 || untergrenzeGewann !== 0) allesOk = false;

// Und ohne detour_factor / ohne Zieldistanz (alte App-Versionen):
let untergrenzeOhneVorgabe = 0, gesamtOhne = 0;
for (const level of [1, 2, 3]) {
  for (let d = 5; d <= 80; d += 1) {
    const r = umwegBasisKm({
      directKm: d, detourLevel: level, detourFactor: 1,
      requestedTargetKm: d, profileMultiplier: 1.0,
    });
    gesamtOhne++;
    if (r.term === 'untergrenze') untergrenzeOhneVorgabe++;
    const erwartet = d * (level === 1 ? 0.15 : level === 2 ? 0.30 : 0.50);
    if (erwartet > 2 && Math.abs(r.km - erwartet) > 1e-9) allesOk = false;
  }
}
zeilen.push(
  `${untergrenzeOhneVorgabe > 0 ? 'OK  ' : 'ROT '} Ohne detour_factor greift die ` +
  `Untergrenze in ${untergrenzeOhneVorgabe}/${gesamtOhne} Faellen — dort und nur ` +
  `dort trennt sie die Stufen`,
);
if (untergrenzeOhneVorgabe === 0) allesOk = false;

console.log(zeilen.join('\n'));
console.log(allesOk ? '\nERGEBNIS: alle Proben gruen' : '\nERGEBNIS: mindestens eine Probe ROT');
Deno.exit(allesOk ? 0 : 1);
