-- ============================================================================
-- 2026-08-24 — Zwei Zahlen fuer die neuen Abzeichen badge_59 … badge_70
-- ============================================================================
--
-- ANLASS: In der Nacht auf den 24.08. sind zwoelf Abzeichen angelegt worden
-- (Garage 1/3/5, Beitraege 1/5/20, Hashtags 1/5/20, Meldungen 1/5/20). Zwei
-- der vier Familien hatten keine Zahl, aus der sie freigeschaltet werden
-- koennen — sie standen dauerhaft gesperrt in der Sammlung.
--
-- WARUM DAS SERVERSEITIG GEHOERT (gemessen am 24.08.):
--
--   1. MELDUNGEN. Die Sichtbarkeitsregel `ri_select` auf `road_incidents`
--      lautet
--          active AND expires_at > now()
--          AND (visibility = 'public' OR reported_by = auth.uid())
--      Eine Meldung hat eine LEBENSDAUER (Migration 20260820175500). Ein
--      normales SELECT des Clients sieht deshalb nur die gerade noch
--      gueltigen Meldungen, nicht die abgesetzten. GEMESSEN: die aktivste
--      meldende Person hat 7 Meldungen abgesetzt, sichtbar sind davon 2.
--      Ueber den Client waere „Setze zwanzig Meldungen ab" praktisch nie
--      erreichbar gewesen — man muesste zwanzig Meldungen GLEICHZEITIG
--      gueltig halten. Die Zeilen bleiben liegen (es gibt keinen Loesch-Job,
--      nur `active`/`expires_at`), also kann die Zahl serverseitig ehrlich
--      gezaehlt werden.
--
--   2. HASHTAGS. Die Familie zaehlt BEITRAEGE mit Raute, nicht Rauten.
--      `post_hashtags` hat eine Zeile je (Beitrag, Hashtag) — ein Beitrag mit
--      fuenf Rauten wuerde clientseitig fuenfmal zaehlen und Stufe 5 nach
--      einem einzigen Beitrag freischalten. `count(distinct post_id)` gehoert
--      deshalb in die Datenbank, wo das „distinct" nichts kostet.
--
-- EINE Funktion fuer BEIDE Zahlen, mit Absicht: `calculateAndSync` laeuft bei
-- jedem Start der Startseite. Zwei getrennte RPCs waeren zwei Wartetakte; so
-- ist es einer, und der laeuft neben den bestehenden Zaehlern.
--
-- Das Abzeichen selbst wird hier NICHT vergeben — dieselbe Begruendung wie bei
-- `meine_community_gruendung` (Migration 20260824103000): eine Badge-ID in SQL
-- waere eine zweite Liste neben `badgeFamilien`, und genau diese Fehlerklasse
-- hat die Migration vom 18.08. abgeschafft. Die Datenbank liefert die Wahrheit,
-- der Client vergibt.
-- ============================================================================

create or replace function public.meine_badge_kennzahlen()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    -- Beitraege MIT mindestens einer Raute, nicht Rauten.
    'hashtag_beitraege', (
      select count(distinct ph.post_id)
        from public.post_hashtags ph
        join public.posts p on p.id = ph.post_id
       where p.user_id = (select auth.uid())
    ),
    -- Alle je abgesetzten Meldungen, unabhaengig von Lebensdauer und
    -- `active`. Zurueckgezogene zaehlen NICHT mit: wer eine Meldung selbst
    -- widerruft, hat sie nicht abgesetzt — und ohne diese Bedingung waere
    -- „zwanzig Meldungen" mit zwanzig Widerrufen zu haben.
    'meldungen', (
      select count(*)
        from public.road_incidents ri
       where ri.reported_by = (select auth.uid())
         and ri.retracted_at is null
    )
  );
$function$;

comment on function public.meine_badge_kennzahlen() is
  '2026-08-24: Zwei Zahlen des angemeldeten Nutzers fuer die Abzeichen '
  'badge_65..badge_70 — Beitraege mit Hashtag und abgesetzte Meldungen. '
  'SECURITY DEFINER, weil die Sichtbarkeitsregel von road_incidents '
  'abgelaufene Meldungen ausblendet; die Funktion liest ausschliesslich '
  'Zeilen des Aufrufers und gibt nichts preis, was ihm nicht gehoert. '
  'Ohne Anmeldung sind beide Zahlen 0.';

-- Ohne Anmeldung gibt es hier nichts zu holen.
revoke execute on function public.meine_badge_kennzahlen() from public;
revoke execute on function public.meine_badge_kennzahlen() from anon;
grant  execute on function public.meine_badge_kennzahlen() to authenticated;

-- Kein neuer Index noetig, beide Wege sind gedeckt:
--   * road_incidents_reporter_time_idx (reported_by, created_at desc)
--   * post_hashtags_pkey (post_id, tag_schluessel) + idx_posts_user_id
