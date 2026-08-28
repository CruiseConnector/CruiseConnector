// ─────────────────────────────────────────────────────────────────────────────
// infra-health-check — stuendliche Ueberwachung der beiden Mini-PCs.
//
// 2026-08-07 (vucko): „schau das die verbindung zu den beiden mini pc's
// zuverlaessig ist und wirklich anzeigt wenn einer ausgefallen ist, das kann
// jede stunde mal kontrolliert werden und bei problemen oder
// verbindungsverlust direkt berichtet werden."
//
// WAS VORHER FALSCH WAR:
//   admin-monitor hat bei jedem Dashboard-Aufruf beide /health angefragt und
//   dabei hart `ms: 0` gemeldet — eine erfundene Zahl. Echte Messung: 150 bis
//   165 ms warm, 400 bis 560 ms kalt. Eine Verlangsamung war also unsichtbar.
//   Ausserdem gab es ohne Dashboard-Aufruf kein Signal und nie einen Alarm.
//
// DREI GRUNDSAETZE HIER:
//
// 1) EIN EINZELNER FEHLSCHLAG IST KEIN AUSFALL.
//    Der Weg zu den PCs laeuft ueber Tailscale Funnel. Ein einzelner
//    Relay-Haenger darf nicht „ausgefallen" bedeuten. Deshalb VIER
//    Versuche, ueber rund 14 Sekunden GESTAFFELT; erst wenn alle vier
//    scheitern, gilt der Host als unten.
//    ⚠ 27.08.: vorher waren es drei Versuche im Abstand von 400 ms, also
//    alles in einer Sekunde. Das reichte nicht — siehe die Messung bei
//    den Konstanten weiter unten.
//
// 2) HTTP 200 IST NICHT „GESUND".
//    /health liefert Klartext „OK" (kein JSON, entgegen der alten Doku).
//    Zusaetzlich wird /info gelesen: dort stehen die geladenen Profile. Ein
//    GraphHopper mit kaputtem Graph antwortet weiter mit 200, hat aber keine
//    Profile mehr. Das faellt nur hier auf.
//
// 3) ZWEI RECHNER STERBEN NICHT GLEICHZEITIG.
//    Fallen beide im selben Lauf aus, liegt der gemeinsame Weg brach
//    (Internet am Standort, Funnel, Supabase). Der Alarm sagt das dann
//    auch, statt zwei Server anzuklagen.
//
// 4) GEMELDET WIRD NUR DER WECHSEL.
//    Bei jedem Lauf entsteht eine Verlaufszeile (2 Hosts * 24 = 48 am Tag,
//    nach 35 Tagen geraeumt). Ein Alarm geht aber nur raus, wenn sich der
//    Zustand AENDERT — Ausfall und Rueckkehr. Sonst waere es Laerm und man
//    wuerde den echten Ausfall uebersehen.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

// ⚠ 27.08.2026: DAS FLATTERN KAM VOM MESSWEG, NICHT VON DEN SERVERN.
// Ausgewertet ueber 480 Pruefungen je Host seit 07.08.:
//   PC1  36 Fehler (7,5 %)   PC2  12 Fehler (2,5 %)
//   Antwortzeit im Schnitt 530 ms, p95 rund 750 ms, Spitze knapp 6 s
// Zum Vergleich direkt ueber Tailscale gemessen: 92 ms. Die 440 ms
// Unterschied sind der Funnel — die Anfrage laeuft von Supabase ueber
// Tailscales oeffentlichen Eingang und erst von dort zur Maschine.
//
// Die Fehler zerfallen in zwei Gruppen:
//   · lange Strecken (14, 7, 5 Pruefungen am Stueck) = echte Ausfaelle
//   · EINZELNE Pruefungen, verteilt ueber alle 24 Stunden, einmal bei
//     BEIDEN Hosts in derselben Sekunde = der Weg, nicht die Server.
//
// Die alte Staffelung war zu eng: drei Versuche im Abstand von 400 ms,
// also alles innerhalb einer Sekunde. Ein Relay-Haenger dauert laenger
// als das. Jetzt vier Versuche ueber rund 14 Sekunden verteilt — damit
// faellt ein kurzer Aussetzer durch, ein echter Ausfall nicht.
//
// ⚠⚠ DIE OBERGRENZE IST NICHT FREI WAEHLBAR.
// Der Cron-Auftrag `infra-health-hourly` ruft mit
// `timeout_milliseconds := 55000` auf. Wer die Staffelung laenger macht
// als das, bekommt keinen langsamen Lauf, sondern einen ABGEBROCHENEN —
// und dann steht im Dashboard der alte Stand, ohne dass es auffaellt.
// Rechnung fuer den schlimmsten Fall, alle vier Versuche laufen ins
// Zeitlimit:  22 s Zeitlimite + 14,2 s Pausen = 36,2 s je Host.
// Beide Hosts laufen parallel, dazu /info und die Schreibvorgaenge:
// rund 40 s. Bleibt Luft bis 55.
const PAUSEN_MS = [1200, 4000, 9000];    // zwischen Versuch 1/2, 2/3, 3/4
const ZEITLIMITE_MS = [5000, 5000, 6000, 6000];
const CRON_GRENZE_MS = 55000;            // muss zu cron.job passen
const VERSUCHE = ZEITLIMITE_MS.length;
const LANGSAM_AB_MS = 2500;     // gemessen normal: 150 bis 560 ms
const VERLAUF_TAGE = 35;
const ALARM_RUHE_MIN = 180;     // fuer nicht-kritische Meldungen (langsam)

type Host = { host: string; anzeige: string; url: string };

type Messung = {
  up: boolean;
  ms: number | null;
  http: number | null;
  detail: string;
  profile: string[] | null;
};

/** Aus einem Ausnahmenamen einen Satz machen, den man lesen kann.
 *
 * ⚠ Der Kunde hat 13 Stunden lang „TypeError" im Dashboard gesehen und
 * daraufhin am falschen Ende gesucht. `TypeError` ist der Name, den Deno
 * jeder fehlgeschlagenen Verbindung gibt — er sagt nichts ueber die
 * Ursache. Diese Tabelle sagt etwas. */
function klartext(name: string, http: number | null): string {
  if (http === 502) return 'Funnel erreicht, dahinter antwortet niemand (502)';
  if (http === 503) return 'Funnel meldet Dienst nicht verfuegbar (503)';
  if (http !== null && http >= 400) return 'HTTP ' + http + ' vom Server';
  // HTTP 200, aber im Text steht nicht „OK": der Dienst antwortet, sagt
  // aber etwas anderes als erwartet. Das ist ein eigener Fall.
  if (http !== null && http < 400 && !name) {
    return 'HTTP ' + http + ', aber die Antwort war nicht „OK"';
  }
  switch (name) {
    case 'TimeoutError': return 'Zeitueberschreitung, keine Antwort im Zeitlimit';
    case 'TypeError':    return 'Verbindung kam nicht zustande (Funnel oder Netz)';
    case 'AbortError':   return 'Anfrage abgebrochen';
    default:             return name || 'keine Antwort';
  }
}

/** Ein Versuch. Misst nur um den fetch herum, damit der Kaltstart der
 *  Edge Function die Zahl nicht verfaelscht. */
async function einVersuch(url: string, zeitlimit: number): Promise<{ ok: boolean; ms: number; http: number | null; text: string }> {
  const start = performance.now();
  try {
    const r = await fetch(url + '/health', {
      signal: AbortSignal.timeout(zeitlimit),
      headers: { 'cache-control': 'no-cache' },
    });
    const ms = Math.round(performance.now() - start);
    const text = (await r.text()).trim().slice(0, 120);
    const ok = r.ok && text.toUpperCase().startsWith('OK');
    return { ok, ms, http: r.status, text: ok ? text : klartext('', r.status) };
  } catch (e) {
    return {
      ok: false,
      ms: Math.round(performance.now() - start),
      http: null,
      text: klartext(String((e as Error)?.name ?? e), null).slice(0, 160),
    };
  }
}

/** Liest die geladenen Profile. Ein GraphHopper mit kaputtem Graph antwortet
 *  weiter mit 200 auf /health, hat hier aber eine leere Liste. */
async function profileLesen(url: string): Promise<string[] | null> {
  try {
    const r = await fetch(url + '/info', { signal: AbortSignal.timeout(ZEITLIMITE_MS[0]) });
    if (!r.ok) return null;
    const j = await r.json();
    const p = j?.profiles;
    if (!Array.isArray(p)) return null;
    return p.map((x: { name?: string }) => String(x?.name ?? '')).filter(Boolean);
  } catch {
    return null;
  }
}

async function messen(h: Host): Promise<Messung> {
  let besteMs: number | null = null;
  let letzteHttp: number | null = null;
  let letzterText = '';

  let gebraucht = 0;
  for (let i = 0; i < VERSUCHE; i++) {
    gebraucht = i + 1;
    const v = await einVersuch(h.url, ZEITLIMITE_MS[i]);
    letzteHttp = v.http;
    letzterText = v.text;
    if (v.ok) {
      // Die schnellste erfolgreiche Antwort ist die ehrlichste Zahl: sie
      // enthaelt am wenigsten fremdes Rauschen (Relay-Umweg, Warteschlange).
      besteMs = besteMs === null ? v.ms : Math.min(besteMs, v.ms);
      break;                          // geglueckt, mehr braucht es nicht
    }
    if (i < VERSUCHE - 1) await new Promise((r) => setTimeout(r, PAUSEN_MS[i]));
  }

  if (besteMs === null) {
    const gesamt = Math.round((PAUSEN_MS.reduce((a, b) => a + b, 0)
                             + ZEITLIMITE_MS.reduce((a, b) => a + b, 0)) / 1000);
    return {
      up: false, ms: null, http: letzteHttp, profile: null,
      detail: (letzterText || 'keine Antwort')
            + ' — ' + VERSUCHE + ' Versuche ueber bis zu ' + gesamt + ' s',
    };
  }

  const profile = await profileLesen(h.url);
  const detail = profile === null
    ? 'OK, /info nicht lesbar'
    : (profile.length === 0 ? 'OK, aber KEINE Profile geladen' : 'OK, ' + profile.length + ' Profile');

  // Kein Profil geladen heisst: der Dienst antwortet, kann aber nicht routen.
  // Wie viele Anlaeufe es gebraucht hat, steht mit dabei: eine Antwort im
  // vierten Versuch ist kein Ausfall, aber auch nicht gesund.
  const mitVersuch = gebraucht > 1 ? detail + ' (erst im ' + gebraucht + '. Versuch)' : detail;
  return { up: profile !== null && profile.length === 0 ? false : true, ms: besteMs, http: letzteHttp, detail: mitVersuch, profile };
}

/** Meldung an alle verknuepften Dashboard-Konten. Der Trigger auf
 *  notifications schickt daraus einen Push. */
async function melden(titel: string, text: string) {
  const { data: admins } = await db
    .from('monitor_admins')
    .select('user_id')
    .eq('aktiv', true)
    .not('user_id', 'is', null);
  if (!admins?.length) {
    console.error('[infra-health] Keine Empfaenger verknuepft, Meldung faellt aus:', titel);
    return;
  }
  await db.from('notifications').insert(
    admins.map((a) => ({
      user_id: a.user_id,
      from_user_id: a.user_id,
      type: 'monitor_alarm',
      payload: { title: titel, body: text, grund: 'infra' },
    })),
  );
}

async function pruefeHost(
  h: Host,
  alt: Record<string, unknown> | undefined,
  m: Messung,
  beideUnten: boolean,
) {
  const jetzt = new Date().toISOString();

  await db.from('infra_health_checks').insert({
    host: h.host, up: m.up, ms: m.ms, http_code: m.http, detail: m.detail,
  });

  const warUp = alt?.up as boolean | null | undefined;
  const wechsel = warUp !== null && warUp !== undefined && warUp !== m.up;
  const erstmalig = warUp === null || warUp === undefined;

  await db.from('infra_health_state').update({
    up: m.up,
    ms: m.ms,
    http_code: m.http,
    profile: m.profile,
    letzter_fehler: m.up ? null : m.detail,
    zuletzt_geprueft: jetzt,
    seit: (wechsel || erstmalig) ? jetzt : (alt?.seit as string | null) ?? jetzt,
  }).eq('host', h.host);

  if (wechsel) {
    if (!m.up) {
      // ⚠ Fallen BEIDE im selben Lauf aus, sind nicht zwei Rechner
      // gleichzeitig gestorben - dann liegt der gemeinsame Weg brach:
      // Internet am Standort, Tailscale-Funnel oder Supabase selbst.
      // Am 24.08. ist genau das passiert, und es standen zwei
      // Server-Alarme da, die beide in die falsche Richtung zeigten.
      await melden(
        beideUnten ? 'Beide Routing-Server weg — vermutlich der Weg'
                   : 'Routing-Server ausgefallen',
        beideUnten
          ? 'PC1 und PC2 antworten im selben Lauf nicht. Zwei Rechner fallen '
            + 'nicht gleichzeitig aus. Zuerst Internet am Standort, '
            + 'Tailscale-Funnel und Supabase pruefen, erst danach die '
            + 'Maschinen. Grund: ' + m.detail
          : h.anzeige + ' antwortet nicht mehr. Grund: ' + m.detail,
      );
    } else {
      await melden(
        'Routing-Server wieder da',
        h.anzeige + ' antwortet wieder, ' + m.ms + ' ms.',
      );
    }
    await db.from('infra_health_state').update({ alarm_zuletzt: jetzt }).eq('host', h.host);
  } else if (m.up && m.ms !== null && m.ms > LANGSAM_AB_MS) {
    // Langsam ist kein Ausfall, deshalb mit Ruhezeit: hoechstens alle 3 Stunden.
    const letzter = alt?.alarm_zuletzt ? new Date(alt.alarm_zuletzt as string).getTime() : 0;
    if (Date.now() - letzter > ALARM_RUHE_MIN * 60000) {
      await melden(
        'Routing-Server langsam',
        h.anzeige + ' braucht ' + m.ms + ' ms statt der ueblichen 150 bis 560 ms.',
      );
      await db.from('infra_health_state').update({ alarm_zuletzt: jetzt }).eq('host', h.host);
    }
  }

  return { host: h.host, up: m.up, ms: m.ms, detail: m.detail, wechsel };
}

// Sicherung gegen ein Auseinanderlaufen von Staffelung und Cron-Grenze.
// Faellt beim ersten Lauf auf, nicht erst beim naechsten Ausfall.
{
  const schlimmst = PAUSEN_MS.reduce((a, b) => a + b, 0)
                  + ZEITLIMITE_MS.reduce((a, b) => a + b, 0);
  if (schlimmst > CRON_GRENZE_MS - 12000) {
    console.error('[infra-health] Staffelung ' + schlimmst
      + ' ms ist zu lang fuer die Cron-Grenze ' + CRON_GRENZE_MS + ' ms.');
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });
  if (req.method !== 'POST') return new Response('Nur POST.', { status: 405 });

  const secret = req.headers.get('x-infra-secret') ?? '';
  const { data: erlaubt } = await db.rpc('infra_health_secret_ok', { p_secret: secret });
  if (erlaubt !== true) return new Response('Nicht erlaubt.', { status: 401 });

  const { data: zustand } = await db.from('infra_health_state').select('*');
  const nachHost = new Map((zustand ?? []).map((z) => [z.host as string, z]));

  const hosts: Host[] = (zustand ?? []).map((z) => ({
    host: z.host as string, anzeige: z.anzeige as string, url: z.url as string,
  }));

  // ⚠ ERST MESSEN, DANN BEWERTEN. Vorher hat jeder Host fuer sich gemessen
  // und sofort Alarm geschlagen. Damit war die Frage „sind beide weg?"
  // nicht beantwortbar, obwohl genau sie den Unterschied macht zwischen
  // einem Serverausfall und einem Wegproblem.
  // Beide parallel: der Lauf soll nicht doppelt so lange dauern wie noetig.
  const messungen = await Promise.all(hosts.map((h) => messen(h)));
  const beideUnten = hosts.length > 1 && messungen.every((m) => !m.up);

  const ergebnis = await Promise.all(
    hosts.map((h, i) => pruefeHost(h, nachHost.get(h.host), messungen[i], beideUnten)),
  );

  // Verlauf raeumen. 48 Zeilen am Tag, 35 Tage = rund 1700 Zeilen.
  const grenze = new Date(Date.now() - VERLAUF_TAGE * 86400000).toISOString();
  await db.from('infra_health_checks').delete().lt('geprueft', grenze);

  return new Response(JSON.stringify({ ok: true, beideUnten, ergebnis }), {
    headers: { 'content-type': 'application/json' },
  });
});
