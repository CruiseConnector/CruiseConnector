// send-push — Fanout einer notifications-Zeile als echte FCM-Push.
//
// 2026-05-31 (vucko): Wird vom DB-Trigger trg_notify_push_on_notification per
// pg_net aufgerufen (AFTER INSERT auf public.notifications). Deckt damit ALLE
// Notification-Typen automatisch ab: like, comment, repost, follow,
// friend_request, weather_recommendation, group_*, trip_reminder …
//
// Ablauf:
//   1. x-push-secret prüfen (Shared Secret, siehe Migration/Doku).
//   2. notifications-record aus dem Body lesen.
//   3. Device-Tokens des Empfängers laden (service_role, umgeht RLS).
//   4. (title, body) serverseitig rendern (Spiegel von NotificationService.renderTexts).
//   5. Service-Account-JWT (RS256, Web Crypto) → OAuth2 Access-Token.
//   6. Pro Token an FCM HTTP v1 zustellen; tote Tokens (UNREGISTERED/404) löschen.
//
// Secrets (Function-Env, via `supabase secrets set`):
//   * PUSH_WEBHOOK_SECRET  — identisch zum Vault-Secret push_webhook_secret
//   * FCM_SERVICE_ACCOUNT  — Service-Account-JSON aus der Firebase Console
//   * SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — automatisch vorhanden
//
// Deploy ohne JWT-Verify (Trigger schickt keinen Supabase-JWT):
//   config.toml → [functions.send-push] verify_jwt = false

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const PUSH_WEBHOOK_SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET') ?? '';
const FCM_SERVICE_ACCOUNT = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';

interface NotificationRecord {
  id?: string;
  user_id: string;
  from_user_id?: string | null;
  type: string;
  reference_id?: string | null;
  payload?: Record<string, unknown> | null;
  aggregate_count?: number | null;
  // 2026-08-24: Der Trigger schickt die komplette notifications-Zeile, also
  // auch created_at. Der Wetter-Text waehlt darueber seine Tagesvariante —
  // so trifft der Push denselben Eintrag wie die App.
  created_at?: string | null;
}

// ── FCM HTTP v1 Auth (Service-Account → OAuth2 Access-Token) ────────────────

function base64UrlFromBytes(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlFromString(str: string): string {
  return base64UrlFromBytes(new TextEncoder().encode(str));
}

function pemToPkcs8Buffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const raw = atob(b64);
  // Direkt in einen echten ArrayBuffer schreiben (crypto.subtle.importKey
  // verlangt BufferSource über ArrayBuffer, nicht Uint8Array<ArrayBufferLike>).
  const buffer = new ArrayBuffer(raw.length);
  const bytes = new Uint8Array(buffer);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return buffer;
}

// deno-lint-ignore no-explicit-any
async function getAccessToken(sa: any): Promise<string> {
  const tokenUri: string = sa.token_uri ?? 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlFromString(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64UrlFromString(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: tokenUri,
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claim}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8Buffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sigBuf = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlFromBytes(new Uint8Array(sigBuf))}`;
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' +
      encodeURIComponent(jwt),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error('FCM token exchange failed: ' + JSON.stringify(data));
  }
  return data.access_token as string;
}

async function sendToToken(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; remove: boolean }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: 'HIGH',
            notification: { channel_id: 'cruise_default', sound: 'default' },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: { aps: { sound: 'default', badge: 1 } },
          },
        },
      }),
    },
  );
  if (res.ok) return { ok: true, remove: false };
  const errText = await res.text();
  // Nur eindeutig tote Tokens entfernen — NICHT bei generischen Fehlern.
  const remove = res.status === 404 || /UNREGISTERED/i.test(errText);
  console.error(`[send-push] FCM ${res.status}: ${errText.slice(0, 240)}`);
  return { ok: false, remove };
}

// ── Wetter-Meldung: Wortlaut ───────────────────────────────────────────────
//
// 2026-08-24 (vucko, Auftrag „Nachmittags-Meldung"): Der Titel stand hier
// fest verdrahtet („Bestes Cruise-Wetter") — jeden Tag derselbe Satz auf dem
// Sperrbildschirm, und darunter zeigte die App einen anderen Text.
//
// Diese Tabelle ist die ZEICHENGLEICHE Kopie von WetterPushTexte in
// lib/data/services/notification_service.dart. Wer hier etwas aendert,
// aendert es dort mit; test/services/wetter_push_texte_test.dart vergleicht
// beide Dateien und schlaegt sonst fehl.

const WETTER_MILD: string[][] = [
  ['Bestes Wetter für Kurven', '{temp}° und die Landstraße ist leer. Hol dir eine Route'],
  ['Der Nachmittag gehört dir', '{temp}° draußen. Such dir eine kurvige Runde und fahr los'],
  ['Feierabendrunde?', '{temp}°, eine Stunde Kurven und du bist rechtzeitig zurück'],
  ['Perfekte Fahrtemperatur', '{temp}° sind genau richtig. Motor an und ab in die Berge'],
  ['Jetzt lohnt sich der Weg', '{temp}° draußen. Wir bauen dir eine Strecke voller Kurven'],
  ['Kurvenwetter', '{temp}° und kaum Wind. Deine Runde wartet in der App'],
  ['Zeit für frische Luft', '{temp}°, Fenster runter und raus auf die Landstraße'],
  ['Deine Strecke steht bereit', '{temp}° draußen. Sag uns wie weit, wir bauen die Kurven'],
  ['Nachmittag mit {temp}°', 'Die Straßen sind frei. Zwei Klicks und deine Runde steht'],
  ['{temp}° und die Straße ruft', 'Zwei Stunden Kurven, dann bist du zurück. Route in der App'],
  ['Guter Tag zum Cruisen', '{temp}° draußen. Wähle deine Länge, den Rest machen wir'],
  ['Raus aus dem Alltag', '{temp}°, eine kurze Runde reicht schon zum Abschalten'],
  ['Die Berge sind nah', '{temp}° draußen. Deine Passstraße ist zwei Klicks entfernt'],
  ['Kurven statt Couch', '{temp}°, hol dir eine Route und leg einfach los'],
  ['Der Sprit ist es wert', '{temp}° draußen. Eine Runde durch die Hügel und der Tag zählt'],
  ['Sonnenuntergang mitnehmen', '{temp}° jetzt. In zwei Stunden steht die Sonne genau richtig'],
  ['Straßen frei bei {temp}°', 'Such dir eine Runde in der App und fahr sie noch heute'],
  ['Heute lohnt der Umweg', '{temp}° draußen. Die kurvige Strecke dauert kaum länger'],
  ['Zeit für eine Ausfahrt', '{temp}°, eine Runde durchs Grüne und der Tag ist gerettet'],
  ['Der Asphalt ist warm', '{temp}° draußen. Beste Bedingungen für eine ruhige Runde'],
  ['Noch ist es hell', '{temp}° draußen. Für eine Runde reicht das Licht locker'],
  ['Deine Kurven für heute', '{temp}°, sag uns die Länge und wir legen die Strecke'],
  ['Cruisen bei {temp}°', 'Allein losfahren oder dich einer Gruppe anschließen'],
  ['Wetterfenster offen', '{temp}° draußen. Die nächsten Stunden gehören der Straße'],
  ['Kurze Runde gefällig?', '{temp}°, dreißig Kilometer und du bist wieder daheim'],
  ['Heute nicht die Autobahn', '{temp}° draußen. Die kurvige Strecke kostet kaum mehr Zeit'],
  ['Beste Zeit am Tag', '{temp}° und am späten Nachmittag ist am wenigsten los'],
  ['Kurvenjagd am Nachmittag', '{temp}° draußen. Wir bauen dir die kurvigste Runde der Gegend'],
  ['Fahr eine Runde für dich', '{temp}°, ohne Ziel, nur wegen der Strecke'],
  ['Handy weg, Lenkrad her', '{temp}° draußen. Zwei Stunden nur du und die Straße'],
  ['Der Tag hat noch Luft', '{temp}°, eine Runde geht sich vor dem Abendessen aus'],
  ['Passstraßen bei {temp}°', 'Hol dir die Route in die App und fahr sie heute noch'],
];

const WETTER_WARM: string[][] = [
  ['Warme {temp}° draußen', 'Fahr in die Höhe, oben ist es angenehmer. Route in der App'],
  ['Hitze mag Höhe', '{temp}° im Tal. Such dir eine Bergstrecke, oben ist es kühler'],
  ['Abends wird es angenehm', '{temp}° jetzt. Plane deine Runde für die Zeit nach sechs'],
  ['{temp}° und freie Bahn', 'Schattige Waldstraßen findest du in der App'],
  ['Sommerabend nutzen', '{temp}° draußen. Die schönste Zeit für eine Runde kommt erst'],
  ['Cabrio oder Helm?', '{temp}° draußen. Beides geht heute, such dir die Strecke aus'],
  ['Heiß, aber fahrbar', '{temp}° im Schatten. Nimm Wasser mit und fahr eine ruhige Runde'],
  ['{temp}° am Nachmittag', 'Der See ist nicht weit. Wir bauen dir die kurvige Anfahrt'],
  ['Ab in die Berge', '{temp}° unten, oben deutlich frischer. Deine Route wartet hier'],
  ['Warme Straßen, guter Grip', '{temp}° draußen. Beste Bedingungen für eine entspannte Runde'],
  ['Sonne satt bei {temp}°', 'Such dir eine Runde durch den Wald und bleib im Schatten'],
  ['Der Tag ist noch lang', '{temp}° draußen. Bis zum Sonnenuntergang gehen zwei Stunden'],
  ['Trinken nicht vergessen', '{temp}° draußen. Dann steht der Ausfahrt nichts im Weg'],
  ['{temp}° und Fernsicht', 'Perfekt für eine Passstraße mit Aussicht. Route in der App'],
  ['Sommerrunde planen', '{temp}° jetzt. Wähle die Länge, wir suchen die Schattenseiten'],
  ['Raus, solange es hell ist', '{temp}° draußen. Eine kurze Runde geht immer'],
];

const WETTER_KUEHL: string[][] = [
  ['{temp}° und klare Sicht', 'Jacke an, Straßen sind frei. Deine Runde wartet in der App'],
  ['Kühl, aber fahrbar', '{temp}° draußen. Mit der richtigen Jacke ein guter Tag zum Fahren'],
  ['Frische Luft, freie Straßen', '{temp}° draußen. Um diese Zeit ist kaum jemand unterwegs'],
  ['Kurven ohne Sommerverkehr', '{temp}°, jetzt gehören die Bergstraßen dir allein'],
  ['Jetzt oder morgen früh', 'Warm anziehen, {temp}° und eine kurze Runde lohnen sich'],
  ['Die Sicht ist heute weit', '{temp}° draußen. Bei kühler Luft siehst du bis zum Horizont'],
  ['Kurze Runde reicht', '{temp}° draußen. Vierzig Kilometer und du bist wieder im Warmen'],
  ['Sitzheizung und Kurven', '{temp}° draußen. Genau dafür wurde sie eingebaut'],
  ['Vorsicht in den Kurven', '{temp}° draußen. Kalter Asphalt braucht etwas mehr Gefühl'],
  ['{temp}° und trotzdem Zeit', 'Für eine kurze Ausfahrt reicht der Nachmittag locker'],
  ['Leere Straßen im Herbst', '{temp}° draußen. Die schönen Strecken hast du fast für dich'],
  ['Der Motor will warm werden', '{temp}° draußen. Fahr eine Runde, bevor es dunkel wird'],
  ['Noch zwei Stunden hell', '{temp}° draußen. Das reicht für eine Runde über Land'],
  ['Handschuhe und Kurven', '{temp}° draußen. Route holen und die Kurven mitnehmen'],
  ['Kein Regen gemeldet', '{temp}° draußen. Das Fenster für eine Runde steht offen'],
  ['Fahren geht immer', '{temp}° draußen. Kurz raus, dann schmeckt der Kaffee besser'],
];

const WETTER_OHNE_WERT: string[][] = [
  ['Zeit für eine Runde', 'Die Bedingungen passen heute. Such dir eine kurvige Strecke'],
  ['Der Nachmittag ist frei', 'Gutes Wetter, freie Straßen. Deine Route wartet in der App'],
  ['Kurven warten auf dich', 'Sag uns wie weit du willst, wir bauen die Strecke'],
  ['Feierabend, Motor an', 'Eine Stunde Kurven und du bist rechtzeitig zurück'],
  ['Heute passt es', 'Wetter gut, Straßen frei. Fahr eine Runde für dich'],
  ['Ab nach draußen', 'Eine kurze Runde reicht schon zum Abschalten'],
  ['Route steht bereit', 'Zwei Klicks in der App und du fährst los'],
  ['Kurven statt Sofa', 'Wähle deine Länge, den Rest übernehmen wir'],
  ['Ruhige Zeit auf der Straße', 'Am späten Nachmittag ist am wenigsten los'],
  ['Fahr die schöne Strecke', 'Die kurvige Route dauert kaum länger als die Autobahn'],
  ['Noch reicht das Licht', 'Für eine Runde über Land ist genug Tag übrig'],
  ['Der Tag ist nicht vorbei', 'Eine Runde geht sich vor dem Abendessen aus'],
];

// Spiegel von WetterPushTexte.streuwert.
function wetterStreuwert(text: string): number {
  let h = 0;
  for (let i = 0; i < text.length; i++) {
    h = (h * 31 + text.charCodeAt(i)) % 1000003;
  }
  return h;
}

// Spiegel von WetterPushTexte.tagesnummer.
function wetterTagesnummer(erstelltAm: string | null | undefined): number {
  const ms = erstelltAm ? Date.parse(erstelltAm) : Number.NaN;
  return Math.floor((Number.isNaN(ms) ? Date.now() : ms) / 86400000);
}

// Spiegel von WetterPushTexte.poolFuer — Bandgrenzen zeichengleich.
function wetterPool(temperaturC: number | null): string[][] {
  if (temperaturC === null) return WETTER_OHNE_WERT;
  if (temperaturC >= 27) return WETTER_WARM;
  if (temperaturC < 13) return WETTER_KUEHL;
  return WETTER_MILD;
}

// Spiegel von WetterPushTexte.temperaturText. Math.round rundet die halbe
// negative Zahl anders als Dart (-2.5 → -2 statt -3), deshalb ueber den
// Betrag runden. Minusgrade werden ausgeschrieben, weil ein Minuszeichen
// auf dem Bildschirm ein Strich waere.
function wetterTemperaturText(temperaturC: number): string {
  const gerundet =
    temperaturC < 0 ? -Math.round(-temperaturC) : Math.round(temperaturC);
  return gerundet < 0 ? `minus ${-gerundet}` : String(gerundet);
}

// Spiegel von WetterPushTexte.fuer.
function wetterTexte(
  userId: string,
  erstelltAm: string | null | undefined,
  temperaturC: number | null,
): { title: string; body: string } {
  const pool = wetterPool(temperaturC);
  const index =
    (wetterTagesnummer(erstelltAm) + wetterStreuwert(userId)) % pool.length;
  const paar = pool[index];
  if (temperaturC === null) return { title: paar[0], body: paar[1] };
  const grad = wetterTemperaturText(temperaturC);
  return {
    title: paar[0].split('{temp}').join(grad),
    body: paar[1].split('{temp}').join(grad),
  };
}

// ── Text-Rendering (Spiegel von NotificationService.renderTexts) ────────────

function renderPush(
  record: NotificationRecord,
  fromUsername: string | null,
): { title: string; body: string } {
  const name = fromUsername ?? 'Jemand';
  const payload = (record.payload ?? {}) as Record<string, unknown>;
  const agg = Number(record.aggregate_count ?? 1);

  switch (record.type) {
    case 'follow':
      return { title: 'Neuer Follower', body: `${name} folgt dir jetzt` };
    case 'like':
      return agg > 1
        ? {
            title: `${agg} neue Likes`,
            body: `${name} und ${agg - 1} weitere mögen deinen Post`,
          }
        : { title: 'Neuer Like', body: `${name} gefällt dein Post` };
    case 'comment':
      return { title: 'Neuer Kommentar', body: `${name} hat kommentiert` };
    case 'friend_request':
      return {
        title: 'Freundschaftsanfrage',
        body: `${name} möchte mit dir cruisen`,
      };
    case 'group_invite':
      return {
        title: 'Einladung zur Gruppe',
        body: `${name} lädt dich zu ${
          (payload.group_name as string) ?? 'einer Gruppe'
        } ein`,
      };
    case 'group_ride_started':
      return {
        title: 'Die Gruppe fährt los',
        body: `${name} fährt jetzt los, schließ dich an`,
      };
    case 'group_public_created':
      return {
        title: 'Neue Gruppe',
        body: `${name} hat eine öffentliche Gruppe erstellt`,
      };
    case 'group_joined':
      return { title: 'Neues Gruppenmitglied', body: `${name} ist beigetreten` };
    case 'repost':
      return { title: 'Repost', body: `${name} hat deinen Post geteilt` };
    case 'weather_recommendation': {
      const t = payload.temperature_c;
      return wetterTexte(
        record.user_id,
        record.created_at,
        typeof t === 'number' ? t : null,
      );
    }
    case 'trip_reminder':
      return {
        title: 'Trip wartet',
        body: 'Dein gestarteter Trip wartet auf Fortsetzung',
      };
    // 2026-08-28 (Fehler 6): Beitraege von Leuten, denen man folgt.
    case 'feed_post': {
      const preview = String(payload.preview ?? '').trim();
      return {
        title: `${name} hat etwas gepostet`,
        body: preview.length > 0 ? preview : 'Schau dir den neuen Beitrag an',
      };
    }
    // 2026-08-28 (Fehler 6): Community-Chat. Titel ist die Community, der
    // Text traegt Absender und Vorschau; gebuendelte Zeilen zaehlen mit.
    case 'community_message': {
      const cname = String(payload.community_name ?? 'Community');
      const preview = String(payload.preview ?? '').trim();
      return agg > 1
        ? {
            title: cname,
            body: `${agg} neue Nachrichten, zuletzt: ${preview}`,
          }
        : { title: cname, body: `${name}: ${preview}` };
    }
    // 2026-08-07 (vucko Monitoring-Zugangsschutz): Der Alarm bringt seinen
    // Text selbst mit — er beschreibt einen Vorfall, nicht eine soziale
    // Aktion, und passt in kein Muster der Faelle darueber.
    case 'monitor_alarm':
      return {
        title: String(payload.title ?? 'Monitoring: unberechtigter Zugriff'),
        body: String(payload.body ?? 'Jemand hat versucht, das Dashboard zu oeffnen.'),
      };
    default:
      return { title: 'Benachrichtigung', body: name };
  }
}

// Notification-Typ -> Einstellungs-Kategorie (Spiegel von
// NotificationSettingsService._categoryForType im Client). null = immer senden
// (z. B. trip_reminder). Fehlt der Schlüssel in den Prefs / Spalte leer =
// aktiviert (Opt-out-Modell: alles an, bis der Nutzer abschaltet).
function categoryForType(type: string): string | null {
  switch (type) {
    case 'follow':
      return 'follows';
    case 'like':
      return 'likes';
    case 'repost':
      return 'reposts';
    case 'comment':
      return 'comments';
    case 'friend_request':
      return 'friend_requests';
    case 'group_invite':
    case 'group_joined':
    case 'group_public_created':
    case 'group_ride_started':
      return 'group_invites';
    case 'weather_recommendation':
      return 'daily_weather';
    // 2026-08-28 (Fehler 6): zwei neue Kategorien, Schluessel identisch mit
    // NotificationSettingsService im Client.
    case 'feed_post':
      return 'feed_posts';
    case 'community_message':
      return 'community_chat';
    default:
      return null;
  }
}

function json(obj: unknown, status: number): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

serve(async (req) => {
  try {
    if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false },
    });

    // 1. Auth: x-push-secret gegen den Vault prüfen (eine Source-of-Truth, die
    //    auch der DB-Trigger nutzt) — via RPC verify_push_webhook_secret, das
    //    Secret verlässt die DB nicht. So kann es nie ein Function-Env/Vault-
    //    Mismatch geben. Fallback auf PUSH_WEBHOOK_SECRET, falls die RPC fehlt.
    const secret = req.headers.get('x-push-secret') ?? '';
    let authorized = false;
    if (secret) {
      try {
        const { data: ok, error: authErr } = await supa.rpc(
          'verify_push_webhook_secret',
          { candidate: secret },
        );
        if (!authErr && ok === true) authorized = true;
      } catch (_) {
        // Vault-RPC nicht verfügbar → Env-Fallback unten.
      }
      if (!authorized && PUSH_WEBHOOK_SECRET && secret === PUSH_WEBHOOK_SECRET) {
        authorized = true;
      }
    }
    if (!authorized) {
      return json({ error: 'unauthorized' }, 401);
    }

    // 2. Record lesen (pg_net schickt { record: {...} }).
    const incoming = await req.json().catch(() => ({}));
    const record: NotificationRecord = incoming?.record ?? incoming;
    if (!record?.user_id || !record?.type) {
      return json({ error: 'invalid_record' }, 400);
    }

    if (!FCM_SERVICE_ACCOUNT) {
      console.warn('[send-push] FCM_SERVICE_ACCOUNT not set — push skipped');
      return json({ skipped: 'no_service_account' }, 200);
    }

    // 2b. Opt-out prüfen: hat der Empfänger diese Kategorie abgeschaltet?
    //     profiles.notification_preferences (jsonb) — fehlt der Schlüssel oder
    //     ist die Spalte leer, gilt „aktiviert". Die In-App-Notification-Zeile
    //     bleibt erhalten; nur der OS-Push wird unterdrückt.
    const prefCategory = categoryForType(record.type);
    if (prefCategory) {
      const { data: prefRow } = await supa
        .from('profiles')
        .select('notification_preferences')
        .eq('id', record.user_id)
        .maybeSingle();
      const prefs = (prefRow?.notification_preferences ?? {}) as Record<
        string,
        unknown
      >;
      if (prefs[prefCategory] === false) {
        return json({ skipped: 'user_disabled', type: record.type }, 200);
      }
    }

    // 3. Device-Tokens des Empfängers.
    const { data: tokenRows, error: tokErr } = await supa
      .from('user_device_tokens')
      .select('token')
      .eq('user_id', record.user_id);
    if (tokErr) console.error('[send-push] token query error', tokErr.message);
    if (!tokenRows || tokenRows.length === 0) {
      return json({ skipped: 'no_tokens' }, 200);
    }

    // 4. Absender-Name für den Text.
    let fromUsername: string | null = null;
    if (record.from_user_id) {
      const { data: prof } = await supa
        .from('profiles')
        .select('username')
        .eq('id', record.from_user_id)
        .maybeSingle();
      fromUsername = (prof?.username as string) ?? null;
    }

    const { title, body } = renderPush(record, fromUsername);
    const data: Record<string, string> = {
      type: String(record.type),
      notification_id: String(record.id ?? ''),
      reference_id: String(record.reference_id ?? ''),
      from_user_id: String(record.from_user_id ?? ''),
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    };

    // 5. Access-Token.
    const sa = JSON.parse(FCM_SERVICE_ACCOUNT);
    const projectId = sa.project_id as string;
    const accessToken = await getAccessToken(sa);

    // 6. Zustellen + tote Tokens aufräumen.
    let sent = 0;
    const dead: string[] = [];
    for (const row of tokenRows) {
      try {
        const r = await sendToToken(
          accessToken,
          projectId,
          row.token as string,
          title,
          body,
          data,
        );
        if (r.ok) sent++;
        else if (r.remove) dead.push(row.token as string);
      } catch (e) {
        console.error('[send-push] token send error', e);
      }
    }
    if (dead.length) {
      await supa.from('user_device_tokens').delete().in('token', dead);
    }

    return json({ sent, removed: dead.length, total: tokenRows.length }, 200);
  } catch (e) {
    // Bewusst 200: pg_net feuert fire-and-forget; ein Fehler hier darf keinen
    // Retry-Sturm / Lärm erzeugen. Details landen im Function-Log.
    console.error('[send-push] fatal', e);
    return json({ error: String(e) }, 200);
  }
});
