// Serverseitige Kennzahlen fuer die Abzeichen, die der Client nicht ehrlich
// bilden kann.
//
// 2026-09-01 — Neue Badge-Familie "Laender" (badge_77 bis badge_79) aus der
// Figma-Serie. Vuckos Vorgabe woertlich: "serverseitige Laender-Klassifikation
// verwenden, NICHT den Client entscheiden lassen, siehe CLAUDE.md".
//
// Der Grund steht in CLAUDE.md: Alte App-Fassungen bleiben installiert und
// senden falsche Werte. Eine Zahl, die ein Abzeichen freischaltet, gehoert
// deshalb nicht in ihre Hand.
//
// Die Funktion liest die aufgezeichneten Spuren des ANGEMELDETEN Nutzers und
// zaehlt, in wie vielen verschiedenen Laendern er gefahren ist. Sie
// beantwortet nur diese eine Frage und gibt keine Koordinaten zurueck.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { classifyCountry } from './land_klassifikation.ts';

const KOPFZEILEN = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

function antwort(koerper: unknown, status = 200): Response {
  return new Response(JSON.stringify(koerper), { status, headers: KOPFZEILEN });
}

/// Wie viele Punkte einer Spur hoechstens geprueft werden.
///
/// Eine Fahrt bleibt fast immer im selben Land; die wenigen Grenzfaelle faengt
/// eine Handvoll gleichmaessig verteilter Punkte zuverlaessig ab. Ohne diese
/// Grenze wuerde eine Spur mit 11.000 Punkten die Funktion unnoetig lange
/// beschaeftigen.
const PUNKTE_JE_FAHRT = 12;

Deno.serve(async (anfrage) => {
  if (anfrage.method === 'OPTIONS') {
    return new Response('ok', { headers: KOPFZEILEN });
  }

  const url = Deno.env.get('SUPABASE_URL');
  const dienstSchluessel = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !dienstSchluessel) {
    console.error('[badge-kennzahlen] Umgebung unvollstaendig');
    return antwort({ fehler: 'server_nicht_bereit' }, 503);
  }

  // Wer fragt? Ausschliesslich ueber das mitgeschickte Token, nie ueber einen
  // Wert aus dem Koerper — sonst koennte jeder die Zahlen eines anderen holen.
  const kopf = anfrage.headers.get('Authorization') ?? '';
  const token = kopf.startsWith('Bearer ') ? kopf.slice(7) : '';
  if (!token) return antwort({ fehler: 'nicht_angemeldet' }, 401);

  const admin = createClient(url, dienstSchluessel);
  const { data: nutzer, error: nutzerFehler } = await admin.auth.getUser(token);
  if (nutzerFehler || !nutzer?.user) {
    return antwort({ fehler: 'nicht_angemeldet' }, 401);
  }
  const nutzerId = nutzer.user.id;

  try {
    const { data: zeilen, error } = await admin
      .from('user_drive_sessions')
      .select('track_geometry')
      .eq('user_id', nutzerId)
      .not('track_geometry', 'is', null);
    if (error) {
      console.error('[badge-kennzahlen] Spuren nicht lesbar', error.message);
      return antwort({ fehler: 'serverfehler' }, 500);
    }

    const laender = new Set<string>();
    for (const zeile of zeilen ?? []) {
      const spur = (zeile as { track_geometry: unknown }).track_geometry;
      if (!Array.isArray(spur) || spur.length === 0) continue;
      const schritt = Math.max(1, Math.floor(spur.length / PUNKTE_JE_FAHRT));
      for (let i = 0; i < spur.length; i += schritt) {
        const p = spur[i];
        // Koordinaten sind ueberall [longitude, latitude].
        if (!Array.isArray(p) || p.length < 2) continue;
        const lng = Number(p[0]);
        const lat = Number(p[1]);
        if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
        const land = classifyCountry(lat, lng);
        if (land) laender.add(land);
      }
    }

    return antwort({
      laender: laender.size,
      codes: [...laender].sort(),
      gepruefte_fahrten: (zeilen ?? []).length,
    });
  } catch (e) {
    console.error('[badge-kennzahlen] Unerwarteter Fehler', String(e));
    return antwort({ fehler: 'serverfehler' }, 500);
  }
});
