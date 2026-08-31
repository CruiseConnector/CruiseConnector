// ─────────────────────────────────────────────────────────────────────────────
// username-login — Anmelden mit dem @-Namen statt mit der E-Mail-Adresse.
//
// Vucko am 31.08.2026: "dass man sich entweder wenn man sich halt direkt
// anmeldet oder halt ein Konto mit seine E-Mail-Adresse hat oder allgemein mit
// Google, dass man sich auch mit seinen Benutzernamen nur mit seinem Passwort
// anmelden kann."
//
// WARUM DIESE FUNKTION UEBERHAUPT EXISTIERT
// Supabase-Auth kennt nur die E-Mail. Fuer eine Anmeldung mit dem @-Namen
// muss also irgendwo Name -> E-Mail aufgeloest werden. Der naheliegende Weg,
// eine Datenbankfunktion, die dem Client die Adresse zurueckgibt, ist ein
// Datenleck: die @-Namen sind oeffentlich (Profil, Rangliste, Community), die
// Adressen nicht. Wer eine solche Funktion hat, kann zu jeder Namensliste die
// passende Adressliste ziehen.
//
// Deshalb passiert die Aufloesung HIER, hinter service_role, und die Adresse
// verlaesst den Server nie:
//   1. Name -> Benutzer-ID          (RPC anmeldename_zu_benutzer_id)
//   2. Benutzer-ID -> E-Mail         (auth.admin.getUserById, service_role)
//   3. E-Mail + Passwort -> Sitzung  (GoTrue prueft das Passwort, nicht wir)
//   4. Antwort an den Client: NUR das refresh_token.
//
// Der Client tauscht das Token mit `auth.setSession(refreshToken)` gegen eine
// echte Sitzung. Er sieht die Adresse nie, und ohne richtiges Passwort gibt es
// aus dieser Funktion ueberhaupt nichts.
//
// WAS SIE BEWUSST NICHT LEISTET
// Sie verbirgt nicht, OB ein @-Name existiert. Das kann sie nicht, und sie
// muesste es auch nicht: die Namen sind ohnehin oeffentlich abfragbar. Geheim
// bleibt die Adresse, und die bleibt es in jedem Zweig.
//
// Deploy: config.toml -> [functions.username-login] verify_jwt = false.
// Die Anmeldung passiert ja gerade OHNE gueltige Sitzung; mit verify_jwt = true
// wuerde das Gateway den Publishable-Key als "Invalid JWT" abweisen (dieselbe
// Falle wie bei generate-cruise-route-v2, siehe Kommentar in der config.toml).
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
// Fuer den Passwort-Zuschuss reicht ein oeffentlicher Schluessel; er dient nur
// als apikey-Kopfzeile. Das Passwort prueft GoTrue, unabhaengig davon, welcher
// Schluessel die Anfrage begleitet. Faellt der anon-Schluessel aus der
// Umgebung (aeltere/neuere Projektvorlagen benennen ihn verschieden), nehmen
// wir den Service-Schluessel — das schwaecht nichts ab, weil ohne richtiges
// Passwort trotzdem keine Sitzung entsteht.
const PUBLIC_KEY = Deno.env.get('SUPABASE_ANON_KEY') ??
  Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
  SERVICE_ROLE;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Grenzen wie in lib/core/input_limits.dart. Laenger kann kein gueltiger Name
// und kein gueltiges Passwort sein; alles darueber ist Muell und wird gar
// nicht erst zur Datenbank durchgereicht.
const NAME_MIN = 3;
const NAME_MAX = 20;
const PASSWORT_MAX = 128;

// 2026-08-31: Zwei Deckel, absichtlich verschieden gedacht.
//
// Der Deckel je Name schuetzt EIN Konto: 10 Fehlversuche in 5 Minuten reichen
// niemandem, der sein eigenes Passwort tippt, und machen das Durchprobieren
// einer Passwortliste unbrauchbar langsam.
//
// Der Deckel je Adresse schuetzt die UEBRIGEN: ohne ihn koennte ein Angreifer
// mit einer Namensliste beliebig viele Konten gleichzeitig durchprobieren und
// dabei nie den Namensdeckel reissen. Er ist grosszuegig genug, dass ein
// ganzes Haus hinter einer Adresse (Studentenheim, Firmen-WLAN) nicht
// ausgesperrt wird.
//
// WICHTIG: check_rate_limit ist mit Absicht HART fail-open — jeder
// Datenbankfehler laesst die Anfrage durch. Fuer eine Anmeldung ist das
// vertretbar: faellt der Zaehler aus, prueft GoTrue das Passwort trotzdem.
// Ein Ausfall macht das Durchprobieren schneller, aber nie erfolgreich.
const LIMIT_NAME = { max: 10, windowSec: 300 };
const LIMIT_IP = { max: 60, windowSec: 300 };
const LIMIT_TIMEOUT_MS = 1500;

const admin = SUPABASE_URL && SERVICE_ROLE
  ? createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  : null;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return antwort({ fehler: 'methode_nicht_erlaubt' }, 405);
  }
  if (!admin || !PUBLIC_KEY) {
    console.error('[username-login] Umgebung unvollstaendig');
    return antwort({ fehler: 'server_nicht_bereit' }, 503);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return antwort({ fehler: 'ungueltige_anfrage' }, 400);
  }

  const name = text(body.benutzername) ?? text(body.username) ?? '';
  const passwort = rohText(body.passwort) ?? rohText(body.password) ?? '';

  if (
    name.length < NAME_MIN || name.length > NAME_MAX ||
    passwort.length === 0 || passwort.length > PASSWORT_MAX ||
    name.includes('@')
  ) {
    // Ein @ im Feld heisst: das ist eine Adresse, keine Kennung. Die App
    // schickt solche Eingaben gar nicht erst hierher, sie meldet sich damit
    // direkt bei Supabase an. Kommt es trotzdem an, ist es kein gueltiger
    // Aufruf dieser Funktion.
    return antwort({ fehler: 'ungueltige_anfrage' }, 400);
  }

  // Fuer den Zaehler reicht die Kleinschreibung. Das ist bewusst NICHT die
  // Faltung aus benutzername_schluessel: die gehoert der Datenbank, und ein
  // Zaehlerschluessel muss nur stabil sein, nicht exakt.
  const nameSchluessel = name.toLowerCase();
  const ip = req.headers.get('cf-connecting-ip') ??
    (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim();

  const proName = await darfNoch(
    `name:${nameSchluessel}`,
    'username_login_name',
    LIMIT_NAME.max,
    LIMIT_NAME.windowSec,
  );
  if (!proName.erlaubt) {
    return antwort(
      { fehler: 'zu_viele_versuche', erneut_in: proName.erneutIn },
      429,
    );
  }
  const proIp = await darfNoch(
    ip ? `ip:${ip}` : 'anon:shared',
    'username_login_ip',
    LIMIT_IP.max,
    LIMIT_IP.windowSec,
  );
  if (!proIp.erlaubt) {
    return antwort(
      { fehler: 'zu_viele_versuche', erneut_in: proIp.erneutIn },
      429,
    );
  }

  try {
    const { data: idData, error: idFehler } = await admin.rpc(
      'anmeldename_zu_benutzer_id',
      { p_name: name },
    );
    if (idFehler) {
      console.error('[username-login] Namensaufloesung fehlgeschlagen', {
        code: idFehler.code,
        message: idFehler.message,
      });
      return antwort({ fehler: 'serverfehler' }, 500);
    }
    const benutzerId = typeof idData === 'string' ? idData : null;
    if (!benutzerId) {
      // Unbekannter Name. Dieselbe Antwort wie ein falsches Passwort — wer
      // hier probiert, erfaehrt nicht, an welchem der beiden es lag.
      return antwort({ fehler: 'anmeldedaten_falsch' }, 401);
    }

    const { data: userData, error: userFehler } = await admin.auth.admin
      .getUserById(benutzerId);
    if (userFehler) {
      console.error('[username-login] Konto nicht lesbar', userFehler.message);
      return antwort({ fehler: 'serverfehler' }, 500);
    }
    const email = userData?.user?.email ?? '';
    if (!email) {
      // Konten, die nur ueber Apple mit verborgener Adresse entstanden sind,
      // haben unter Umstaenden keine nutzbare Adresse. Fuer die gibt es
      // keinen Passwortweg — also dieselbe neutrale Antwort.
      return antwort({ fehler: 'anmeldedaten_falsch' }, 401);
    }

    const anmelder = createClient(SUPABASE_URL, PUBLIC_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: sitzung, error: anmeldeFehler } = await anmelder.auth
      .signInWithPassword({ email, password: passwort });

    if (anmeldeFehler) {
      const meldung = (anmeldeFehler.message ?? '').toLowerCase();
      if (meldung.includes('not confirmed')) {
        // Der einzige Fall, in dem wir mehr sagen als "falsch": sonst steht
        // der Nutzer vor einem richtigen Passwort und einer Meldung, die
        // behauptet, es sei falsch. Die Adresse verraten wir trotzdem nicht.
        return antwort({ fehler: 'email_nicht_bestaetigt' }, 403);
      }
      if (
        meldung.includes('too many') || meldung.includes('rate limit') ||
        anmeldeFehler.status === 429
      ) {
        return antwort({ fehler: 'zu_viele_versuche', erneut_in: 60 }, 429);
      }
      return antwort({ fehler: 'anmeldedaten_falsch' }, 401);
    }

    const refreshToken = sitzung?.session?.refresh_token ?? '';
    if (!refreshToken) {
      console.error('[username-login] Anmeldung ohne Sitzung zurueckgekommen');
      return antwort({ fehler: 'serverfehler' }, 500);
    }
    // NUR das refresh_token. Kein access_token (der Client holt sich beim
    // Einloesen ohnehin ein frisches), keine E-Mail, keine Metadaten.
    return antwort({ refresh_token: refreshToken }, 200);
  } catch (e) {
    console.error('[username-login] Unerwarteter Fehler', String(e));
    return antwort({ fehler: 'serverfehler' }, 500);
  }
});

async function darfNoch(
  key: string,
  action: string,
  max: number,
  windowSec: number,
): Promise<{ erlaubt: boolean; erneutIn: number }> {
  if (!admin) return { erlaubt: true, erneutIn: 0 };
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), LIMIT_TIMEOUT_MS);
    const { data, error } = await admin
      .rpc('check_rate_limit', {
        p_key: key,
        p_action: action,
        p_max: max,
        p_window_seconds: windowSec,
      })
      .abortSignal(ctrl.signal)
      .maybeSingle();
    clearTimeout(t);
    if (error || !data) return { erlaubt: true, erneutIn: 0 };
    const row = data as { allowed?: boolean; retry_after?: number };
    return {
      erlaubt: row.allowed === true,
      erneutIn: row.retry_after ?? 0,
    };
  } catch (_) {
    return { erlaubt: true, erneutIn: 0 };
  }
}

/// Getrimmter Text aus dem Anfragekoerper, oder null.
function text(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  return v.length === 0 ? null : v;
}

/// Passwoerter werden NICHT getrimmt — ein fuehrendes oder abschliessendes
/// Leerzeichen kann Teil des Passworts sein, und stillschweigend etwas
/// abzuschneiden hiesse, ein richtiges Passwort abzulehnen.
function rohText(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function antwort(payload: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
