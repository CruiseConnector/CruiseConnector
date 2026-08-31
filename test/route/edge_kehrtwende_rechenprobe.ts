// 2026-09-01 (Vucko: "niemals in keiner situation dazu auffordert irgendwo auf
// einer strasse umzudrehen"): Rechenprobe fuer den Kehrtwenden-Zaehler.
//
// Der Code wird NICHT abgeschrieben, sondern zur Laufzeit aus
// supabase/functions/generate-cruise-route-v2/index.ts ausgeschnitten. Damit
// kann die Probe nicht von der echten Fassung abdriften.
//
// Start:  deno run --allow-read test/route/edge_kehrtwende_rechenprobe.ts

const QUELLE = new URL(
  '../../supabase/functions/generate-cruise-route-v2/index.ts',
  import.meta.url,
);

const datei = await Deno.readTextFile(QUELLE);
const von = datei.indexOf('function distanceMeters(');
const bis = datei.indexOf('// ─────────────────── Autobahn-Episoden');
if (von < 0 || bis < 0 || bis <= von) {
  console.error('FEHLER: Ausschnitt nicht gefunden — wurde index.ts umgebaut?');
  Deno.exit(2);
}
const ausschnitt = datei.slice(von, bis) +
  '\nexport { kehrtwendenZaehler };\n';
const modul = await import(
  'data:application/typescript;base64,' +
    btoa(unescape(encodeURIComponent(ausschnitt)))
);
const zaehle = modul.kehrtwendenZaehler as (
  c: [number, number][],
) => { anzahl: number; anzahlMitte: number; maxLaengeM: number };

// ── Geometrie-Helfer: Meter -> [lng, lat] ────────────────────────────────
const LAT0 = 47.4, LNG0 = 9.7;
const M_PRO_LAT = 110540;
const M_PRO_LNG = 111320 * Math.cos((LAT0 * Math.PI) / 180);
const pkt = (xM: number, yM: number): [number, number] =>
  [LNG0 + xM / M_PRO_LNG, LAT0 + yM / M_PRO_LAT];

/// Punkte im Abstand `schrittM` entlang der Strecke A->B (ohne Endpunkt).
function strecke(
  x1: number, y1: number, x2: number, y2: number, schrittM = 20,
): [number, number][] {
  const laenge = Math.hypot(x2 - x1, y2 - y1);
  const n = Math.max(1, Math.round(laenge / schrittM));
  const out: [number, number][] = [];
  for (let i = 0; i < n; i++) {
    out.push(pkt(x1 + ((x2 - x1) * i) / n, y1 + ((y2 - y1) * i) / n));
  }
  return out;
}

let fehler = 0;
function pruefe(name: string, ist: unknown, soll: unknown) {
  const ok = JSON.stringify(ist) === JSON.stringify(soll);
  if (!ok) fehler++;
  console.log(`${ok ? 'OK  ' : 'FEHL'}  ${name}: ist=${JSON.stringify(ist)} soll=${JSON.stringify(soll)}`);
}

// ── Fall 1: schnurgerade, keine Wende ────────────────────────────────────
{
  const g = [...strecke(0, 0, 0, 6000), pkt(0, 6000)];
  const r = zaehle(g);
  pruefe('gerade Strecke hat keine Wende', r.anzahl, 0);
}

// ── Fall 2: Vuckos Fall — Wende MITTEN auf der Strecke ───────────────────
// 2 km geradeaus, dann 875 m Stich hinauf und zurueck, dann 2 km weiter.
{
  const g = [
    ...strecke(0, 0, 0, 2000),
    ...strecke(0, 2000, 875, 2000),
    ...strecke(875, 2000, 0, 2000),
    ...strecke(0, 2000, 0, 4000),
    pkt(0, 4000),
  ];
  const r = zaehle(g);
  pruefe('Stich mitten auf der Strecke wird erkannt', r.anzahl >= 1, true);
  pruefe('und zaehlt als Wende in der MITTE', r.anzahlMitte >= 1, true);
}

// ── Fall 3: Ziel in der Sackgasse — Wende am ENDE, unvermeidbar ──────────
// 4 km geradeaus, dann 400 m Stich hinein und zurueck. Das Ziel liegt dort.
{
  const g = [
    ...strecke(0, 0, 0, 4000),
    ...strecke(0, 4000, 400, 4000),
    ...strecke(400, 4000, 0, 4000),
    pkt(0, 4000),
  ];
  const r = zaehle(g);
  pruefe('Sackgasse am Ende wird gezaehlt', r.anzahl >= 1, true);
  pruefe(
    'zaehlt aber NICHT als Wende in der Mitte (sonst "keine Route")',
    r.anzahlMitte,
    0,
  );
}

// ── Fall 4: Start in der Sackgasse ───────────────────────────────────────
{
  const g = [
    ...strecke(0, 0, 400, 0),
    ...strecke(400, 0, 0, 0),
    ...strecke(0, 0, 0, 4000),
    pkt(0, 4000),
  ];
  const r = zaehle(g);
  pruefe('Sackgasse am Start zaehlt nicht als Mitte', r.anzahlMitte, 0);
}

// ── Fall 5: zwei Wenden mitten drin ──────────────────────────────────────
{
  const g = [
    ...strecke(0, 0, 0, 1500),
    ...strecke(0, 1500, 700, 1500),
    ...strecke(700, 1500, 0, 1500),
    ...strecke(0, 1500, 0, 3000),
    ...strecke(0, 3000, 700, 3000),
    ...strecke(700, 3000, 0, 3000),
    ...strecke(0, 3000, 0, 4500),
    pkt(0, 4500),
  ];
  const r = zaehle(g);
  pruefe('zwei Wenden mitten drin werden beide gezaehlt', r.anzahlMitte >= 2, true);
}

console.log(fehler === 0 ? '\nALLE PROBEN GRUEN' : `\n${fehler} PROBE(N) FEHLGESCHLAGEN`);
Deno.exit(fehler === 0 ? 0 : 1);
