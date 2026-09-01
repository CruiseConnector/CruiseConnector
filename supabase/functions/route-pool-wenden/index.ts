// Rechnet fuer die Zeilen in `route_pool` aus, ob sie den Fahrer MITTEN AUF
// DER STRASSE wenden lassen, und schreibt das Ergebnis in die Tabelle.
//
// 2026-09-01 (Vucko: „die routen die jetzt im routenpool gespeichert sind und
// genehmigt werden von der app keine wendepunkte mitten auf den strassen
// erlauben"):
//
// Der Pool ist ueber Monate gewachsen, lange bevor es die Wende-Kennzahl gab.
// Keine der rund 2778 Zeilen weiss also, ob sie diesen Fehler enthaelt. Diese
// Funktion holt das nach: sie liest die Zeilen stapelweise, rechnet die
// Kennzahl mit DEMSELBEN Verfahren wie `generate-cruise-route-v2` und schreibt
// `kehrtwenden_count` und `kehrtwenden_mitte` zurueck.
//
// WARUM NICHT IN SQL: Der Algorithmus legt die Strecke auf ein Meterraster um
// und sucht darin mit einem Gitter nach gegenlaeufigen Partnern. In plpgsql
// waere das ein Vielfaches an Code, eine zweite Fassung derselben Rechnung
// (und damit eine neue Auseinanderlauf-Falle) und wuerde die kurze
// Anweisungs-Zeitgrenze der Datenbank reissen. Hier laeuft es in derselben
// Sprache wie das Original.
//
// WARUM NICHT IM CLIENT: Der Client sieht immer nur die eine Strecke, die er
// gerade anzeigt. Er kann sie pruefen (und tut das auch), aber er kann den
// Pool nicht aufraeumen. Eine schlechte Zeile bliebe sonst fuer immer drin und
// wuerde jedem Nutzer einmal angeboten, bevor sie verworfen wird.
//
// ZUGANG: nur mit dem Dienstschluessel. Die Funktion SCHREIBT in den Pool,
// den alle Nutzer lesen — ein angemeldeter Nutzer darf das nicht ausloesen.
//
// Koordinaten sind ueberall [longitude, latitude].

import { createClient } from 'jsr:@supabase/supabase-js@2';

import {
  abschnitteAus,
  kehrtwendenZaehler,
} from '../_gemeinsam/kehrtwenden.ts';

// ─────────────── Die Kennzahl, zeichengleich zur Edge v2 ───────────────────
//
// Diese Konstanten MUESSEN mit denen in
// `supabase/functions/generate-cruise-route-v2/index.ts` und in
// `lib/data/services/kehrtwenden_zaehler.dart` uebereinstimmen. Der Test
// `test/route/kehrtwenden_portierung_test.dart` haelt alle drei zusammen.
// ─────────────── Der Durchlauf ─────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  const dienstSchluessel = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const kopf = req.headers.get('Authorization') ?? '';
  const mitgeschickt = kopf.replace(/^Bearer\s+/i, '').trim();

  // Nur mit Dienstrechten. Diese Funktion SCHREIBT in eine Tabelle, die alle
  // Nutzer lesen — ein angemeldeter Nutzer darf sie nicht ausloesen.
  //
  // Geprueft wird die ROLLE im Token, nicht der Schluesselwert. Ein reiner
  // Wertvergleich haette an den neueren Schluesselformaten (sb_secret_...)
  // vorbeigegriffen, obwohl der Aufrufer Dienstrechte hat.
  const rolleAusToken = (): string => {
    const teile = mitgeschickt.split('.');
    if (teile.length !== 3) return '';
    try {
      const roh = teile[1].replace(/-/g, '+').replace(/_/g, '/');
      const nutzlast = JSON.parse(atob(roh + '='.repeat((4 - roh.length % 4) % 4)));
      return typeof nutzlast?.role === 'string' ? nutzlast.role : '';
    } catch (_) {
      return '';
    }
  };
  const darfSchreiben = mitgeschickt.length > 0 &&
    (mitgeschickt === dienstSchluessel || rolleAusToken() === 'service_role');
  if (!darfSchreiben) {
    return new Response(
      JSON.stringify({ error: 'nur_mit_dienstrechten' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  let stapel = 200;
  let nurMessen = false;
  try {
    const koerper = await req.json();
    if (typeof koerper?.stapel === 'number') {
      stapel = Math.max(1, Math.min(500, Math.round(koerper.stapel)));
    }
    if (koerper?.nur_messen === true) nurMessen = true;
  } catch (_) {
    // Kein Koerper ist in Ordnung — dann gelten die Vorgaben.
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    dienstSchluessel,
    { auth: { persistSession: false } },
  );

  const { data, error } = await db
    .from('route_pool')
    .select('id, geometry')
    .is('kehrtwenden_mitte', null)
    .not('geometry', 'is', null)
    .limit(stapel);

  if (error) {
    return new Response(
      JSON.stringify({ error: 'lesen_fehlgeschlagen', detail: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const zeilen = (data ?? []) as Array<{ id: string; geometry: unknown }>;
  let mitWendeMittendrin = 0;
  let ohneGeometrie = 0;
  let geschrieben = 0;
  const beispiele: Array<{ id: string; mitte: number; laengeM: number }> = [];

  for (const zeile of zeilen) {
    const abschnitte = abschnitteAus(zeile.geometry);
    if (abschnitte.length === 0) {
      ohneGeometrie++;
      // Auch das festhalten, sonst liest die Funktion dieselbe Zeile beim
      // naechsten Durchlauf wieder und kommt nie ans Ende.
      if (!nurMessen) {
        const { error: e } = await db
          .from('route_pool')
          .update({ kehrtwenden_count: 0, kehrtwenden_mitte: 0 })
          .eq('id', zeile.id);
        if (!e) geschrieben++;
      }
      continue;
    }

    let anzahl = 0;
    let mitte = 0;
    let maxLaengeM = 0;
    for (const teil of abschnitte) {
      const b = kehrtwendenZaehler(teil);
      anzahl += b.anzahl;
      mitte += b.anzahlMitte;
      if (b.maxLaengeM > maxLaengeM) maxLaengeM = b.maxLaengeM;
    }

    if (mitte > 0) {
      mitWendeMittendrin++;
      if (beispiele.length < 10) {
        beispiele.push({ id: zeile.id, mitte, laengeM: maxLaengeM });
      }
    }

    if (!nurMessen) {
      const { error: e } = await db
        .from('route_pool')
        .update({ kehrtwenden_count: anzahl, kehrtwenden_mitte: mitte })
        .eq('id', zeile.id);
      if (!e) geschrieben++;
    }
  }

  const { count: offen } = await db
    .from('route_pool')
    .select('id', { count: 'exact', head: true })
    .is('kehrtwenden_mitte', null);

  return new Response(
    JSON.stringify({
      geprueft: zeilen.length,
      mit_wende_mittendrin: mitWendeMittendrin,
      ohne_geometrie: ohneGeometrie,
      geschrieben,
      noch_offen: offen ?? null,
      beispiele,
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
});
