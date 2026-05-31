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
        title: 'Gruppen-Einladung',
        body: `${name} lädt dich zu ${
          (payload.group_name as string) ?? 'einer Gruppe'
        } ein`,
      };
    case 'group_ride_started':
      return {
        title: 'Gruppen-Ride gestartet',
        body: `${name} fährt jetzt los — schließ dich an`,
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
      const temp = typeof t === 'number' ? Math.round(t) : null;
      const cond = (payload.condition as string) ?? 'gut';
      return {
        title: 'Bestes Cruise-Wetter',
        body:
          temp != null
            ? `${temp}° und ${cond} — Zeit für eine Runde`
            : 'Heute ist es ideal für eine Tour',
      };
    }
    case 'trip_reminder':
      return {
        title: 'Trip wartet',
        body: 'Dein gestarteter Trip wartet auf Fortsetzung',
      };
    default:
      return { title: 'Benachrichtigung', body: name };
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

    // 1. Auth via Shared Secret (der Trigger schickt x-push-secret).
    const secret = req.headers.get('x-push-secret') ?? '';
    if (!PUSH_WEBHOOK_SECRET || secret !== PUSH_WEBHOOK_SECRET) {
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

    const supa = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false },
    });

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
