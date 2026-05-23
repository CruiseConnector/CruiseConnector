// Daily Weather Push — läuft täglich morgens via pg_cron.
//
// Pro aktivem User:
//   1. Letzte bekannte Position ermitteln (drive_sessions oder
//      saved_routes Anfang)
//   2. OpenMeteo aktuelles Wetter + 6h-Forecast checken
//   3. Wenn Riding-Condition ≥ "good" → notification mit
//      type='weather_recommendation' erzeugen
//
// Idempotenz: pro user_id + Datum nur EINE Weather-Notification (UNIQUE).
// Bei schlechtem Wetter: NICHTS senden (User soll nicht alle 24h Push bekommen).
//
// Trigger:
//   - pg_cron job '0 7 * * *' UTC (~08:00 lokal Sommer, ~09:00 Winter)
//   - oder manuell: invoke('daily-weather-push')

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const OPEN_METEO_URL = 'https://api.open-meteo.com/v1/forecast';

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

function conditionLabel(condition: string): string {
  switch (condition) {
    case 'excellent': return 'perfekt';
    case 'good': return 'gut';
    default: return 'OK';
  }
}

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  let sent = 0;
  let skipped = 0;
  let failed = 0;
  try {
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

      // 2. Check ob heute schon Weather-Notification an User
      const { data: existing } = await supabase
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('type', 'weather_recommendation')
        .gte('created_at', `${today}T00:00:00Z`)
        .limit(1);
      if (existing && existing.length > 0) {
        skipped++;
        continue;
      }

      // 3. Position: zuerst aus profile, dann aus session, dann Fallback
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

      // 4. Wetter checken
      const wx = await checkWeather(lat, lng);
      if (!wx || !wx.ok) {
        skipped++;
        continue;
      }

      // 5. Notification erstellen (self-from_user_id = system marker)
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
        },
      });
      if (insErr) {
        failed++;
        continue;
      }
      sent++;
    }

    return new Response(
      JSON.stringify({ sent, skipped, failed, total: users.length }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e), sent, skipped, failed }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
