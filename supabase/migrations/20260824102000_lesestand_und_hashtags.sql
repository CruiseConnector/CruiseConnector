-- ============================================================================
-- 2026-08-24  Serverseitiger Lesestand fuer die Hinweispunkte (1.1)
--             und eine eigene Ablage fuer Hashtags (1.3)
-- ============================================================================
--
-- vucko: "Ein Punkt am Community-Einstieg, dann je Reiter, dann je einzelner
-- Community." und "Ich will spaeter Gewinnspiele ueber einen Hashtag
-- auslosen."
--
-- GEMESSENER AUSGANGSZUSTAND (24.08.2026):
--   * Ebene 1 existiert bereits, liegt aber in SharedPreferences
--     (lib/data/services/community_neuigkeit_service.dart) und vergleicht
--     ANZAHLEN. Ein Geraetewechsel setzt sie zurueck, und "wo ist etwas neu"
--     kann ein Zaehler grundsaetzlich nicht beantworten.
--   * Es gibt KEINEN serverseitigen Lesestand. Suche ueber
--     information_schema nach last_read/last_seen/seen_at/viewed lieferte nur
--     notifications.read, route_search_sessions.worker_last_seen_at und
--     user_device_tokens.last_seen_at.
--   * posts 10 Zeilen, davon 0 mit einer Raute. community_messages 19,
--     communities 6, community_members 44, group_messages 0, follows 57,
--     profiles 183.
--   * pg_trgm ist NICHT installiert.
--
-- ============================================================================


-- ============================================================================
-- TEIL 1 - Lesestand
-- ============================================================================
--
-- WARUM EINE EIGENE TABELLE UND NICHT profiles.starter_aufgaben-STIL (jsonb)?
--
-- Das jsonb-Muster auf profiles ist am 19.08. bewusst gewaehlt worden
-- ("keine eigene Tabelle, kein Umbau, ein UPDATE pro Abgleich"). Es passt
-- dort, weil die Starter-Aufgaben acht Mal im LEBEN eines Kontos geschrieben
-- werden. Der Lesestand wird bei JEDEM Reiterwechsel und JEDEM Oeffnen einer
-- Community geschrieben. Das ist eine voellig andere Schreiblast, und drei
-- gemessene Gruende sprechen dagegen:
--
--   1. profiles ist eine breite Zeile: 353 Byte im Schnitt, 58 Spalten.
--      Postgres schreibt bei jedem UPDATE eine KOMPLETTE neue Zeilenversion.
--      Ein Reiterwechsel wuerde also 353 Byte umschreiben, um einen
--      Zeitstempel von 8 Byte zu setzen. Bei vier Reitern plus sechs
--      Communities sind das zehn moegliche Schreibziele pro Sitzung.
--   2. Lesestaende sind pro Bereich UNABHAENGIG. Ein jsonb ist EIN Wert:
--      zwei Geraete, die gleichzeitig zwei verschiedene Reiter oeffnen,
--      ueberschreiben sich gegenseitig (lost update), weil beide das ganze
--      Objekt lesen, aendern und zurueckschreiben. Eine Zeile je Bereich
--      kennt dieses Problem nicht.
--   3. profiles wird von fast jedem Bildschirm gelesen. Jede zusaetzliche
--      Zeilenversion dort blaeht die Tabelle auf und trifft alle Leser.
--
-- Die eigene Tabelle ist winzig: hoechstens (4 Reiter + eigene Communities)
-- Zeilen je Nutzer. Bei 183 Profilen und 6 Communities sind das im
-- schlimmsten Fall rund 1.800 Zeilen von je etwa 60 Byte.

create table if not exists public.community_lesestand (
  user_id        uuid        not null references public.profiles(id) on delete cascade,
  -- 'feed' | 'gruppen' | 'chats' | 'entdecken'  -> ein Reiter
  -- 'community'                                 -> eine einzelne Community
  bereich        text        not null,
  community_id   uuid        references public.communities(id) on delete cascade,
  -- Ersatzspalte fuer den Primaerschluessel: bei den vier Reiter-Zeilen ist
  -- community_id NULL, und NULL ist in einem Schluessel nie gleich NULL. Mit
  -- der Null-UUID wird daraus ein normaler, dreispaltiger Primaerschluessel.
  community_schluessel uuid generated always as
    (coalesce(community_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored,
  gesehen_bis    timestamptz not null default now(),
  aktualisiert_am timestamptz not null default now(),
  constraint community_lesestand_bereich_chk
    check (bereich in ('feed', 'gruppen', 'chats', 'entdecken', 'community')),
  -- community_id gehoert genau dann dazu, wenn es um eine Community geht.
  constraint community_lesestand_zuordnung_chk
    check ((bereich = 'community') = (community_id is not null)),
  constraint community_lesestand_pkey
    primary key (user_id, bereich, community_schluessel)
);

comment on table public.community_lesestand is
  '2026-08-24: Serverseitiger Lesestand je Nutzer und Bereich. Ersetzt den '
  'geraetelokalen Zaehler aus SharedPreferences. Ebene 1 (der Punkt am '
  'Community-Einstieg) wird NICHT gespeichert, sondern aus den Reitern '
  'berechnet - sonst muesste man sie nachpflegen.';

-- Fuer das Aufraeumen beim Loeschen einer Community (on delete cascade).
create index if not exists community_lesestand_community_idx
  on public.community_lesestand (community_id)
  where community_id is not null;

alter table public.community_lesestand enable row level security;

-- Lesen darf jeder nur den eigenen Stand. Geschrieben wird ausschliesslich
-- ueber community_als_gesehen_markieren() - deshalb gibt es hier bewusst
-- KEINE Policy fuer insert/update/delete. Das ist dieselbe Lehre wie beim
-- Meldungs-Missbrauchsschutz vom 26.07.: was der Client direkt schreiben
-- darf, wird frueher oder spaeter manipuliert.
drop policy if exists community_lesestand_select_own on public.community_lesestand;
create policy community_lesestand_select_own
  on public.community_lesestand
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- ACHTUNG, wiederkehrende Falle: Supabase vergibt ueber
-- ALTER DEFAULT PRIVILEGES beim CREATE TABLE automatisch ALLE Rechte an
-- authenticated. Ein "revoke ... from anon, public" trifft das NICHT.
-- INSERT/UPDATE/DELETE wuerde die RLS-Regel noch abfangen, TRUNCATE aber
-- NICHT - das ist ein Tabellenrecht und kennt keine Zeilenregeln. Genau
-- dieser Fehler steht in CLAUDE.md schon bei user_drive_sessions.
revoke all on public.community_lesestand from anon, public;
revoke insert, update, delete, truncate, references, trigger
  on public.community_lesestand from authenticated;
grant select on public.community_lesestand to authenticated;


-- ----------------------------------------------------------------------------
-- Eine einzige Abfrage fuer alle Punkte
-- ----------------------------------------------------------------------------
--
-- vucko: "Wenn jeder Punkt einzeln fragt, sind das zehn Abfragen pro
-- Bildschirmaufbau."
--
-- Rueckgabe:
--   {
--     "punkt": true,                                  -- Ebene 1, BERECHNET
--     "reiter": {
--       "feed":      {"neu": true,  "anzahl": 3},
--       "gruppen":   {"neu": false, "anzahl": 0},
--       "chats":     {"neu": true,  "anzahl": 5},
--       "entdecken": {"neu": false, "anzahl": 0}
--     },
--     "communities": { "<uuid>": {"neu": true, "anzahl": 5} },
--     "stand": "2026-08-24T10:20:00+00:00"
--   }
--
-- Ebene 1 ist bewusst kein eigener Zustand: punkt = feed oder gruppen oder
-- chats oder entdecken. Damit erfuellt sich "sind alle Unterbereiche gelesen,
-- verschwindet auch der Punkt oben" von selbst.
--
-- Der Reiter "Chats" ist zweigeteilt, weil die Oberflaeche es auch ist:
--   * der Mitglieder-Teil ist die ODER-Verknuepfung der einzelnen
--     Community-Punkte (WhatsApp-Verhalten - der Punkt geht erst aus, wenn
--     man die betroffene Community wirklich oeffnet),
--   * der Entdecken-Teil (neue oeffentliche Community zum Beitreten) hat
--     einen eigenen Lesestand und geht aus, sobald man den Reiter oeffnet.
--
-- ZEITFENSTER: Ein Punkt verspricht "es ist gerade etwas passiert". Ein
-- halbes Jahr alter Beitrag ist kein Grund zu leuchten. Deshalb schaut die
-- Funktion hoechstens 30 Tage zurueck. Wer noch nie gelesen hat, bekommt als
-- Startpunkt sein Kontodatum - beim ersten Besuch leuchtet der Punkt also,
-- und genau das ist seit dem 11.08. die gewollte Regel ("genau dann soll
-- jemand die Community ueberhaupt entdecken").
create or replace function public.community_hinweispunkte()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid              uuid := (select auth.uid());
  v_fenster constant interval := interval '30 days';
  v_konto            timestamptz;
  v_b_feed           timestamptz;
  v_b_gruppen        timestamptz;
  v_b_chats          timestamptz;
  v_b_entdecken      timestamptz;
  v_feed             int := 0;
  v_gruppen          int := 0;
  v_entdecken        int := 0;
  v_chats_entdecken  int := 0;
  v_chats_mitglied   int := 0;
  v_chats            int := 0;
  v_communities      jsonb := '{}'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object(
      'punkt', false,
      'reiter', jsonb_build_object(
        'feed',      jsonb_build_object('neu', false, 'anzahl', 0),
        'gruppen',   jsonb_build_object('neu', false, 'anzahl', 0),
        'chats',     jsonb_build_object('neu', false, 'anzahl', 0),
        'entdecken', jsonb_build_object('neu', false, 'anzahl', 0)),
      'communities', '{}'::jsonb,
      'stand', now());
  end if;

  select p.created_at into v_konto from public.profiles p where p.id = v_uid;
  v_konto := coalesce(v_konto, now() - v_fenster);

  select
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'feed'),      v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'gruppen'),   v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'chats'),     v_konto), now() - v_fenster),
    greatest(coalesce(max(l.gesehen_bis) filter (where l.bereich = 'entdecken'), v_konto), now() - v_fenster)
  into v_b_feed, v_b_gruppen, v_b_chats, v_b_entdecken
  from public.community_lesestand l
  where l.user_id = v_uid
    and l.community_id is null;

  -- --- Reiter 0: Feed -------------------------------------------------------
  -- Deckungsgleich mit SocialService.getFeedPosts: oeffentliche Beitraege von
  -- Leuten, denen ich folge, plus "Nur Follower"-Beitraege von Leuten, die
  -- mir zurueckfolgen. Eigene Beitraege zaehlen NICHT - ein Punkt fuer den
  -- eigenen Beitrag waere Unsinn.
  select count(*) into v_feed
  from public.posts p
  where p.created_at > v_b_feed
    and p.user_id <> v_uid
    and coalesce(p.is_hidden, false) = false
    and exists (
      select 1 from public.follows f
      where f.follower_id = v_uid and f.following_id = p.user_id
        and f.status = 'accepted')
    and (
      p.visibility = 'public'
      or (p.visibility = 'followers' and exists (
            select 1 from public.follows g
            where g.follower_id = p.user_id and g.following_id = v_uid
              and g.status = 'accepted')))
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = v_uid and b.blocked_id = p.user_id)
         or (b.blocker_id = p.user_id and b.blocked_id = v_uid));

  -- --- Reiter 1: Gruppen & Fahrten -----------------------------------------
  -- Zwei Quellen: eine neue oeffentliche Gruppe, der ich beitreten koennte
  -- (deckungsgleich mit SocialService.getDiscoverGroups), und eine neue
  -- Nachricht in einer Gruppe, in der ich schon bin.
  select
    (select count(*)
       from public.groups g
      where g.created_at > v_b_gruppen
        and g.is_public
        and g.is_active = false
        and g.closed_at is null
        and g.created_by <> v_uid
        and not exists (select 1 from public.group_members m
                         where m.group_id = g.id and m.user_id = v_uid)
        and not exists (select 1 from public.user_blocks b
                         where (b.blocker_id = v_uid and b.blocked_id = g.created_by)
                            or (b.blocker_id = g.created_by and b.blocked_id = v_uid)))
    +
    (select count(*)
       from public.group_messages gm
       join public.group_members m
         on m.group_id = gm.group_id and m.user_id = v_uid
      where gm.created_at > v_b_gruppen
        and gm.deleted_at is null
        and gm.user_id <> v_uid)
  into v_gruppen;

  -- --- Reiter 2: Chats, Teil A - meine Communities --------------------------
  -- Startpunkt je Community, wenn noch nie gelesen: der Tag des Beitritts.
  -- Alles, was seit dem Beitritt geschrieben wurde, ist fuer mich neu.
  select
    coalesce(jsonb_object_agg(
      t.community_id::text,
      jsonb_build_object('neu', t.anzahl > 0, 'anzahl', t.anzahl)), '{}'::jsonb),
    coalesce(sum(t.anzahl), 0)
  into v_communities, v_chats_mitglied
  from (
    select
      m.community_id,
      least(99, (
        select count(*)
        from public.community_messages cm
        where cm.community_id = m.community_id
          and cm.deleted_at is null
          and cm.user_id <> v_uid
          and cm.created_at > greatest(coalesce(l.gesehen_bis, m.created_at),
                                       now() - v_fenster)
          and not exists (
            select 1 from public.user_blocks b
            where (b.blocker_id = v_uid and b.blocked_id = cm.user_id)
               or (b.blocker_id = cm.user_id and b.blocked_id = v_uid))
      ))::int as anzahl
    from public.community_members m
    left join public.community_lesestand l
      on l.user_id = v_uid
     and l.bereich = 'community'
     and l.community_id = m.community_id
    where m.user_id = v_uid
  ) t;

  -- --- Reiter 2: Chats, Teil B - neue oeffentliche Communities --------------
  select count(*) into v_chats_entdecken
  from public.communities c
  where c.created_at > v_b_chats
    and c.is_public
    and c.owner_id <> v_uid
    and not exists (select 1 from public.community_members m
                     where m.community_id = c.id and m.user_id = v_uid)
    and not exists (select 1 from public.user_blocks b
                     where (b.blocker_id = v_uid and b.blocked_id = c.owner_id)
                        or (b.blocker_id = c.owner_id and b.blocked_id = v_uid));

  v_chats := v_chats_mitglied + v_chats_entdecken;

  -- --- Reiter 3: Entdecken --------------------------------------------------
  -- Deckungsgleich mit SocialService.getDiscoverPosts: oeffentliche Beitraege
  -- von Leuten, denen ich NICHT folge, ohne private und gesperrte Profile.
  select count(*) into v_entdecken
  from public.posts p
  join public.profiles a on a.id = p.user_id
  where p.created_at > v_b_entdecken
    and p.visibility = 'public'
    and coalesce(p.is_hidden, false) = false
    and p.user_id <> v_uid
    and coalesce(a.is_private, false) = false
    and coalesce(a.is_banned, false) = false
    and not exists (select 1 from public.follows f
                     where f.follower_id = v_uid and f.following_id = p.user_id
                       and f.status = 'accepted')
    and not exists (select 1 from public.user_blocks b
                     where (b.blocker_id = v_uid and b.blocked_id = p.user_id)
                        or (b.blocker_id = p.user_id and b.blocked_id = v_uid));

  return jsonb_build_object(
    'punkt', (v_feed > 0 or v_gruppen > 0 or v_chats > 0 or v_entdecken > 0),
    'reiter', jsonb_build_object(
      'feed',      jsonb_build_object('neu', v_feed      > 0, 'anzahl', least(v_feed, 99)),
      'gruppen',   jsonb_build_object('neu', v_gruppen   > 0, 'anzahl', least(v_gruppen, 99)),
      'chats',     jsonb_build_object('neu', v_chats     > 0, 'anzahl', least(v_chats, 99)),
      'entdecken', jsonb_build_object('neu', v_entdecken > 0, 'anzahl', least(v_entdecken, 99))),
    'communities', v_communities,
    'stand', now());
end;
$fn$;

comment on function public.community_hinweispunkte() is
  '2026-08-24: Alle Hinweispunkte in EINER Abfrage. Ebene 1 wird berechnet, '
  'nicht gespeichert. Blickt hoechstens 30 Tage zurueck.';

revoke all on function public.community_hinweispunkte() from public, anon;
grant execute on function public.community_hinweispunkte() to authenticated;


-- ----------------------------------------------------------------------------
-- Gegenstueck zum Schreiben
-- ----------------------------------------------------------------------------
--
-- vucko: "Als gesehen markieren, und zwar genau fuer den geoeffneten Bereich,
-- NICHT fuer die Ebene darueber."
--
-- Es gibt hier deshalb BEWUSST keine Weitergabe nach oben und keine nach
-- unten. Wer eine Community oeffnet, markiert genau diese Community. Der
-- Chats-Punkt geht dadurch nur dann aus, wenn es auch die letzte ungelesene
-- Community war - richtig so.
create or replace function public.community_als_gesehen_markieren(
  p_bereich      text,
  p_community_id uuid default null
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_jetzt timestamptz := now();
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.' using errcode = '28000';
  end if;

  if p_bereich is null
     or p_bereich not in ('feed', 'gruppen', 'chats', 'entdecken', 'community') then
    raise exception 'Unbekannter Bereich: %', coalesce(p_bereich, '(leer)')
      using errcode = '22023';
  end if;

  if (p_bereich = 'community') <> (p_community_id is not null) then
    raise exception 'Bereich und Community passen nicht zusammen.'
      using errcode = '22023';
  end if;

  -- Nur eigene Mitgliedschaften. Ohne diese Pruefung koennte jemand die
  -- Tabelle mit fremden Community-IDs vollschreiben.
  if p_bereich = 'community'
     and not exists (select 1 from public.community_members m
                      where m.community_id = p_community_id and m.user_id = v_uid) then
    raise exception 'Du bist kein Mitglied dieser Community.'
      using errcode = '42501';
  end if;

  insert into public.community_lesestand as l
    (user_id, bereich, community_id, gesehen_bis, aktualisiert_am)
  values (v_uid, p_bereich, p_community_id, v_jetzt, v_jetzt)
  on conflict (user_id, bereich, community_schluessel)
  do update set gesehen_bis     = greatest(l.gesehen_bis, excluded.gesehen_bis),
                aktualisiert_am = excluded.aktualisiert_am;

  return v_jetzt;
end;
$fn$;

comment on function public.community_als_gesehen_markieren(text, uuid) is
  '2026-08-24: Markiert GENAU den geoeffneten Bereich als gesehen. Kein '
  'Durchreichen nach oben oder unten. greatest() schuetzt vor einem Geraet '
  'mit nachgehender Uhr.';

revoke all on function public.community_als_gesehen_markieren(text, uuid) from public, anon;
grant execute on function public.community_als_gesehen_markieren(text, uuid) to authenticated;


-- ----------------------------------------------------------------------------
-- Index fuer die Feed-Frage
-- ----------------------------------------------------------------------------
--
-- GEMESSEN, nicht angenommen. Die Feed-Frage hat die Form
--   posts WHERE user_id IN (<meine Gefolgten>) AND created_at > <Stand>
--
-- a) Heute, mit 10 Zeilen in posts: der Planer nimmt einen Seq Scan ueber
--    EINE Seite (Buffers: shared hit=1, 0,2 ms). Ein Index bringt bei dieser
--    Groesse nachweislich nichts und wuerde auch gar nicht benutzt.
-- b) Deshalb dieselbe Abfrage gegen eine Kopie mit 200.000 Zeilen, warm
--    gelaufen, beide Varianten mit analyze:
--       nur idx_posts_created (created_at)   -> Bitmap Heap Scan, 10,9 ms
--       zusaetzlich (user_id, created_at)    -> Index Scan,         2,4 ms
--    Faktor 4,5. Die bestehenden Indizes reichen nicht: idx_posts_user_id
--    kennt die Zeit nicht, idx_posts_created kennt den Nutzer nicht.
--
-- Der Index kostet heute bei 10 Zeilen praktisch nichts und traegt genau
-- dann, wenn der Feed waechst.
create index if not exists idx_posts_user_created
  on public.posts (user_id, created_at desc);

-- Fuer die Gruppen-Frage ist nichts zu tun: group_messages hat bereits
-- group_messages_group_created_idx (group_id, created_at), community_messages
-- hat community_messages_community_created_idx (community_id, created_at desc),
-- communities hat communities_public_created_idx (is_public, created_at desc).
-- groups hat KEINEN Index auf (is_public, created_at) - bei 1 Zeile ist das
-- kein Thema, siehe "offen".


-- ============================================================================
-- TEIL 2 - Hashtags
-- ============================================================================
--
-- vucko: "Die Liste aller Beitraege zu einem Hashtag muss VOLLSTAENDIG und
-- zuverlaessig sein."
--
-- Warum keine Textsuche: `content ilike '%tour%'` findet auch "tourenfahrt"
-- und "kontour". Gemessen an einem Beispieltext liefert die Rauten-Suche
-- sauber getrennte Treffer, ilike nicht. Wer aus einer ilike-Liste auslost,
-- verlost an Leute, die nie teilgenommen haben. Zudem ist pg_trgm nicht
-- installiert, ein fuehrendes Prozentzeichen waere also jedes Mal ein voller
-- Tabellendurchlauf.

-- ----------------------------------------------------------------------------
-- Welche Zeichen darf ein Hashtag enthalten?
-- ----------------------------------------------------------------------------
--
-- ENTSCHEIDUNG (bindend fuer Client und Server):
--   * Erstes Zeichen: ein BUCHSTABE oder ein Unterstrich. Damit ist "#2026"
--     kein Hashtag, "#cruise2026" schon. Das haelt Preisangaben und
--     Hausnummern draussen.
--   * Danach: Buchstaben, Ziffern, Unterstrich.
--   * Laenge: 2 bis 50 Zeichen (ohne die Raute).
--   * BUCHSTABE heisst Unicode-Buchstabe, nicht nur A bis Z. Die Datenbank
--     laeuft auf en_US.UTF-8, [[:alpha:]] trifft damit nachweislich auch
--     Umlaute (geprueft: '#kurvenkoenig' und '#kurvenkönig' werden beide
--     vollstaendig erkannt).
--
-- UND DIE UMLAUT-FRAGE, die vucko ausdruecklich gestellt hat:
--   #kurvenkoenig und #kurvenkönig sind fuer einen Menschen DASSELBE. Wer
--   ein Gewinnspiel auslost, darf niemanden verlieren, nur weil er kein oe
--   auf der Tastatur hatte. Deshalb wird zu jedem Hashtag ein SCHLUESSEL
--   gespeichert: klein geschrieben, ae/oe/ue/ss ausgeschrieben, sonstige
--   Akzente entfernt. Gruppiert und gesucht wird ueber den Schluessel,
--   ANGEZEIGT wird die Schreibweise, die der Nutzer getippt hat.
--   Damit landen #Tourenfahrt, #tourenfahrt, #kurvenkönig und #kurvenkoenig
--   jeweils in derselben Liste. "#kontour" bleibt ein eigener Hashtag.
create or replace function public.hashtag_schluessel(p_tag text)
returns text
language sql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $fn$
  select translate(
           replace(replace(replace(replace(replace(replace(replace(replace(
             lower(p_tag),
             'ä', 'ae'), 'ö', 'oe'), 'ü', 'ue'), 'ß', 'ss'),
             'æ', 'ae'), 'ø', 'oe'), 'å', 'aa'), 'œ', 'oe'),
           'áàâãāăçćčéèêëēėęíìîïīıñńóòôõōšśúùûūýÿžźż',
           'aaaaaaccceeeeeeeiiiiiinnooooossuuuuyyzzz');
$fn$;

comment on function public.hashtag_schluessel(text) is
  '2026-08-24: Faltet einen Hashtag auf seine Vergleichsform. Klein '
  'geschrieben, ae/oe/ue/ss ausgeschrieben, Akzente entfernt. #Kurvenkoenig '
  'und #kurvenkönig ergeben denselben Schluessel - sonst verliert ein '
  'Gewinnspiel Teilnehmer an der Tastatur.';

-- Bewusst KEIN execute fuer authenticated: der Client soll nicht selbst
-- falten. Die Faltung gehoert in die Datenbank, sonst laufen Client und
-- Server irgendwann auseinander und ein Gewinnspiel verliert Teilnehmer.
revoke all on function public.hashtag_schluessel(text) from public, anon, authenticated;


-- ----------------------------------------------------------------------------
-- Die Ablage
-- ----------------------------------------------------------------------------
create table if not exists public.post_hashtags (
  post_id        uuid        not null references public.posts(id) on delete cascade,
  -- so getippt wie im Beitrag, nur klein geschrieben (Anzeige)
  tag            text        not null,
  -- gefaltete Vergleichsform (Suche, Gruppierung, Auslosung)
  tag_schluessel text        generated always as (public.hashtag_schluessel(tag)) stored,
  erstellt_am    timestamptz not null default now(),
  primary key (post_id, tag_schluessel)
);

comment on table public.post_hashtags is
  '2026-08-24: Hashtags eines Beitrags. Wird AUSSCHLIESSLICH vom Trigger '
  'post_hashtags_trg gefuellt, nie vom Client - Lehre aus dem '
  'Meldungs-Missbrauchsschutz vom 26.07.: sonst traegt sich jemand per '
  'manipuliertem Aufruf in ein Gewinnspiel ein, ohne den Hashtag je '
  'geschrieben zu haben.';

-- Nachschlagen "alle Beitraege zu einem Hashtag".
create index if not exists post_hashtags_tag_idx
  on public.post_hashtags (tag_schluessel, post_id);

-- Vorschlaege beim Tippen: LIKE 'praefix%'. Die Datenbank laeuft auf
-- en_US.UTF-8, dort kann ein normaler btree-Index fuer LIKE NICHT benutzt
-- werden - dafuer braucht es text_pattern_ops. Damit bleibt die Suche
-- indexgestuetzt, obwohl pg_trgm nicht installiert ist.
create index if not exists post_hashtags_praefix_idx
  on public.post_hashtags (tag_schluessel text_pattern_ops);

alter table public.post_hashtags enable row level security;

drop policy if exists post_hashtags_select_all on public.post_hashtags;
create policy post_hashtags_select_all
  on public.post_hashtags
  for select
  to authenticated
  using (true);

-- Dieselbe Falle wie oben: die Vorgaberechte von Supabase geben
-- authenticated auch TRUNCATE, und TRUNCATE fragt keine RLS-Regel.
revoke all on public.post_hashtags from anon, public;
revoke insert, update, delete, truncate, references, trigger
  on public.post_hashtags from authenticated;
grant select on public.post_hashtags to authenticated;


-- ----------------------------------------------------------------------------
-- Der Trigger
-- ----------------------------------------------------------------------------
--
-- Bearbeiten und Loeschen ziehen mit:
--   * INSERT           -> Hashtags werden angelegt
--   * UPDATE OF content-> alte Zuordnung weg, neue angelegt
--   * DELETE           -> erledigt "on delete cascade" am Fremdschluessel
create or replace function public.post_hashtags_pflegen()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if tg_op = 'UPDATE' then
    -- Nur arbeiten, wenn sich der Text wirklich geaendert hat. Ein Update auf
    -- likes_count darf die Hashtags nicht neu schreiben.
    if new.content is not distinct from old.content then
      return new;
    end if;
    delete from public.post_hashtags where post_id = new.id;
  end if;

  insert into public.post_hashtags (post_id, tag)
  select distinct new.id, lower(m[1])
  from regexp_matches(coalesce(new.content, ''),
                      '#([[:alpha:]_][[:alnum:]_]{1,49})', 'g') as m
  on conflict do nothing;

  return new;
end;
$fn$;

comment on function public.post_hashtags_pflegen() is
  '2026-08-24: Haelt post_hashtags am Beitragstext. Nur der Trigger schreibt.';

-- Eine Trigger-Funktion darf NIE als RPC erreichbar sein. Ohne das
-- Entziehen fuer authenticated haengt sie unter /rest/v1/rpc/ und ist als
-- SECURITY DEFINER aufrufbar - der Advisor meldet das zu Recht.
revoke all on function public.post_hashtags_pflegen() from public, anon, authenticated;

drop trigger if exists post_hashtags_trg on public.posts;
create trigger post_hashtags_trg
  after insert or update of content on public.posts
  for each row
  execute function public.post_hashtags_pflegen();

-- Nachtrag fuer den Bestand. Gemessen: von den 10 vorhandenen Beitraegen
-- enthaelt keiner eine Raute, es kommen also 0 Zeilen dazu. Der Nachtrag
-- steht trotzdem hier, damit die Migration auf einer anderen Datenbank
-- (oder nach einem Restore) dasselbe Ergebnis liefert.
insert into public.post_hashtags (post_id, tag)
select distinct p.id, lower(m[1])
from public.posts p
cross join lateral regexp_matches(coalesce(p.content, ''),
                                  '#([[:alpha:]_][[:alnum:]_]{1,49})', 'g') as m
on conflict do nothing;


-- ----------------------------------------------------------------------------
-- Abfrage 1: alle Beitraege zu einem Hashtag (die Auslosungsliste)
-- ----------------------------------------------------------------------------
--
-- Zwei bewusste Einschraenkungen, die vucko kennen muss:
--   * nur visibility = 'public'. Ein Beitrag, den nur die eigenen Follower
--     sehen, kann keine oeffentliche Gewinnspiel-Teilnahme sein.
--   * keine ausgeblendeten Beitraege und keine gesperrten Konten. Ein
--     moderierter Beitrag soll nicht gewinnen.
-- Beides ist eine Produktentscheidung, keine technische Grenze.
create or replace function public.hashtag_beitraege(
  p_tag    text,
  p_limit  int default 50,
  p_offset int default 0
)
returns table (
  post_id    uuid,
  user_id    uuid,
  username   text,
  avatar_url text,
  content    text,
  created_at timestamptz,
  tag        text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.id, p.user_id, pr.username, pr.avatar_url, p.content, p.created_at, h.tag
  from public.post_hashtags h
  join public.posts p     on p.id  = h.post_id
  join public.profiles pr on pr.id = p.user_id
  where h.tag_schluessel = public.hashtag_schluessel(
          btrim(regexp_replace(coalesce(p_tag, ''), '^#+', '')))
    and p.visibility = 'public'
    and coalesce(p.is_hidden, false) = false
    and coalesce(pr.is_banned, false) = false
  order by p.created_at desc, p.id
  limit  greatest(1, least(coalesce(p_limit, 50), 500))
  offset greatest(0, coalesce(p_offset, 0));
$fn$;

comment on function public.hashtag_beitraege(text, int, int) is
  '2026-08-24: Alle oeffentlichen Beitraege zu einem Hashtag. Grundlage fuer '
  'die Gewinnspiel-Auslosung. Gross- und Kleinschreibung sowie Umlaut-'
  'Schreibweise spielen keine Rolle.';

revoke all on function public.hashtag_beitraege(text, int, int) from public, anon;
grant execute on function public.hashtag_beitraege(text, int, int) to authenticated;


-- ----------------------------------------------------------------------------
-- Abfrage 2: beliebte Hashtags vorschlagen
-- ----------------------------------------------------------------------------
--
-- Ohne Praefix: die haeufigsten Hashtags im Zeitfenster (Vorschlagsliste).
-- Mit Praefix: Vervollstaendigung beim Tippen, indexgestuetzt ueber
-- post_hashtags_praefix_idx.
-- Angezeigt wird die JUENGSTE tatsaechliche Schreibweise, gezaehlt wird ueber
-- den Schluessel - #Tourenfahrt und #tourenfahrt sind eine Zeile.
create or replace function public.hashtag_vorschlaege(
  p_praefix text default null,
  p_tage    int  default 30,
  p_limit   int  default 10
)
returns table (
  tag            text,
  tag_schluessel text,
  anzahl         bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select
    (array_agg(h.tag order by p.created_at desc, p.id))[1] as tag,
    h.tag_schluessel,
    count(*) as anzahl
  from public.post_hashtags h
  join public.posts p on p.id = h.post_id
  where p.visibility = 'public'
    and coalesce(p.is_hidden, false) = false
    and p.created_at > now()
        - (greatest(1, least(coalesce(p_tage, 30), 365)) * interval '1 day')
    and (
      p_praefix is null
      or btrim(regexp_replace(p_praefix, '^#+', '')) = ''
      or h.tag_schluessel like
         public.hashtag_schluessel(btrim(regexp_replace(p_praefix, '^#+', ''))) || '%'
    )
  group by h.tag_schluessel
  order by count(*) desc, h.tag_schluessel
  limit greatest(1, least(coalesce(p_limit, 10), 50));
$fn$;

comment on function public.hashtag_vorschlaege(text, int, int) is
  '2026-08-24: Beliebte Hashtags, wahlweise auf einen Praefix eingeschraenkt.';

revoke all on function public.hashtag_vorschlaege(text, int, int) from public, anon;
grant execute on function public.hashtag_vorschlaege(text, int, int) to authenticated;
