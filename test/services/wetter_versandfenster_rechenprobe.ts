// 2026-08-24: Reine Rechenprobe fuer das Versandfenster des Wetter-Pushes.
//
// Der Code wird NICHT abgeschrieben, sondern zur Laufzeit aus
// supabase/functions/daily-weather-push/index.ts ausgeschnitten und als Modul
// geladen. Damit kann die Probe nicht von der echten Fassung abdriften.
//
// Start:  deno run --allow-read test/services/wetter_versandfenster_rechenprobe.ts
// (wird auch von test/services/wetter_push_nachmittag_test.dart aufgerufen)

const QUELLE = new URL(
  '../../supabase/functions/daily-weather-push/index.ts',
  import.meta.url,
);

const datei = await Deno.readTextFile(QUELLE);
const von = datei.indexOf('const WIEN =');
const bis = datei.indexOf('Versandfenster: reine Rechenlogik (Ende)');
if (von < 0 || bis < 0 || bis <= von) {
  console.error(
    'FEHLER: Ausschnitt nicht gefunden. Entweder fehlen die Markierungen\n' +
      '"Versandfenster: reine Rechenlogik (Anfang/Ende)" in index.ts, oder die\n' +
      'reine Logik wurde herausgeloest. Beides muss der Mensch entscheiden.',
  );
  Deno.exit(2);
}
const ausschnitt = datei.slice(von, bis) +
  '\nexport { FENSTER_ENDE_MINUTE, FENSTER_MINDESTENDE_MINUTE,' +
  ' KEHRAUS_TICKS,' +
  ' FENSTER_START_MINUTE, fensterEndeMinute, istFaellig, SLOT_MINUTEN,' +
  ' slotMinute, sonnenuntergangMinute, streuHash, wienStempel,' +
  ' wienTagesbeginn };\n';

const rohBytes = new TextEncoder().encode(ausschnitt);
let binaer = '';
for (const b of rohBytes) binaer += String.fromCharCode(b);
const modul = await import(
  'data:application/typescript;base64,' + btoa(binaer)
);

const START = modul.FENSTER_START_MINUTE as number;
const ENDE = modul.FENSTER_ENDE_MINUTE as number;
const MINDESTENDE = modul.FENSTER_MINDESTENDE_MINUTE as number;
const RASTER = modul.SLOT_MINUTEN as number;
const KEHRAUS = modul.KEHRAUS_TICKS as number;
const slotMinute = modul.slotMinute as (u: string, d: string, e: number) => number;
const istFaellig = modul.istFaellig as (
  u: string, d: string, jetzt: number, ende: number,
) => boolean;
const fensterEndeMinute = modul.fensterEndeMinute as (s: number | null) => number;
const sonnenuntergangMinute = modul.sonnenuntergangMinute as (j: unknown) => number | null;
const wienStempel = modul.wienStempel as (
  d: Date,
) => { datum: string; minute: number };
const wienTagesbeginn = modul.wienTagesbeginn as (d: Date) => string;

// ── Probenrahmen ──────────────────────────────────────────────────────────
const zeilen: string[] = [];
let allesOk = true;
function pruefe(name: string, bedingung: boolean, zusatz = '') {
  allesOk = bedingung && allesOk;
  zeilen.push(`${bedingung ? 'OK  ' : 'ROT '} ${name.padEnd(58)} ${zusatz}`);
}

function uhr(minute: number): string {
  const h = Math.floor(minute / 60).toString().padStart(2, '0');
  const m = (minute % 60).toString().padStart(2, '0');
  return `${h}:${m}`;
}

/// 183 Nutzer — so viele haben am 24.08. eine Wetter-Meldung bekommen.
const NUTZER: string[] = [];
for (let i = 0; i < 183; i++) {
  const h = (0x9e3779b1 * (i + 1)) >>> 0;
  NUTZER.push(
    `${h.toString(16).padStart(8, '0')}-4407-45cc-8470-${
      (h ^ 0x5bf03635).toString(16).padStart(8, '0')
    }abcd`,
  );
}

// ── (1) Vuckos Fenster ────────────────────────────────────────────────────
pruefe(
  '(1a) Fenster beginnt um 13:00',
  START === 13 * 60,
  `START=${uhr(START)}`,
);
pruefe(
  '(1b) Fenster endet um 20:00',
  ENDE === 20 * 60,
  `ENDE=${uhr(ENDE)}`,
);
pruefe(
  '(1c) 08:00 — die alte Uhrzeit — ist nicht mehr faellig',
  NUTZER.every((u) => !istFaellig(u, '2026-08-25', 8 * 60, ENDE)),
  'kein Nutzer bekommt morgens noch etwas',
);
pruefe(
  '(1d) 12:59 ist noch zu frueh, 20:00 schon zu spaet',
  NUTZER.every((u) =>
    !istFaellig(u, '2026-08-25', 12 * 60 + 59, ENDE) &&
    !istFaellig(u, '2026-08-25', 20 * 60, ENDE)
  ),
);

// ── (2) Jeder Slot liegt im Fenster und auf dem Raster ────────────────────
{
  let drin = true;
  let aufRaster = true;
  for (let tag = 1; tag <= 28; tag++) {
    const datum = `2026-09-${tag.toString().padStart(2, '0')}`;
    for (const u of NUTZER) {
      const s = slotMinute(u, datum, ENDE);
      if (s < START || s >= ENDE) drin = false;
      if ((s - START) % RASTER !== 0) aufRaster = false;
    }
  }
  pruefe('(2a) Kein Slot faellt aus dem Fenster (28 Tage x 183 Nutzer)', drin);
  pruefe('(2b) Alle Slots liegen auf dem 5-Minuten-Raster', aufRaster);
}

// ── (3) "immer unterschiedlich" — ueber die Tage ──────────────────────────
{
  // Vorher war diese Zahl fuer JEDEN Nutzer exakt 1: 08:00, jeden Tag.
  // Bei 81 Slots und 30 Ziehungen sind rund 25 verschiedene Uhrzeiten zu
  // erwarten; die Schranke liegt bewusst darunter, damit die Probe eine
  // kaputte Streuung meldet und nicht das normale Rauschen.
  const proNutzer: number[] = [];
  for (const u of NUTZER) {
    const gesehen = new Set<number>();
    for (let tag = 1; tag <= 30; tag++) {
      gesehen.add(slotMinute(u, `2026-09-${tag.toString().padStart(2, '0')}`, ENDE));
    }
    proNutzer.push(gesehen.size);
  }
  const schlechtester = Math.min(...proNutzer);
  const schnitt = proNutzer.reduce((a, b) => a + b, 0) / proNutzer.length;
  pruefe(
    '(3a) In 30 Tagen mindestens 15 verschiedene Uhrzeiten je Nutzer',
    schlechtester >= 15,
    `schlechtester=${schlechtester}, Schnitt=${schnitt.toFixed(1)} von 30 (vorher: 1)`,
  );

  // Dass zwei aufeinanderfolgende Tage einmal dieselbe Minute treffen, ist
  // bei 81 Slots kein Fehler, sondern Zufall (rund 1,2 % der Paare). Ein
  // deutlich hoeherer Anteil hiesse: die Streuung haengt gar nicht am Datum.
  let paare = 0, gleich = 0;
  for (const u of NUTZER) {
    for (let tag = 1; tag < 30; tag++) {
      const a = slotMinute(u, `2026-09-${tag.toString().padStart(2, '0')}`, ENDE);
      const b = slotMinute(u, `2026-09-${(tag + 1).toString().padStart(2, '0')}`, ENDE);
      paare++;
      if (a === b) gleich++;
    }
  }
  const anteil = gleich / paare;
  pruefe(
    '(3b) Kaum ein Nutzer bekommt zwei Tage nacheinander dieselbe Minute',
    anteil < 0.04,
    `${(anteil * 100).toFixed(2)} % der ${paare} Tagespaare (Zufallserwartung 1,2 %)`,
  );
}

// ── (4) "immer unterschiedlich" — zwischen den Nutzern ────────────────────
{
  const zaehler = new Map<number, number>();
  for (const u of NUTZER) {
    const s = slotMinute(u, '2026-08-25', ENDE);
    zaehler.set(s, (zaehler.get(s) ?? 0) + 1);
  }
  const belegteSlots = zaehler.size;
  const groesster = Math.max(...zaehler.values());
  pruefe(
    '(4a) 183 Nutzer verteilen sich auf mindestens 50 Uhrzeiten',
    belegteSlots >= 50,
    `${belegteSlots} von ${Math.floor((ENDE - START) / RASTER) - KEHRAUS} moeglichen belegt`,
  );
  pruefe(
    '(4b) Kein Zeitpunkt buendelt mehr als 10 Nutzer',
    groesster <= 10,
    `groesste Gruppe=${groesster} (vorher: 183 um 08:00)`,
  );
}

// ── (5) Ein Tagesdurchlauf: jeder genau einmal, keiner faellt aus ─────────
function tagDurchspielen(
  datum: string, ende: number, tickAuslassen: (m: number) => boolean,
): Map<string, number> {
  const versand = new Map<string, number>();
  for (let m = START; m < ende; m += RASTER) {
    if (tickAuslassen(m)) continue;
    for (const u of NUTZER) {
      if (versand.has(u)) continue; // Tagespruefung (Vorpruefung + UNIQUE)
      if (!istFaellig(u, datum, m, ende)) continue;
      versand.set(u, m);
    }
  }
  return versand;
}
{
  const versand = tagDurchspielen('2026-08-25', ENDE, () => false);
  pruefe(
    '(5a) Alle 183 Nutzer bekommen an einem vollstaendigen Tag genau eine',
    versand.size === NUTZER.length,
    `${versand.size} von ${NUTZER.length}`,
  );
  const punktgenau = NUTZER.every(
    (u) => versand.get(u) === slotMinute(u, '2026-08-25', ENDE),
  );
  pruefe('(5b) Und zwar genau in ihrem eigenen Slot', punktgenau);
}

// ── (6) Nachzuegler-Regel: ausgefallene Ticks kosten keinen Tag ───────────
{
  // Jeder zweite Tick faellt aus.
  const a = tagDurchspielen('2026-08-25', ENDE, (m) => ((m - START) / RASTER) % 2 === 1);
  pruefe(
    '(6a) Jeder zweite Tick faellt aus — trotzdem bekommt jeder etwas',
    a.size === NUTZER.length,
    `${a.size} von ${NUTZER.length}`,
  );
  // Eine ganze Stunde Ausfall mitten im Fenster.
  const b = tagDurchspielen(
    '2026-08-25', ENDE,
    (m) => m >= 15 * 60 && m < 16 * 60,
  );
  pruefe(
    '(6b) Eine Stunde Totalausfall — trotzdem bekommt jeder etwas',
    b.size === NUTZER.length,
    `${b.size} von ${NUTZER.length}`,
  );
  // Nur der allerletzte Tick laeuft: der Kehraus.
  const c = tagDurchspielen('2026-08-25', ENDE, (m) => m !== ENDE - RASTER);
  pruefe(
    '(6c) Nur der letzte Tick laeuft — er kehrt alles zusammen',
    c.size === NUTZER.length,
    `${c.size} von ${NUTZER.length} um ${uhr(ENDE - RASTER)}`,
  );
  const alleNachSlot = NUTZER.every((u) => (a.get(u) ?? -1) >= slotMinute(u, '2026-08-25', ENDE));
  pruefe('(6d) Nachgeholt wird nie VOR dem eigenen Slot', alleNachSlot);
}

// ── (7) Warum die Tagespruefung nicht wegfallen darf ──────────────────────
{
  // Ohne Tagesgedaechtnis wuerde die "Slot erreicht ODER vorbei"-Regel jeden
  // Nutzer bis zum Fensterende bei JEDEM Tick erneut treffen. Diese Probe
  // haelt fest, dass die Streuung allein nicht gegen Doppeltes schuetzt —
  // das tun die Vorpruefung und der UNIQUE-Index aus der Migration.
  let ohneGedaechtnis = 0;
  for (let m = START; m < ENDE; m += RASTER) {
    for (const u of NUTZER) if (istFaellig(u, '2026-08-25', m, ENDE)) ohneGedaechtnis++;
  }
  pruefe(
    '(7) Ohne Tagespruefung waere es ein Vielfaches — sie traegt die Last',
    ohneGedaechtnis > NUTZER.length * 10,
    `${ohneGedaechtnis} Sendungen statt ${NUTZER.length}`,
  );
}

// ── (8) Sommerzeit: derselbe UTC-Zeitpunkt, zwei Wiener Uhrzeiten ─────────
{
  const sommer = wienStempel(new Date('2026-08-24T11:00:00Z'));
  const winter = wienStempel(new Date('2026-11-24T11:00:00Z'));
  pruefe(
    '(8a) 11:00 UTC ist im Sommer 13:00 Wiener Zeit',
    sommer.minute === 13 * 60 && sommer.datum === '2026-08-24',
    `${sommer.datum} ${uhr(sommer.minute)}`,
  );
  pruefe(
    '(8b) Derselbe UTC-Zeitpunkt ist im Winter erst 12:00',
    winter.minute === 12 * 60 && winter.datum === '2026-11-24',
    `${uhr(winter.minute)} — ein fester UTC-Zeitpunkt wandert also`,
  );
  // Umstellungstag 25.10.2026: 00:00 UTC ist noch Sommerzeit (02:00),
  // 12:00 UTC ist schon Winterzeit (13:00).
  const umstellung = wienStempel(new Date('2026-10-25T12:00:00Z'));
  pruefe(
    '(8c) Am Umstellungstag rechnet Intl selbst richtig',
    umstellung.minute === 13 * 60 && umstellung.datum === '2026-10-25',
    `25.10. 12:00 UTC -> ${uhr(umstellung.minute)}`,
  );
  pruefe(
    '(8d) Wiener Tagesbeginn traegt den Zonenversatz',
    wienTagesbeginn(new Date('2026-08-24T11:00:00Z')) === '2026-08-24T00:00:00+02:00' &&
      wienTagesbeginn(new Date('2026-11-24T11:00:00Z')) === '2026-11-24T00:00:00+01:00',
    wienTagesbeginn(new Date('2026-11-24T11:00:00Z')),
  );
  // Der alte Fehler: 01:03 Wiener Zeit am 24.05. lag in UTC im 23.05.
  const nacht = wienStempel(new Date('2026-05-23T23:03:00Z'));
  pruefe(
    '(8e) 23:03 UTC ist in Wien schon der naechste Tag — der alte Doppel-Fehler',
    nacht.datum === '2026-05-24',
    `UTC-Datum 2026-05-23, Wiener Datum ${nacht.datum}`,
  );
}

// ── (9) Sonnenuntergang begrenzt das Fenster ──────────────────────────────
{
  const aus = (s: string) => sonnenuntergangMinute({ daily: { sunset: [s] } });
  pruefe(
    '(9a) Sonnenuntergang wird aus der OpenMeteo-Antwort gelesen',
    aus('2026-08-24T20:07') === 20 * 60 + 7,
    `${aus('2026-08-24T20:07')}`,
  );
  pruefe(
    '(9b) Fehlt das Feld, bleibt es bei Vuckos 20:00',
    sonnenuntergangMinute({}) === null && fensterEndeMinute(null) === ENDE,
  );
  pruefe(
    '(9c) Im Sommer aendert die Regel nichts (Untergang 20:07)',
    fensterEndeMinute(20 * 60 + 7) === ENDE,
    `Ende=${uhr(fensterEndeMinute(20 * 60 + 7))}`,
  );
  pruefe(
    '(9d) Im November endet das Fenster mit dem Licht (Untergang 16:52)',
    fensterEndeMinute(16 * 60 + 52) === 16 * 60 + 52,
    `Ende=${uhr(fensterEndeMinute(16 * 60 + 52))} statt 20:00`,
  );
  pruefe(
    '(9e) Unsinnige Antwort kann das Fenster nicht zuschnueren',
    fensterEndeMinute(9 * 60) === MINDESTENDE,
    `Ende=${uhr(fensterEndeMinute(9 * 60))}`,
  );
  // Auch im verkuerzten Winterfenster darf kein Tag ausfallen.
  const winterEnde = fensterEndeMinute(16 * 60 + 52);
  const v = tagDurchspielen('2026-11-24', winterEnde, () => false);
  pruefe(
    '(9f) Auch im verkuerzten Winterfenster bekommt jeder genau eine',
    v.size === NUTZER.length &&
      [...v.values()].every((m) => m >= START && m < winterEnde),
    `${v.size} von ${NUTZER.length}, spaetestens ${uhr(Math.max(...v.values()))}`,
  );
}

console.log(zeilen.join('\n'));
console.log(allesOk ? '\nAlle Proben gruen.' : '\nMindestens eine Probe ROT.');
Deno.exit(allesOk ? 0 : 1);
