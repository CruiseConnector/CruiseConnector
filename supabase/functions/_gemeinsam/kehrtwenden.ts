// Die Wende-Erkennung, EINMAL fuer alle Server-Funktionen.
//
// 2026-09-01 (Vucko: „keine wendepunkte mitten auf den strassen erlauben"):
//
// Es gab kurzzeitig drei Kopien derselben Rechnung. Drei Kopien heisst: eine
// Strecke faellt je nach Weg mal durch das Tor und mal nicht, und niemand
// merkt es, weil jede Kopie fuer sich richtig aussieht. Genau dieses Muster
// hat hier schon einmal bei der Laender-Klassifikation zugeschlagen.
//
// Deshalb steht die Rechnung ab jetzt hier, und die Funktionen holen sie sich.
// Die Dart-Fassung in `lib/data/services/kehrtwenden_zaehler.dart` bleibt eine
// eigene Portierung — sie laeuft auf dem Handy. Der Test
// `test/route/kehrtwenden_portierung_test.dart` haelt beide zusammen.
//
// Koordinaten sind ueberall [longitude, latitude].

export const KEHRTWENDE_RASTER_M = 25;
export const KEHRTWENDE_NAEHE_M = 40;
export const KEHRTWENDE_MIN_WEG_M = 150;
export const KEHRTWENDE_MAX_WEG_M = 6000;
export const KEHRTWENDE_GEGENLAEUFIG_COS = -0.5;
export const KEHRTWENDE_ZELLE_M = 120;
export const KEHRTWENDE_BUENDEL_TOLERANZ = 12;
export const KEHRTWENDE_RAND_M = 300;

// Wie weit vor und hinter dem Scheitel der Kurs gemessen wird, und ab wie viel
// Grad dort wirklich gedreht wird.
//
// 2026-09-01 an 40 echten Pool-Strecken nachgemessen: Ohne diese Pruefung
// meldete die Zaehlung 66 Wenden — an 21 davon dreht die Strecke am Scheitel
// gar nicht (teils nur 22 Grad). Das sind Stellen, an denen die Route nur nah
// an sich selbst zurueckläuft, ohne dass jemand wenden muesste. Ein Tor auf
// der ungepruefeten Zahl haette jede dritte Strecke aus einem Grund
// abgelehnt, den es nicht gibt.
//
// 140 Grad und nicht 180: an einer echten Wende liegt die Gegenfahrbahn ein
// paar Meter versetzt, und die Rasterung glaettet die Spitze etwas ab.
export const KEHRTWENDE_DREH_FENSTER_M = 100;
export const KEHRTWENDE_DREH_GRAD = 140;

export function kursGrad(dx: number, dy: number): number {
  return (Math.atan2(dx, dy) * 180) / Math.PI;
}

export function kursDifferenz(a: number, b: number): number {
  let d = Math.abs(a - b) % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/// Dreht die Strecke am Rasterpunkt `scheitel` wirklich um?
export function drehtDortWirklich(
  xs: Float64Array,
  ys: Float64Array,
  n: number,
  scheitel: number,
): boolean {
  const fenster = Math.round(KEHRTWENDE_DREH_FENSTER_M / KEHRTWENDE_RASTER_M);
  const davor = scheitel - fenster;
  const danach = scheitel + fenster;
  if (davor < 0 || danach >= n) return false;
  const kursDavor = kursGrad(xs[scheitel] - xs[davor], ys[scheitel] - ys[davor]);
  const kursDanach = kursGrad(xs[danach] - xs[scheitel], ys[danach] - ys[scheitel]);
  return kursDifferenz(kursDavor, kursDanach) >= KEHRTWENDE_DREH_GRAD;
}
export const UEBERLAPP_MAX_PUNKTE = 20000;

export function ueberlappRaster(
  coords: [number, number][],
  schrittM: number,
): { xs: Float64Array; ys: Float64Array; n: number } {
  const lat0 = coords[0][1];
  const lng0 = coords[0][0];
  const mProLng = 111320 * Math.cos((lat0 * Math.PI) / 180);
  const mProLat = 110540;
  const px: number[] = [];
  const py: number[] = [];
  let vx = 0;
  let vy = 0;
  px.push(0);
  py.push(0);
  let rest = schrittM;
  for (let i = 1; i < coords.length; i++) {
    const nx = (coords[i][0] - lng0) * mProLng;
    const ny = (coords[i][1] - lat0) * mProLat;
    let dx = nx - vx;
    let dy = ny - vy;
    let len = Math.sqrt(dx * dx + dy * dy);
    while (len > 0 && len >= rest && px.length < UEBERLAPP_MAX_PUNKTE) {
      vx += (dx / len) * rest;
      vy += (dy / len) * rest;
      px.push(vx);
      py.push(vy);
      dx = nx - vx;
      dy = ny - vy;
      len = Math.sqrt(dx * dx + dy * dy);
      rest = schrittM;
    }
    rest -= len;
    vx = nx;
    vy = ny;
  }
  return { xs: Float64Array.from(px), ys: Float64Array.from(py), n: px.length };
}

export function kehrtwendenZaehler(
  coords: [number, number][],
): { anzahl: number; anzahlMitte: number; maxLaengeM: number } {
  if (!coords || coords.length < 2) {
    return { anzahl: 0, anzahlMitte: 0, maxLaengeM: 0 };
  }
  const { xs, ys, n } = ueberlappRaster(coords, KEHRTWENDE_RASTER_M);
  const minSchritte = Math.round(KEHRTWENDE_MIN_WEG_M / KEHRTWENDE_RASTER_M);
  const maxSchritte = Math.round(KEHRTWENDE_MAX_WEG_M / KEHRTWENDE_RASTER_M);
  if (n <= minSchritte + 2) return { anzahl: 0, anzahlMitte: 0, maxLaengeM: 0 };
  const rx = new Float64Array(n);
  const ry = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const a = i > 0 ? i - 1 : 0;
    const b = i < n - 1 ? i + 1 : n - 1;
    let dx = xs[b] - xs[a];
    let dy = ys[b] - ys[a];
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len > 0) {
      dx /= len;
      dy /= len;
    }
    rx[i] = dx;
    ry[i] = dy;
  }
  const zelle = KEHRTWENDE_ZELLE_M;
  const gitter = new Map<number, number[]>();
  const schluessel = (cx: number, cy: number) => cx * 1000003 + cy;
  for (let i = 0; i < n; i++) {
    const k = schluessel(Math.floor(xs[i] / zelle), Math.floor(ys[i] / zelle));
    const eimer = gitter.get(k);
    if (eimer) eimer.push(i);
    else gitter.set(k, [i]);
  }
  const naeheQuadrat = KEHRTWENDE_NAEHE_M * KEHRTWENDE_NAEHE_M;
  const partner = new Int32Array(n).fill(-1);
  for (let i = 0; i < n; i++) {
    const cx = Math.floor(xs[i] / zelle);
    const cy = Math.floor(ys[i] / zelle);
    let bester = -1;
    for (let ox = -1; ox <= 1; ox++) {
      for (let oy = -1; oy <= 1; oy++) {
        const eimer = gitter.get(schluessel(cx + ox, cy + oy));
        if (!eimer) continue;
        for (const j of eimer) {
          const abstandSchritte = j - i;
          if (abstandSchritte <= minSchritte) continue;
          if (abstandSchritte > maxSchritte) continue;
          const dx = xs[j] - xs[i];
          const dy = ys[j] - ys[i];
          if (dx * dx + dy * dy > naeheQuadrat) continue;
          if (rx[i] * rx[j] + ry[i] * ry[j] > KEHRTWENDE_GEGENLAEUFIG_COS) {
            continue;
          }
          if (bester < 0 || j < bester) bester = j;
        }
      }
    }
    partner[i] = bester;
  }
  let anzahl = 0;
  let anzahlMitte = 0;
  const gesamtM = n * KEHRTWENDE_RASTER_M;
  let i = 0;
  let maxLaengeM = 0;
  while (i < n) {
    if (partner[i] < 0) {
      i++;
      continue;
    }
    const start = i;
    const rueckkehr = partner[i];
    while (
      i + 1 < n && partner[i + 1] >= 0 &&
      Math.abs(partner[i + 1] - partner[i]) <= KEHRTWENDE_BUENDEL_TOLERANZ
    ) {
      i++;
    }
    anzahl++;
    const laengeM = (partner[start] - start) * KEHRTWENDE_RASTER_M;
    if (laengeM > maxLaengeM) maxLaengeM = laengeM;
    const vorDemStichM = start * KEHRTWENDE_RASTER_M;
    const nachDerRueckkehrM = gesamtM - partner[start] * KEHRTWENDE_RASTER_M;
    // Mittendrin heisst: vor UND nach der Wende liegt echte Strecke, UND an
    // ihrem Scheitel dreht die Route auch wirklich um. Die zweite Bedingung
    // ist kein Beiwerk — ohne sie ist jede dritte Meldung falsch.
    const scheitel = Math.round((start + partner[start]) / 2);
    if (
      vorDemStichM > KEHRTWENDE_RAND_M &&
      nachDerRueckkehrM > KEHRTWENDE_RAND_M &&
      drehtDortWirklich(xs, ys, n, scheitel)
    ) {
      anzahlMitte++;
    }
    i = Math.max(i + 1, rueckkehr);
  }
  return { anzahl, anzahlMitte, maxLaengeM: Math.round(maxLaengeM) };
}

// ─────────────── Geometrie einlesen ────────────────────────────────────────

/// Holt die Koordinaten aus einer GeoJSON-Geometrie.
///
/// Ein MultiLineString wird NICHT geplaettet, sondern in seine Abschnitte
/// zerlegt: eine Luecke zwischen zwei Abschnitten ist keine Strasse, und die
/// Wende-Erkennung wuerde ueber die Luftlinie hinweg falsche Partner finden.
export function abschnitteAus(geometry: unknown): [number, number][][] {
  if (!geometry || typeof geometry !== 'object') return [];
  const g = geometry as Record<string, unknown>;
  const roh = g.coordinates;
  if (!Array.isArray(roh)) return [];

  const alsPunktliste = (liste: unknown): [number, number][] => {
    if (!Array.isArray(liste)) return [];
    const punkte: [number, number][] = [];
    for (const p of liste) {
      if (!Array.isArray(p) || p.length < 2) continue;
      const lng = p[0];
      const lat = p[1];
      if (typeof lng !== 'number' || typeof lat !== 'number') continue;
      if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
      punkte.push([lng, lat]);
    }
    return punkte;
  };

  if (g.type === 'MultiLineString') {
    return roh.map(alsPunktliste).filter((t) => t.length >= 2);
  }
  const flach = alsPunktliste(roh);
  return flach.length >= 2 ? [flach] : [];
}
