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
//    Relay-Haenger darf nicht „ausgefallen" bedeuten. Deshalb bis zu drei
//    Versuche; erst wenn ALLE drei scheitern, gilt der Host als unten.
//    Genauso macht es der Waechter auf PC2 selbst (gh_guardian_pc2.sh:
//    3 Fehlschlaege noetig).
//
// 2) HTTP 200 IST NICHT „GESUND".
//    /health liefert Klartext „OK" (kein JSON, entgegen der alten Doku).
//    Zusaetzlich wird /info gelesen: dort stehen die geladenen Profile. Ein
//    GraphHopper mit kaputtem Graph antwortet weiter mit 200, hat aber keine
//    Profile mehr. Das faellt nur hier auf.
//
// 3) GEMELDET WIRD NUR DER WECHSEL.
//    Bei jedem Lauf entsteht eine Verlaufszeile (2 Hosts * 24 = 48 am Tag,
//    nach 35 Tagen geraeumt). Ein Alarm geht aber nur raus, wenn sich der
//    Zustand AENDERT — Ausfall und Rueckkehr. Sonst waere es Laerm und man
//    wuerde den echten Ausfall uebersehen.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

const VERSUCHE = 3;
const ZEITLIMIT_MS = 9000;      // gh_guardian_pc2.sh nutzt 10 s; 6 s war zu eng
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

/** Ein Versuch. Misst nur um den fetch herum, damit der Kaltstart der
 *  Edge Function die Zahl nicht verfaelscht. */
async function einVersuch(url: string): Promise<{ ok: boolean; ms: number; http: number | null; text: string }> {
  const start = performance.now();
  try {
    const r = await fetch(url + '/health', {
      signal: AbortSignal.timeout(ZEITLIMIT_MS),
      headers: { 'cache-control': 'no-cache' },
    });
    const ms = Math.round(performance.now() - start);
    const text = (await r.text()).trim().slice(0, 120);
    return { ok: r.ok && text.toUpperCase().startsWith('OK'), ms, http: r.status, text };
  } catch (e) {
    return {
      ok: false,
      ms: Math.round(performance.now() - start),
      http: null,
      text: String((e as Error)?.name ?? e).slice(0, 120),
    };
  }
}

/** Liest die geladenen Profile. Ein GraphHopper mit kaputtem Graph antwortet
 *  weiter mit 200 auf /health, hat hier aber eine leere Liste. */
async function profileLesen(url: string): Promise<string[] | null> {
  try {
    const r = await fetch(url + '/info', { signal: AbortSignal.timeout(ZEITLIMIT_MS) });
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

  for (let i = 0; i < VERSUCHE; i++) {
    const v = await einVersuch(h.url);
    letzteHttp = v.http;
    letzterText = v.text;
    if (v.ok) {
      // Die schnellste erfolgreiche Antwort ist die ehrlichste Zahl: sie
      // enthaelt am wenigsten fremdes Rauschen (Relay-Umweg, Warteschlange).
      besteMs = besteMs === null ? v.ms : Math.min(besteMs, v.ms);
      if (i === 0) break;            // gleich beim ersten Versuch gut: fertig
    }
    if (i < VERSUCHE - 1) await new Promise((r) => setTimeout(r, 400));
  }

  if (besteMs === null) {
    return { up: false, ms: null, http: letzteHttp, detail: letzterText || 'keine Antwort', profile: null };
  }

  const profile = await profileLesen(h.url);
  const detail = profile === null
    ? 'OK, /info nicht lesbar'
    : (profile.length === 0 ? 'OK, aber KEINE Profile geladen' : 'OK, ' + profile.length + ' Profile');

  // Kein Profil geladen heisst: der Dienst antwortet, kann aber nicht routen.
  return { up: profile !== null && profile.length === 0 ? false : true, ms: besteMs, http: letzteHttp, detail, profile };
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

async function pruefeHost(h: Host, alt: Record<string, unknown> | undefined) {
  const m = await messen(h);
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
      await melden(
        'Routing-Server ausgefallen',
        h.anzeige + ' antwortet nicht mehr. Grund: ' + m.detail + '. Drei Versuche, alle fehlgeschlagen.',
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

  // Beide parallel: der Lauf soll nicht doppelt so lange dauern wie noetig.
  const ergebnis = await Promise.all(hosts.map((h) => pruefeHost(h, nachHost.get(h.host))));

  // Verlauf raeumen. 48 Zeilen am Tag, 35 Tage = rund 1700 Zeilen.
  const grenze = new Date(Date.now() - VERLAUF_TAGE * 86400000).toISOString();
  await db.from('infra_health_checks').delete().lt('geprueft', grenze);

  return new Response(JSON.stringify({ ok: true, ergebnis }), {
    headers: { 'content-type': 'application/json' },
  });
});
