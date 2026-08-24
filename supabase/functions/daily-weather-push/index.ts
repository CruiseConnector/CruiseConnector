// Daily Weather Push — laeuft nachmittags, gestreut ueber ein Zeitfenster.
//
// 2026-08-24 (Vucko): "ich moechte das die taeglichen benachrichtigungen fuer
// eine strecke erst am nachmittag kommen sollen zwischen 13 - 20 uhr und immer
// unterschiedlich sein sollen".
//
// VORHER: pg_cron '0 6 * * *' UTC. Gemessen an 20 Tagen in `notifications`:
// jede einzelne Wetter-Meldung lag zwischen 08:00:03 und 08:01:29 Wiener Zeit,
// am 24.08. waren das 183 Zeilen innerhalb von 53 Sekunden. Eine Rundmail zur
// vollen Stunde, jeden Tag dieselbe Minute.
//
// JETZT:
//   - Der Cron-Job tickt alle 5 Minuten (11-19 UTC, also breiter als noetig).
//     Ob wirklich gesendet wird, entscheidet eine SQL-Schranke in WIENER Zeit
//     (Migration 20260824200000). Damit ist die Sommerzeit erledigt: Postgres
//     kennt die Zeitzonendatenbank, ein fester UTC-Zeitpunkt wuerde zweimal im
//     Jahr aus dem Fenster wandern.
//   - Jeder Nutzer bekommt pro Tag EINEN eigenen Slot im Fenster, aus
//     user_id + Datum gewuerfelt. Morgen ist es eine andere Minute, und zwei
//     Nutzer treffen sich selten. Das fuehlt sich nach Nachricht an, nicht
//     nach Serienbrief.
//   - Nachzuegler-Regel: faellig ist, wessen Slot ERREICHT ODER VORBEI ist.
//     Faellt ein Tick aus, holt der naechste ihn nach; der letzte Tick des
//     Fensters kehrt alles zusammen. So faellt kein Tag aus.
//   - Doppelt geht nicht: die Vorpruefung ist nur der schnelle Weg, die
//     Wahrheit ist ein partieller UNIQUE-Index auf
//     (user_id, Wiener Datum) fuer type='weather_recommendation'.
//     Bis heute gab es den NICHT — deshalb standen im Bestand vier
//     Nutzer-Tage mit zwei bzw. drei Meldungen.
//
// Bei schlechtem Wetter: NICHTS senden (User soll nicht alle 24h Push bekommen).
//
// Trigger:
//   - pg_cron job 'daily_weather_push', '*/5 11-19 * * *' UTC, mit
//     Wiener Schranke in public.wetter_push_ausloesen()
//   - oder manuell: invoke('daily-weather-push')

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const OPEN_METEO_URL = 'https://api.open-meteo.com/v1/forecast';

// ─────────────── Versandfenster: reine Rechenlogik (Anfang) ───────────────
// Alles zwischen diesen beiden Markierungen ist frei von Netz und Datenbank
// und wird von test/services/wetter_versandfenster_rechenprobe.ts zur Laufzeit
// aus DIESER Datei ausgeschnitten und durchgerechnet. Die Markierungen also
// bitte stehen lassen.

/// Alle Nutzer sitzen in AT, CH und DE — eine Zeitzone reicht.
const WIEN = 'Europe/Vienna';

/// Vuckos Vorgabe: ab 13:00, vor 20:00 Wiener Zeit.
const FENSTER_START_MINUTE = 13 * 60;
const FENSTER_ENDE_MINUTE = 20 * 60;

/// Untergrenze fuer das Fensterende, falls der Sonnenuntergang es nach vorne
/// zieht. In DACH geht die Sonne auch am 21.12. erst nach 16:00 unter, diese
/// Schranke greift also nie — sie ist nur der Riegel gegen ein Fenster der
/// Laenge null, wenn OpenMeteo einmal Unsinn liefert.
const FENSTER_MINDESTENDE_MINUTE = 15 * 60;

/// Rasterweite der Slots. 5 Minuten ergibt im vollen Fenster 84 Slots — genug,
/// dass 183 Nutzer sich auf rund zwei pro Tick verteilen.
const SLOT_MINUTEN = 5;

/// Obergrenze pro Lauf. Im Normalbetrieb sind es zwei bis drei Nutzer; die
/// Grenze schuetzt nur den Nachhol-Lauf nach einer Stoerung davor, in die
/// Laufzeitgrenze der Edge Function zu rennen. Der Rest kommt beim naechsten
/// Tick.
const MAX_PRO_LAUF = 60;

/// FNV-1a, 32 Bit. Gebraucht wird nur: gleiche Eingabe -> gleicher Slot,
/// unterschiedliche Eingabe -> gut gestreute Slots. Keine Kryptografie.
function streuHash(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/// Wiener Datum und Minute-seit-Mitternacht zu einem Zeitpunkt.
/// 'sv-SE' liefert "2026-08-24 19:32" — ISO-nah und ohne Monatsnamen.
/// Intl kennt die Zeitzonendatenbank, damit stimmt auch die Sommerzeit.
function wienStempel(jetzt: Date): { datum: string; minute: number } {
  const teile = new Intl.DateTimeFormat('sv-SE', {
    timeZone: WIEN,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(jetzt);
  const [datum, uhrzeit] = teile.split(' ');
  const [stunde, minute] = uhrzeit.split(':').map(Number);
  return { datum, minute: stunde * 60 + minute };
}

/// Wiener Mitternacht des laufenden Tages als ISO-Zeitpunkt MIT Zonenversatz,
/// z.B. "2026-08-24T00:00:00+02:00". PostgREST versteht das direkt.
///
/// Feinheit: in der Umstellungsnacht gilt zur Sendezeit schon der neue
/// Versatz, die echte Mitternacht hatte noch den alten. Das Fenster ist dann
/// um eine Stunde zu weit — unkritisch, weil in dieser Stunde (23-24 Uhr)
/// nie eine Wetter-Meldung entsteht. Der UNIQUE-Index rechnet ohnehin exakt.
function wienTagesbeginn(jetzt: Date): string {
  const { datum } = wienStempel(jetzt);
  const versatz = new Intl.DateTimeFormat('en-US', {
    timeZone: WIEN,
    timeZoneName: 'longOffset',
  }).format(jetzt).match(/GMT([+-]\d{2}:\d{2})/);
  return `${datum}T00:00:00${versatz ? versatz[1] : '+00:00'}`;
}

/// Sonnenuntergang aus der OpenMeteo-Tagesantwort, als Minute-seit-Mitternacht
/// Wiener Zeit. null, wenn die Antwort das Feld nicht hat.
function sonnenuntergangMinute(json: unknown): number | null {
  const d = (json as { daily?: { sunset?: unknown[] } })?.daily;
  const roh = Array.isArray(d?.sunset) ? d!.sunset![0] : null;
  if (typeof roh !== 'string') return null;
  const t = roh.match(/T(\d{2}):(\d{2})/);
  if (!t) return null;
  return Number(t[1]) * 60 + Number(t[2]);
}

/// Ende des Versandfensters. Vuckos 20:00 bleibt die Vorgabe, aber nie nach
/// Sonnenuntergang: eine Meldung "raus auf die Strecke" um 19:55 im November
/// erreicht jemanden, bei dem es seit drei Stunden dunkel ist.
/// Im Sommer aendert die Regel nichts (Sonnenuntergang nach 20:00).
function fensterEndeMinute(sonnenuntergang: number | null): number {
  if (sonnenuntergang === null) return FENSTER_ENDE_MINUTE;
  const ende = Math.min(FENSTER_ENDE_MINUTE, sonnenuntergang);
  return Math.max(FENSTER_MINDESTENDE_MINUTE, ende);
}

/// Der persoenliche Slot eines Nutzers an einem Tag, als Minute-seit-
/// Mitternacht Wiener Zeit. Aendert sich taeglich, weil das Datum in den
/// Hash eingeht.
function slotMinute(userId: string, datum: string, endeMinute: number): number {
  const slots = Math.max(
    1,
    Math.floor((endeMinute - FENSTER_START_MINUTE) / SLOT_MINUTEN),
  );
  const slot = streuHash(`${userId}:${datum}`) % slots;
  return FENSTER_START_MINUTE + slot * SLOT_MINUTEN;
}

/// Ist der Nutzer jetzt dran? "Slot erreicht ODER vorbei" — nicht "Slot
/// gleich jetzt". Genau dieses <= ist die Nachzuegler-Regel: ein
/// ausgefallener oder verspaeteter Tick kostet keinen Tag, weil der naechste
/// Tick alles Liegengebliebene mitnimmt. Gegen Doppeltes schuetzt nicht
/// dieser Vergleich, sondern die Tagespruefung plus der UNIQUE-Index.
function istFaellig(
  userId: string,
  datum: string,
  jetztMinute: number,
  endeMinute: number,
): boolean {
  if (jetztMinute < FENSTER_START_MINUTE) return false;
  if (jetztMinute >= FENSTER_ENDE_MINUTE) return false;
  if (jetztMinute >= endeMinute) return false;
  return slotMinute(userId, datum, endeMinute) <= jetztMinute;
}

// ─────────────── Versandfenster: reine Rechenlogik (Ende) ─────────────────

interface WeatherCheck {
  ok: boolean;
  condition: string;
  tempC: number;
  weatherCode: number;
  rainMm: number;
  windKmh: number;
}

async function checkWeather(lat: number, lng: number): Promise<WeatherCheck | null> {
  try {
    const url =
      `${OPEN_METEO_URL}?latitude=${lat.toFixed(4)}&longitude=${lng.toFixed(4)}` +
      `&current=temperature_2m,weather_code,precipitation,wind_speed_10m` +
      `&hourly=precipitation_probability,weather_code&forecast_hours=6&timezone=auto`;
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = await res.json();
    const cur = data.current ?? {};
    const tempC = Number(cur.temperature_2m ?? 0);
    const weatherCode = Number(cur.weather_code ?? 0);
    const rainMm = Number(cur.precipitation ?? 0);
    const windKmh = Number(cur.wind_speed_10m ?? 0);
    // Riding-Conditions:
    // poor: regen >4mm, wind >40km/h, temp <0
    // marginal: regen >0.5mm, wind >25km/h, temp <5
    // excellent: trocken, 12-28°, wind <15
    // good: alles dazwischen
    let condition = 'good';
    if (rainMm > 4 || windKmh > 40 || tempC < 0) condition = 'poor';
    else if (rainMm > 0.5 || windKmh > 25 || tempC < 5) condition = 'marginal';
    else if (rainMm === 0 && tempC >= 12 && tempC <= 28 && windKmh < 15) {
      condition = 'excellent';
    }
    // 6h-Forecast: wenn in den nächsten 6h Regen-Prob >50% → marginal
    const probs: number[] = data.hourly?.precipitation_probability ?? [];
    const maxProb = probs.length ? Math.max(...probs.slice(0, 6)) : 0;
    if (maxProb >= 50 && condition === 'excellent') condition = 'good';
    if (maxProb >= 70 && condition === 'good') condition = 'marginal';
    // Push nur bei good oder excellent
    const ok = condition === 'good' || condition === 'excellent';
    return { ok, condition, tempC, weatherCode, rainMm, windKmh };
  } catch {
    return null;
  }
}

/// Sonnenuntergang fuer die Heimatregion (Vorarlberg). Einer fuer alle: ueber
/// AT, CH und DE schwankt er um rund eine halbe Stunde, das Fenster ist sieben
/// Stunden lang. Ein Aufruf pro Tick statt einer pro Nutzer — und vor allem
/// EIN Fensterende fuer alle, sonst wuerden die Slots je Nutzer auf
/// verschiedene Raster fallen.
async function holeSonnenuntergangMinute(): Promise<number | null> {
  try {
    const url =
      `${OPEN_METEO_URL}?latitude=47.5031&longitude=9.7471` +
      `&daily=sunset&forecast_days=1&timezone=${encodeURIComponent(WIEN)}`;
    const res = await fetch(url);
    if (!res.ok) return null;
    return sonnenuntergangMinute(await res.json());
  } catch {
    return null;
  }
}

function conditionLabel(condition: string): string {
  switch (condition) {
    case 'excellent': return 'perfekt';
    case 'good': return 'gut';
    default: return 'OK';
  }
}

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  const jetzt = new Date();
  const { datum: heute, minute: jetztMinute } = wienStempel(jetzt);
  const tagesbeginn = wienTagesbeginn(jetzt);
  let sent = 0;
  let skipped = 0;
  let failed = 0;
  let ausserhalb = 0;
  let nochNichtDran = 0;
  try {
    // 0. Fensterende bestimmen (20:00, aber nie nach Sonnenuntergang).
    const endeMinute = fensterEndeMinute(await holeSonnenuntergangMinute());

    // Frueher Ausstieg, wenn der Tick ausserhalb liegt. Die SQL-Schranke im
    // Cron-Job faengt das normalerweise schon ab; hier steht der Riegel fuer
    // den Fall, dass jemand die Funktion von Hand aufruft.
    if (jetztMinute < FENSTER_START_MINUTE || jetztMinute >= endeMinute) {
      return new Response(
        JSON.stringify({
          sent: 0, skipped: 0, failed: 0,
          grund: 'ausserhalb des Versandfensters',
          wiener_minute: jetztMinute,
          fenster: [FENSTER_START_MINUTE, endeMinute],
        }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }

    // 1. Profile (mit letzter bekannter Position falls vorhanden)
    const { data: users, error: usersErr } = await supabase
      .from('profiles')
      .select('id, last_known_lat, last_known_lng')
      .limit(5000);
    if (usersErr) throw usersErr;
    if (!users) {
      return new Response(JSON.stringify({ error: 'no users' }), { status: 500 });
    }

    for (const u of users) {
      const userId = u.id as string;

      // 2. Ist dieser Nutzer in diesem Tick dran?
      if (!istFaellig(userId, heute, jetztMinute, endeMinute)) {
        nochNichtDran++;
        continue;
      }
      if (sent >= MAX_PRO_LAUF) {
        ausserhalb++;
        continue;
      }

      // 3. Vorpruefung: heute schon eine Wetter-Meldung? Gerechnet wird ab
      // WIENER Mitternacht. Vorher stand hier UTC-Mitternacht — genau daran
      // ist die Idempotenz am 24.05. gescheitert: ein Lauf um 01:03 Wiener
      // Zeit lag in UTC noch im Vortag, der Lauf um 08:01 sah ihn nicht.
      const { data: existing } = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('type', 'weather_recommendation')
        .gte('created_at', tagesbeginn)
        .limit(1);
      if (existing && existing.length > 0) {
        skipped++;
        continue;
      }

      // 4. Position: zuerst aus profile, dann aus session, dann Fallback
      let lat: number | null = null;
      let lng: number | null = null;
      const profileLat = (u as { last_known_lat?: number | null }).last_known_lat;
      const profileLng = (u as { last_known_lng?: number | null }).last_known_lng;
      if (profileLat != null && profileLng != null) {
        lat = Number(profileLat);
        lng = Number(profileLng);
      }
      if (lat === null || lng === null) {
        const { data: lastSession } = await supabase
          .from('route_search_sessions')
          .select('origin_lat, origin_lng')
          .eq('user_id', userId)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (lastSession?.origin_lat && lastSession?.origin_lng) {
          lat = Number(lastSession.origin_lat);
          lng = Number(lastSession.origin_lng);
        }
      }
      // Fallback: pool_demand_log
      if (lat === null || lng === null) {
        const { data: lastDemand } = await supabase
          .from('pool_demand_log')
          .select('search_lat, search_lng')
          .eq('user_id', userId)
          .order('logged_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (lastDemand?.search_lat && lastDemand?.search_lng) {
          lat = Number(lastDemand.search_lat);
          lng = Number(lastDemand.search_lng);
        }
      }
      // Fallback: Vorarlberg (CruiseConnect-Heimatregion).
      // So bekommen alle User wenigstens etwas relevant-nahes,
      // bis profiles.last_known_lat/lng geschrieben wird.
      if (lat === null || lng === null) {
        lat = 47.5031;
        lng = 9.7471;
      }

      // 5. Wetter checken
      const wx = await checkWeather(lat, lng);
      if (!wx || !wx.ok) {
        skipped++;
        continue;
      }

      // 6. Notification erstellen (self-from_user_id = system marker)
      const { error: insErr } = await supabase.from('notifications').insert({
        user_id: userId,
        from_user_id: userId, // system uses self as from
        type: 'weather_recommendation',
        read: false,
        payload: {
          condition: conditionLabel(wx.condition),
          temperature_c: wx.tempC,
          weather_code: wx.weatherCode,
          wind_kmh: wx.windKmh,
          lat,
          lng,
          // Wann die Meldung ENTSTANDEN ist, in Wiener Stunden. Der Text in
          // der App richtet sich bisher nach der Uhrzeit des OEFFNENS — wer
          // die Nachmittagsmeldung erst am naechsten Morgen antippt, liest
          // einen Morgentext. Mit diesem Feld kann die Textseite auf die
          // Sendezeit umstellen.
          stunde_lokal: Math.floor(jetztMinute / 60),
        },
      });
      if (insErr) {
        // 23505 = UNIQUE verletzt. Das ist kein Fehler, sondern genau der
        // Schutz, den die Vorpruefung allein nicht leisten kann: zwei
        // gleichzeitige Laeufe lesen beide "noch nichts da" und schreiben
        // beide. Der Index laesst nur den ersten durch.
        if ((insErr as { code?: string }).code === '23505') {
          skipped++;
          continue;
        }
        failed++;
        continue;
      }
      sent++;
    }

    return new Response(
      JSON.stringify({
        sent, skipped, failed,
        noch_nicht_dran: nochNichtDran,
        vertagt: ausserhalb,
        total: users.length,
        wiener_minute: jetztMinute,
        fenster_ende: endeMinute,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e), sent, skipped, failed }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
