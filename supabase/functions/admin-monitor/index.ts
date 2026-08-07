// ─────────────────────────────────────────────────────────────────────────────
// admin-monitor — Monitoring-Dashboard für CruiseConnect.
//
// 2026-08-07 (vucko): „Das Monitoring-Tool darf nie wieder die Datenbank
// überlasten. Es soll sich maximal alle 12 Stunden aktualisieren. Und ich
// möchte, dass es nicht von jedem angeschaut werden kann, sondern nur von mir
// und meinem Kollegen."
//
// ZWEI GRUNDLEGENDE ÄNDERUNGEN GEGENÜBER DER ALTEN FASSUNG:
//
// 1) DIESE FUNKTION RECHNET NICHTS MEHR.
//    Vorher rief sie fünf schwere RPCs auf und versuchte, das über einen
//    Cache in MODUL-VARIABLEN zu bremsen. Das ist Zustand pro Isolat — jedes
//    frisch gestartete Isolat fing bei null an. Gemessen: je 185 Aufrufe in
//    6,85 Tagen statt der versprochenen 14. Dazu zerstörte der Cache-Buster
//    des Clients die CDN-Bremse.
//    Jetzt rechnet ein pg_cron-Job zweimal täglich und legt das Ergebnis in
//    admin_metric_snapshots ab; ein eindeutiger Index auf den Halbtags-Slot
//    lässt höchstens einen Schnappschuss je Halbtag zu. Diese Funktion macht
//    nur noch EINEN indizierten SELECT. Ein Dashboard-Aufruf KANN die
//    schweren Abfragen nicht mehr auslösen — der Code dafür existiert hier
//    nicht mehr.
//
// 2) ECHTE ANMELDUNG STATT TOKEN IN DER URL.
//    Der alte Schutz war ?token=… — wer den Link hatte, war drin, und URLs
//    landen im Verlauf, in Lesezeichen und in Chat-Vorschauen. Jetzt schickt
//    das Dashboard das Zugangstoken des angemeldeten Nutzers im
//    Authorization-Header; hier wird es serverseitig geprüft und die
//    Nutzer-ID gegen monitor_admins abgeglichen. Jeder Versuch wird
//    protokolliert, unberechtigte lösen einen Alarm aus.
//
// Endpunkte:
//   GET  /admin-monitor                 -> HTML (Anmeldung + Dashboard)
//   POST /admin-monitor  (Bearer-Token) -> JSON mit Kennzahlen und Verlauf
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { SEITE } from './seite.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

// GraphHopper-Funnels (öffentliche /health). Kostet die Datenbank nichts.
const PC2_HEALTH = 'https://vucko2-hp-prodesk-600-g5-desktop-mini.taildddd94.ts.net/health';
const PC1_HEALTH = 'https://vucko.taildddd94.ts.net/health';

// Wie viele Schnappschüsse der Verlauf höchstens mitliefert. 800 Zeilen
// entsprechen bei zwei pro Tag gut 13 Monaten — genug für den Jahresfilter,
// und immer noch ein einziger indizierter SELECT.
const VERLAUF_MAX = 800;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false },
});

async function ping(url: string): Promise<{ up: boolean; ms: number | null }> {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { signal: AbortSignal.timeout(6000) });
    return { up: r.ok, ms: Date.now() - t0 };
  } catch {
    return { up: false, ms: null };
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-allow-methods': 'POST, OPTIONS',
      // Das Dashboard hängt an keiner fremden Quelle. Alles, was nicht von
      // hier oder von Supabase kommt, wird vom Browser blockiert.
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    },
  });
}

/** Schreibt den Versuch weg und meldet zurück, ob ein Alarm fällig ist. */
async function protokolliere(
  req: Request,
  userId: string | null,
  email: string | null,
  erfolg: boolean,
  grund: string,
): Promise<boolean> {
  try {
    const { data } = await admin.rpc('monitor_log_access', {
      p_user_id: userId,
      p_email: email,
      p_erfolg: erfolg,
      p_grund: grund,
      p_ip: req.headers.get('x-forwarded-for') ?? null,
      p_user_agent: req.headers.get('user-agent') ?? null,
    });
    return data === true;
  } catch (_) {
    return false;
  }
}

/**
 * Meldet den Admins einen unberechtigten Versuch.
 *
 * Bewusst ueber eine Zeile in `notifications` statt ueber einen direkten
 * Aufruf von send-push: Auf notifications sitzt bereits der Trigger, der die
 * Zustellung uebernimmt. Ein eigener Aufruf muesste dessen Vertrag
 * nachbauen — und der erwartet ein ganz anderes Format, als hier zunaechst
 * angenommen wurde.
 *
 * `from_user_id` ist der Empfaenger selbst. Die Spalte ist NOT NULL, und bei
 * einer Systemmeldung gibt es keinen Absender.
 */
async function alarmSenden(grund: string, email: string | null) {
  try {
    const { data: admins } = await admin
      .from('monitor_admins')
      .select('user_id')
      .eq('aktiv', true);
    if (!admins?.length) return;
    const wer = email ? ` von ${email}` : '';
    await admin.from('notifications').insert(
      admins.map((a) => ({
        user_id: a.user_id,
        from_user_id: a.user_id,
        type: 'monitor_alarm',
        payload: {
          title: 'Monitoring: unberechtigter Zugriff',
          body: `Versuch${wer}, das Dashboard zu oeffnen. Grund: ${grund}.`,
          grund,
        },
      })),
    );
  } catch (e) {
    console.error('[admin-monitor] Alarm konnte nicht gemeldet werden:', e);
  }
}

/**
 * Prüft die Anmeldung. Gibt bei Erfolg den Nutzer zurück, sonst eine Antwort.
 *
 * Bewusst in dieser Reihenfolge: erst Token vorhanden, dann Token gültig,
 * dann berechtigt. Jede Stufe wird eigens protokolliert, damit man im
 * Nachhinein unterscheiden kann zwischen „abgelaufene Sitzung" und
 * „jemand probiert etwas".
 */
type ZugangOk = { ok: true; name: string; userId: string };
type ZugangAbgelehnt = { ok: false; antwort: Response };

async function pruefeZugang(req: Request): Promise<ZugangOk | ZugangAbgelehnt> {
  const auth = req.headers.get('authorization') ?? '';
  const token = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';

  if (!token) {
    await protokolliere(req, null, null, false, 'kein_token');
    return { ok: false, antwort: json({ error: 'Nicht angemeldet.' }, 401) };
  }

  const { data, error } = await admin.auth.getUser(token);
  const user = data?.user ?? null;
  if (error || !user) {
    const alarm = await protokolliere(req, null, null, false, 'token_ungueltig');
    if (alarm) await alarmSenden('ungültiges Zugangstoken', null);
    return { ok: false, antwort: json({ error: 'Sitzung ungültig. Bitte neu anmelden.' }, 401) };
  }

  const { data: adminRow } = await admin
    .from('monitor_admins')
    .select('anzeigename')
    .eq('user_id', user.id)
    .eq('aktiv', true)
    .maybeSingle();

  if (!adminRow) {
    const alarm = await protokolliere(req, user.id, user.email ?? null, false, 'nicht_berechtigt');
    if (alarm) await alarmSenden('Konto ohne Berechtigung', user.email ?? null);
    // Bewusst dieselbe knappe Meldung wie oben: Wer nicht berechtigt ist,
    // soll nicht erfahren, ob sein Konto überhaupt existiert.
    return { ok: false, antwort: json({ error: 'Kein Zugriff auf dieses Dashboard.' }, 403) };
  }

  await protokolliere(req, user.id, user.email ?? null, true, 'ok');
  return { ok: true, name: adminRow.anzeigename as string, userId: user.id };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return json({}, 204);

  // ── Die Seite selbst ist öffentlich, enthält aber KEINE Daten. ───────────
  // Sie zeigt nur das Anmeldefenster; alles Weitere kommt erst nach der
  // Prüfung unten.
  if (req.method === 'GET') {
    return new Response(SEITE.replace('__ANON_KEY__', ANON_KEY).replace('__SUPABASE_URL__', SUPABASE_URL), {
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'x-frame-options': 'DENY',
        'referrer-policy': 'no-referrer',
      },
    });
  }

  if (req.method !== 'POST') return json({ error: 'Methode nicht erlaubt.' }, 405);

  const zugang = await pruefeZugang(req);
  if (!zugang.ok) return zugang.antwort;

  // ── EIN indizierter SELECT. Mehr passiert hier nicht. ────────────────────
  const { data: reihen, error } = await admin
    .from('admin_metric_snapshots')
    .select('taken_at, slot_key, metrics, history, today, compare, analytics')
    .order('taken_at', { ascending: false })
    .limit(VERLAUF_MAX);

  if (error) {
    return json({ error: `Schnappschüsse nicht lesbar: ${error.message}` }, 500);
  }
  if (!reihen?.length) {
    return json({
      error: 'Noch kein Schnappschuss vorhanden. Der erste entsteht beim nächsten Lauf (10:00 bzw. 22:00 UTC).',
      angemeldet_als: zugang.name,
    });
  }

  const neuester = reihen[0];
  const [pc2, pc1] = await Promise.all([ping(PC2_HEALTH), ping(PC1_HEALTH)]);

  return json({
    angemeldet_als: zugang.name,
    stand: neuester.taken_at,
    slot: neuester.slot_key,
    metrics: neuester.metrics,
    history: neuester.history,
    today: neuester.today,
    compare: neuester.compare,
    analytics: neuester.analytics,
    // Der ganze Tagesverlauf, damit das Dashboard 7 Tage, 30 Tage, 3 Monate
    // und 1 Jahr sowie Wochenvergleiche RECHNEN kann, ohne je wieder
    // nachzufragen.
    verlauf: reihen.map((z) => ({ t: z.taken_at, slot: z.slot_key, m: z.metrics })),
    abdeckung: {
      punkte: reihen.length,
      aeltester: reihen[reihen.length - 1]?.taken_at ?? null,
    },
    infra: { pc2, pc1 },
  });
});
