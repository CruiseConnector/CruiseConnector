// ─────────────────────────────────────────────────────────────────────────────
// admin-monitor — Monitoring-Dashboard für CruiseConnect.
//
// 2026-08-07 (vucko): „Das Monitoring-Tool darf nie wieder die Datenbank
// überlasten, maximal alle 12 Stunden aktualisieren. Nur ich und mein Kollege
// sollen es sehen. Anfangspasswort Test123, nach der Erstanmeldung ändern wir
// es selbst. Und Benutzername statt E-Mail — Vucko und Luca."
//
// 2026-08-07, zweite Runde (vucko): „schau das die verbindung zu den beiden
// mini pc's zuverlässig ist … das kann jede stunde mal kontrolliert werden und
// bei problemen oder verbindungsverlust direkt berichtet werden."
//
// VIER GRUNDSÄTZE:
//
// 1) DIESE FUNKTION RECHNET NICHTS.
//    Früher rief sie fünf schwere RPCs auf und bremste das über einen Cache in
//    MODUL-VARIABLEN — Zustand pro Isolat, jedes frische fing bei null an.
//    Gemessen: je 185 Aufrufe in 6,85 Tagen statt der versprochenen 14.
//    Jetzt rechnet pg_cron zweimal täglich; ein eindeutiger Index auf den
//    Halbtags-Slot lässt höchstens einen Schnappschuss je Halbtag zu. Hier
//    passieren nur noch drei indizierte SELECTs. Die RPC-Aufrufe existieren in
//    diesem Code nicht mehr.
//
// 2) EIGENE ANMELDUNG, GETRENNT VON DER APP.
//    Auf auth.users liegen zwei Trigger, die für jedes neue Konto ein
//    App-Profil anlegen. Dashboard-Konten dort hätten die Kennzahlen
//    verfälscht, die dieses Dashboard anzeigt. Deshalb eine eigene, sehr
//    kleine Anmeldung: bcrypt in der Datenbank, Sitzungstoken als
//    Zufallswert, alles über SECURITY-DEFINER-Funktionen, auf die kein
//    Client Rechte hat.
//
// 3) DAS SCHWACHE STARTPASSWORT IST EINGEZÄUNT.
//    Solange „Test123" nicht geändert wurde, liefert diese Funktion KEINE
//    Kennzahlen aus, sondern ausschließlich `passwort_aendern_noetig`.
//
// 4) DIE MINI-PCS WERDEN HIER NICHT MEHR ANGEPINGT.
//    Vorher: bei JEDEM Dashboard-Aufruf zwei fetch auf fremde Rechner, sechs
//    Sekunden Zeitlimit, und danach ein hart erfundenes `ms: 0`. Wer das
//    Dashboard nicht öffnete, bekam nie ein Signal, und einen Alarm gab es
//    nie. Jetzt prüft infra-health-check stündlich per Cron mit echter
//    Zeitmessung und meldet bei Zustandswechsel. Hier wird nur noch der
//    gespeicherte Zustand GELESEN. Der Knopf „jetzt prüfen" im Dashboard
//    stößt denselben Lauf von Hand an, höchstens einmal pro Minute.
//
// Endpunkte (alle POST, Aktion im Rumpf):
//   {aktion:'login',       benutzer, passwort}   -> Token oder Fehler
//   {aktion:'daten',       token}                -> Kennzahlen + Verlauf + Infra
//   {aktion:'infra_jetzt', token}                -> Mini-PC-Prüfung von Hand
//   {aktion:'passwort',    token, alt, neu}      -> Passwortwechsel
//   {aktion:'logout',      token}                -> Sitzung verwerfen
//   GET                                          -> Hinweis (Seite liegt auf R2)
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// 800 Zeilen sind bei zwei Schnappschüssen pro Tag gut 13 Monate — genug für
// den Jahresfilter, und immer noch ein einziger indizierter SELECT.
const VERLAUF_MAX = 800;

// Sieben Tage stündliche Prüfung = 2 Hosts * 24 * 7 = 336 Zeilen.
const INFRA_VERLAUF_MAX = 400;

// Von Hand höchstens einmal pro Minute, damit der Knopf kein Werkzeug wird,
// mit dem man die beiden Mini-PCs beschießt.
const INFRA_MANUELL_ABSTAND_MS = 60_000;

const db = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });

// 2026-08-07 (vucko: „Failed to fetch"): Diese Kopfzeilen braucht AUCH die
// Vorabanfrage. Sie stehen deshalb getrennt und werden von beiden Wegen
// benutzt.
const KOPF = {
  'content-type': 'application/json',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'content-type, authorization, apikey, x-client-info',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-max-age': '86400',
  'x-content-type-options': 'nosniff',
  'referrer-policy': 'no-referrer',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: KOPF,
  });
}

const herkunft = (req: Request) =>
  (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || null;

async function protokolliere(
  req: Request, name: string | null, erfolg: boolean, grund: string,
): Promise<boolean> {
  try {
    const { data } = await db.rpc('monitor_log_access', {
      p_user_id: null,
      p_email: name,
      p_erfolg: erfolg,
      p_grund: grund,
      p_ip: herkunft(req),
      p_user_agent: req.headers.get('user-agent') ?? null,
    });
    return data === true;
  } catch {
    return false;
  }
}

/** Meldet unberechtigte Versuche über den bestehenden Benachrichtigungsweg.
 *
 *  2026-08-07: Das lief bis heute ins Leere. Die beiden AKTIVEN Konten hatten
 *  user_id = NULL, die Zeilen MIT user_id waren inaktiv — der Filter unten fand
 *  also nie einen Empfänger und meldete still gar nichts. Die Verknüpfung ist
 *  in der Migration infra_health_hourly_watch nachgezogen. Falls sie je wieder
 *  fehlt, steht das jetzt im Log, statt lautlos zu verschwinden. */
async function alarmSenden(grund: string, wer: string | null) {
  try {
    const { data: admins } = await db
      .from('monitor_admins')
      .select('user_id')
      .eq('aktiv', true)
      .not('user_id', 'is', null);
    if (!admins?.length) {
      console.error('[admin-monitor] ALARM OHNE EMPFAENGER:', grund, wer);
      return;
    }
    await db.from('notifications').insert(
      admins.map((a) => ({
        user_id: a.user_id,
        from_user_id: a.user_id,
        type: 'monitor_alarm',
        payload: {
          title: 'Monitoring: unberechtigter Zugriff',
          body: `Versuch${wer ? ` als „${wer}"` : ''}, das Dashboard zu öffnen. Grund: ${grund}.`,
          grund,
        },
      })),
    );
  } catch (e) {
    console.error('[admin-monitor] Alarm nicht gemeldet:', e);
  }
}

/** Stösst infra-health-check an. Das Geheimnis holt sich die Funktion über
 *  eine SECURITY-DEFINER-Funktion, auf die nur die Service-Rolle Rechte hat —
 *  so steht es nirgends im Klartext in dieser Datei. */
async function infraPruefungAnstossen(): Promise<boolean> {
  try {
    const { data: secret } = await db.rpc('infra_health_cron_secret_lesen');
    if (!secret) return false;
    const r = await fetch(`${SUPABASE_URL}/functions/v1/infra-health-check`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-infra-secret': String(secret) },
      body: JSON.stringify({ quelle: 'dashboard' }),
      signal: AbortSignal.timeout(45_000),
    });
    return r.ok;
  } catch (e) {
    console.error('[admin-monitor] Handprüfung fehlgeschlagen:', e);
    return false;
  }
}

/** Liest den gespeicherten Zustand der Mini-PCs. Kein Netzzugriff. */
async function infraLesen() {
  const [zustand, verlauf] = await Promise.all([
    db.from('infra_health_state')
      .select('host, anzeige, up, ms, http_code, profile, seit, zuletzt_geprueft, letzter_fehler')
      .order('host'),
    db.from('infra_health_checks')
      .select('host, geprueft, up, ms')
      .order('geprueft', { ascending: false })
      .limit(INFRA_VERLAUF_MAX),
  ]);
  return {
    hosts: zustand.data ?? [],
    verlauf: verlauf.data ?? [],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTSPERRE (2026-08-14, vucko: "lokalisiere die api und sperre vorlaeufig
// den zugang"): Seit dem Vormittag trifft alle 15-25 Minuten ein Aufruf mit
// einem abgelaufenen Sitzungstoken ein (belegt: POST 401 in den Logs, je einer
// pro Alarm-Push). Weder Vucko noch Luca noch dieser Rechner sind die Quelle.
// Bis zur Klaerung ist der Zugang KOMPLETT gesperrt - jede Anfrage bekommt
// 503, ohne Anmeldepruefung und OHNE Alarm-Push (der Push-Spam war das
// eigentliche Aergernis). Zum Entsperren: Konstante auf false, neu deployen.
const ZUGANG_GESPERRT = true;

Deno.serve(async (req) => {
  if (ZUGANG_GESPERRT) {
    return new Response(
      JSON.stringify({
        error: 'Das Monitoring ist voruebergehend gesperrt.',
      }),
      { status: 503, headers: { 'Content-Type': 'application/json' } },
    );
  }

  // 204 bedeutet „kein Inhalt". Ein Rumpf ist dabei VERBOTEN — der Versuch
  // wirft, die Funktion antwortet mit 500, der Browser bricht die
  // Vorabanfrage ab und meldet „Failed to fetch". Genau das ist passiert.
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: KOPF });

  if (req.method === 'GET') {
    // Supabase liefert HTML auf *.supabase.co als text/plain aus. Die Seite
    // liegt deshalb auf R2; hier steht nur der Verweis.
    return json({
      hinweis: 'Das Dashboard liegt unter https://tiles.cruiseconnector.at/monitor.html',
    });
  }
  if (req.method !== 'POST') return json({ error: 'Methode nicht erlaubt.' }, 405);

  const rumpf = await req.json().catch(() => ({}));
  const aktion = String(rumpf?.aktion ?? '');

  // ── Anmelden ────────────────────────────────────────────────────────────
  if (aktion === 'login') {
    const benutzer = String(rumpf.benutzer ?? '').slice(0, 60);
    const { data, error } = await db.rpc('monitor_login', {
      p_benutzer: benutzer,
      p_passwort: String(rumpf.passwort ?? '').slice(0, 200),
      p_ip: herkunft(req),
    });
    if (error) return json({ error: 'Anmeldung gerade nicht möglich.' }, 500);

    if (!data?.ok) {
      const grund = data?.grund === 'gesperrt' ? 'gesperrt' : 'passwort_falsch';
      const alarm = await protokolliere(req, benutzer, false, grund);
      if (alarm) await alarmSenden('falsches Passwort', benutzer);
      return json({
        error: grund === 'gesperrt'
          ? 'Zu viele Fehlversuche. Bitte in 15 Minuten erneut probieren.'
          : 'Benutzername oder Passwort stimmt nicht.',
      }, 401);
    }

    await protokolliere(req, benutzer, true, 'ok');
    return json({
      token: data.token,
      name: data.name,
      passwort_aendern_noetig: data.passwort_aendern_noetig === true,
    });
  }

  const token = String(rumpf.token ?? '');

  // ── Abmelden ────────────────────────────────────────────────────────────
  if (aktion === 'logout') {
    if (token) await db.from('monitor_sessions').delete().eq('token', token);
    return json({ ok: true });
  }

  // ── Ab hier ist eine gültige Sitzung Pflicht ────────────────────────────
  if (!token) {
    await protokolliere(req, null, false, 'kein_token');
    return json({ error: 'Nicht angemeldet.' }, 401);
  }
  const { data: sitzung } = await db.rpc('monitor_session_pruefen', { p_token: token });
  if (!sitzung?.ok) {
    const alarm = await protokolliere(req, null, false, 'token_ungueltig');
    if (alarm) await alarmSenden('ungültiges Sitzungstoken', null);
    return json({ error: 'Sitzung abgelaufen. Bitte neu anmelden.' }, 401);
  }

  // ── Passwort ändern ─────────────────────────────────────────────────────
  if (aktion === 'passwort') {
    const { data, error } = await db.rpc('monitor_passwort_aendern', {
      p_token: token,
      p_alt: String(rumpf.alt ?? ''),
      p_neu: String(rumpf.neu ?? ''),
    });
    if (error) return json({ error: 'Änderung gerade nicht möglich.' }, 500);
    if (!data?.ok) return json({ error: data?.grund ?? 'Änderung fehlgeschlagen.' }, 400);
    await protokolliere(req, sitzung.name, true, 'passwort_geaendert');
    return json({ ok: true });
  }

  // Auch hier gilt die Einzäunung des Startpassworts.
  if (sitzung.passwort_aendern_noetig === true) {
    return json({ passwort_aendern_noetig: true, angemeldet_als: sitzung.name });
  }

  // ── Mini-PCs von Hand prüfen ────────────────────────────────────────────
  if (aktion === 'infra_jetzt') {
    const { data: vorher } = await db
      .from('infra_health_state').select('zuletzt_geprueft')
      .order('zuletzt_geprueft', { ascending: false }).limit(1).maybeSingle();
    const alter = vorher?.zuletzt_geprueft
      ? Date.now() - new Date(vorher.zuletzt_geprueft).getTime()
      : Number.MAX_SAFE_INTEGER;
    if (alter < INFRA_MANUELL_ABSTAND_MS) {
      return json({
        ok: false,
        grund: 'zu_frueh',
        wartesekunden: Math.ceil((INFRA_MANUELL_ABSTAND_MS - alter) / 1000),
        infra: await infraLesen(),
      });
    }
    const ok = await infraPruefungAnstossen();
    return json({ ok, infra: await infraLesen() });
  }

  // ── Sofort-Aktualisierung ────────────────────────────────────────────────
  // 2026-08-09 (vucko): „eine sofortige Aktualisierung soll auch moeglich
  // sein." Rechnet den aktuellen Slot neu (mit 90-Sek-Cooldown in der DB gegen
  // Dauerklicken). Der 6-Stunden-Rhythmus bleibt unberuehrt.
  if (aktion === 'snapshot_jetzt') {
    const { data, error } = await db.rpc('admin_monitor_refresh_now');
    if (error) {
      return json({ ok: false, grund: 'fehler', meldung: error.message }, 500);
    }
    await protokolliere(req, sitzung.name, true, 'snapshot_jetzt');
    return json(data ?? { ok: false, grund: 'fehler' });
  }

  if (aktion !== 'daten') return json({ error: 'Unbekannte Aktion.' }, 400);

  // ── Drei indizierte SELECTs. Mehr passiert hier nicht. ───────────────────
  const [schnappschuesse, infra] = await Promise.all([
    db.from('admin_metric_snapshots')
      .select('taken_at, slot_key, metrics, history, today, compare, analytics, leute')
      .order('taken_at', { ascending: false })
      .limit(VERLAUF_MAX),
    infraLesen(),
  ]);

  const { data: reihen, error } = schnappschuesse;

  if (error) return json({ error: `Schnappschüsse nicht lesbar: ${error.message}` }, 500);
  if (!reihen?.length) {
    return json({
      error: 'Noch kein Schnappschuss vorhanden. Der erste entsteht beim nächsten Lauf (10:00 bzw. 22:00 UTC).',
      angemeldet_als: sitzung.name,
      infra,
    });
  }

  const neuester = reihen[0];

  return json({
    angemeldet_als: sitzung.name,
    stand: neuester.taken_at,
    slot: neuester.slot_key,
    metrics: neuester.metrics,
    history: neuester.history,
    today: neuester.today,
    compare: neuester.compare,
    analytics: neuester.analytics,
    // 2026-08-09 (vucko): „wer dazugekommen ist — nur mit In-App-Name — und
    // wie viele Personen zuletzt gefahren sind." Kommt aus demselben
    // Schnappschuss wie alles andere, kostet also keine zusaetzliche Abfrage.
    leute: neuester.leute,
    // Der ganze Tagesverlauf, damit das Dashboard 7 Tage, 14 Tage, 30 Tage,
    // 3 Monate und 1 Jahr sowie Wochenvergleiche RECHNEN kann, ohne je
    // nachzufragen.
    verlauf: reihen.map((z) => ({ t: z.taken_at, slot: z.slot_key, m: z.metrics })),
    abdeckung: {
      punkte: reihen.length,
      aeltester: reihen[reihen.length - 1]?.taken_at ?? null,
    },
    infra,
  });
});
