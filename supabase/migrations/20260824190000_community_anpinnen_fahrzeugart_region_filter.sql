-- ═══════════════════════════════════════════════════════════════════════════
-- 2026-08-24 — Communities: Anpinnen, Fahrzeugart, Region, Filter
--
-- Auftrag Vucko am 24.08. (zwei Nachrichten, woertlich):
--   „und man soll auch communitys anpinnen koennen und einen filter haben bei
--    oeffentliche communitys wo man einstellen kann auch bei der erstellung
--    obs fuer autofahrer motorradfahrer in welcher region und das man dann
--    beim filter nach region nach auto motorrad oder beides und sonstige
--    sachen die noch sinn machen einstellen kann"
--   „man soll auch community anpinnen koennen und wenn man in der community
--    oben klickt auf den namen wenn man drinnen ist, soll man auch als
--    normaler user in der gruppe die eckdaten wie mitglieder usw sehen
--    koennen aber man soll nichts aendern koennen"
--
-- Diese Migration ist NUR das Fundament: Datenmodell, Rechte, eine Abfrage.
-- Die Oberflaeche (Filterblatt, Pin-Geste, Eckdaten-Blatt) liegt in lib/.
--
-- GEMESSENER IST-ZUSTAND, 24.08.2026, der die Entscheidungen unten traegt:
--   * communities: 11 Spalten, kein Feld fuer Fahrzeugart, keins fuer Region.
--   * 6 Communities. Mitglieder 2 bis 19. Eine davon („Legacy", 14
--     Mitglieder) hat NIE eine Nachricht gehabt, „Cruise Connector" (19
--     Mitglieder) seit dem 14.08. nicht mehr.
--   * 183 Profile, 165 mit Land — aber nur DREI Laender: AT, CH, DE.
--   * profiles.region ist vorhanden und WERTLOS: bei allen 168 gefuellten
--     Zeilen steht dort derselbe Wert wie in country_code (AT/AT, DE/DE,
--     CH/CH). Es gibt heute also keine feinere Ortsangabe am Konto.
--   * profile_vehicles.vehicle_type: 73 Autos, 13 Motorraeder, 0 NULL,
--     CHECK-Constraint auf ('car','motorcycle'). Echte Daten.
--   * Hoechste Zahl an Mitgliedschaften eines Nutzers: 3. Schnitt 1,55.
--   * Das Leserecht auf public.communities ist seit 20260823123000
--     SPALTENWEISE. Jede neue Spalte braucht ein eigenes `grant select`.
-- ═══════════════════════════════════════════════════════════════════════════


-- ───────────────────────────────────────────────────────────────────────────
-- 1. REGION — eine geschlossene Liste, kein Freitext
--
-- Warum ueberhaupt nachgedacht statt gleich gebaut:
--
--   a) „Nach Land filtern" filtert nichts. Es gibt drei Laender und sechs
--      Communities. Der Regler waere ein Versprechen ohne Wirkung.
--
--   b) Feiner ginge nur Bundesland/Kanton. Woher kaeme der Wert?
--      - profiles.country_code: liefert AT/CH/DE, also wieder nur das Land.
--      - profiles.region: gemessen identisch mit country_code, wertlos.
--      - profiles.last_known_lat/lng: ein Punkt. Daraus ein Bundesland zu
--        machen hiesse Grenzpolygone in die Datenbank oder einen fremden
--        Dienst dazuzunehmen. Beides ist kein Fundament, das ist ein eigenes
--        Vorhaben. Ausdruecklich ausgeschlossen war „ohne neuen Fremddienst".
--      - route_regions: hat zwar country_code/admin1_name, ist aber die
--        Pool-Tabelle der Routenberechnung — 31 Zeilen, 10 verschiedene
--        admin1_name, luckenhaft nach Bedarf gewachsen. Als Auswahlliste fuer
--        Menschen ungeeignet, und CLAUDE.md warnt beim Nachbarn
--        route_pool_coverage genau davor, eine Bedarfstabelle als Wahrheit zu
--        nehmen.
--
--   c) Der Gruender tippt die Region also selbst — aber NICHT frei. Frei
--      getippt endet das wie das Marken-Feld: 36 Schreibweisen fuer 30 Marken,
--      gestern erst aufgeraeumt (20260824101000). Deshalb waehlt er aus einer
--      GESCHLOSSENEN Liste, und ein Fremdschluessel erzwingt das. Ein zweites
--      „Vorarlberg / vorarlberg / Ländle" kann gar nicht erst entstehen.
--
-- Die Liste ist statisches Wissen, kein Dienst: die Verwaltungseinheiten von
-- AT, CH und DE nach ISO 3166-2 — 9 Bundeslaender, 26 Kantone, 16
-- Bundeslaender. Dazu drei Zeilen fuer „das ganze Land", damit eine Community
-- sich auch als „oesterreichweit" ausgeben kann, ohne ein Bundesland zu
-- behaupten, das sie nicht hat.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists public.community_regionen (
  -- ISO 3166-2 fuer Bundeslaender/Kantone (AT-8, DE-BY, CH-ZH),
  -- ISO 3166-1 fuer die drei „ganzes Land"-Zeilen (AT, CH, DE).
  code       text primary key,
  land_code  text not null check (land_code in ('AT', 'CH', 'DE')),
  -- Deutscher Anzeigename. Steht so in der Oberflaeche.
  name       text not null,
  -- true = die Zeile meint das ganze Land, nicht eine Verwaltungseinheit.
  ist_land   boolean not null default false,
  -- Reihenfolge im Auswahlblatt. Land zuerst, dann alphabetisch.
  sortierung smallint not null default 100
);

comment on table public.community_regionen is
  '2026-08-24: Geschlossene Auswahlliste fuer communities.region_code. '
  'Verwaltungseinheiten von AT/CH/DE nach ISO 3166-2, dazu drei Zeilen fuer '
  'das jeweils ganze Land. Geschlossen mit Absicht: ein frei getipptes '
  'Regionsfeld haette dieselben 36-Schreibweisen-fuer-30-Werte erzeugt wie '
  'das Markenfeld vor dem 24.08.';

comment on column public.community_regionen.ist_land is
  'true = „ganz Oesterreich/Schweiz/Deutschland". Eine solche Community '
  'erscheint in JEDEM Regionsfilter ihres Landes, und ein Filter auf das '
  'ganze Land findet umgekehrt alle Regionen darin.';

insert into public.community_regionen (code, land_code, name, ist_land, sortierung)
values
  -- Die drei „ganzes Land"-Zeilen stehen im Auswahlblatt oben.
  ('AT',    'AT', 'Ganz Österreich',          true,  0),
  ('CH',    'CH', 'Ganze Schweiz',            true,  0),
  ('DE',    'DE', 'Ganz Deutschland',         true,  0),

  -- Österreich: 9 Bundesländer
  ('AT-1',  'AT', 'Burgenland',               false, 10),
  ('AT-2',  'AT', 'Kärnten',                  false, 10),
  ('AT-3',  'AT', 'Niederösterreich',         false, 10),
  ('AT-4',  'AT', 'Oberösterreich',           false, 10),
  ('AT-5',  'AT', 'Salzburg',                 false, 10),
  ('AT-6',  'AT', 'Steiermark',               false, 10),
  ('AT-7',  'AT', 'Tirol',                    false, 10),
  ('AT-8',  'AT', 'Vorarlberg',               false, 10),
  ('AT-9',  'AT', 'Wien',                     false, 10),

  -- Schweiz: 26 Kantone, deutsche Namen (Genf statt Genève)
  ('CH-AG', 'CH', 'Aargau',                   false, 10),
  ('CH-AI', 'CH', 'Appenzell Innerrhoden',    false, 10),
  ('CH-AR', 'CH', 'Appenzell Ausserrhoden',   false, 10),
  ('CH-BE', 'CH', 'Bern',                     false, 10),
  ('CH-BL', 'CH', 'Basel-Landschaft',         false, 10),
  ('CH-BS', 'CH', 'Basel-Stadt',              false, 10),
  ('CH-FR', 'CH', 'Freiburg',                 false, 10),
  ('CH-GE', 'CH', 'Genf',                     false, 10),
  ('CH-GL', 'CH', 'Glarus',                   false, 10),
  ('CH-GR', 'CH', 'Graubünden',               false, 10),
  ('CH-JU', 'CH', 'Jura',                     false, 10),
  ('CH-LU', 'CH', 'Luzern',                   false, 10),
  ('CH-NE', 'CH', 'Neuenburg',                false, 10),
  ('CH-NW', 'CH', 'Nidwalden',                false, 10),
  ('CH-OW', 'CH', 'Obwalden',                 false, 10),
  ('CH-SG', 'CH', 'St. Gallen',               false, 10),
  ('CH-SH', 'CH', 'Schaffhausen',             false, 10),
  ('CH-SO', 'CH', 'Solothurn',                false, 10),
  ('CH-SZ', 'CH', 'Schwyz',                   false, 10),
  ('CH-TG', 'CH', 'Thurgau',                  false, 10),
  ('CH-TI', 'CH', 'Tessin',                   false, 10),
  ('CH-UR', 'CH', 'Uri',                      false, 10),
  ('CH-VD', 'CH', 'Waadt',                    false, 10),
  ('CH-VS', 'CH', 'Wallis',                   false, 10),
  ('CH-ZG', 'CH', 'Zug',                      false, 10),
  ('CH-ZH', 'CH', 'Zürich',                   false, 10),

  -- Deutschland: 16 Bundesländer
  ('DE-BW', 'DE', 'Baden-Württemberg',        false, 10),
  ('DE-BY', 'DE', 'Bayern',                   false, 10),
  ('DE-BE', 'DE', 'Berlin',                   false, 10),
  ('DE-BB', 'DE', 'Brandenburg',              false, 10),
  ('DE-HB', 'DE', 'Bremen',                   false, 10),
  ('DE-HH', 'DE', 'Hamburg',                  false, 10),
  ('DE-HE', 'DE', 'Hessen',                   false, 10),
  ('DE-MV', 'DE', 'Mecklenburg-Vorpommern',   false, 10),
  ('DE-NI', 'DE', 'Niedersachsen',            false, 10),
  ('DE-NW', 'DE', 'Nordrhein-Westfalen',      false, 10),
  ('DE-RP', 'DE', 'Rheinland-Pfalz',          false, 10),
  ('DE-SL', 'DE', 'Saarland',                 false, 10),
  ('DE-SN', 'DE', 'Sachsen',                  false, 10),
  ('DE-ST', 'DE', 'Sachsen-Anhalt',           false, 10),
  ('DE-SH', 'DE', 'Schleswig-Holstein',       false, 10),
  ('DE-TH', 'DE', 'Thüringen',                false, 10)
on conflict (code) do update
  set land_code  = excluded.land_code,
      name       = excluded.name,
      ist_land   = excluded.ist_land,
      sortierung = excluded.sortierung;

create index if not exists community_regionen_land_idx
  on public.community_regionen (land_code, sortierung, name);

alter table public.community_regionen enable row level security;

-- Die Liste der Bundeslaender ist Allgemeinwissen. Lesen darf sie jeder,
-- aendern niemand ausser einer Migration (kein insert/update/delete-Recht).
drop policy if exists community_regionen_lesen on public.community_regionen;
create policy community_regionen_lesen
  on public.community_regionen for select
  to anon, authenticated
  using (true);

revoke all on public.community_regionen from public, anon, authenticated;
grant select on public.community_regionen to anon, authenticated;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. FAHRZEUGART und REGION an der Community
--
-- FAHRZEUGART, Werte: 'car', 'motorcycle', 'both'.
--   Die ersten beiden sind WORTGLEICH mit profile_vehicles.vehicle_type
--   (gemessen: 73 car, 13 motorcycle, 0 NULL, CHECK-Constraint). Absicht:
--   ein spaeteres „passt zu meinem Fahrzeug" braucht dann keine
--   Uebersetzungstabelle — genau so eine ist beim Markenfeld noetig geworden.
--
--   BESTANDSDATEN: Standardwert 'both'. Die sechs vorhandenen Communities
--   haben nie eine Fahrzeugart angegeben. Waere der Standard NULL oder 'car',
--   fielen sie ab sofort aus dem Filter — ein Feature, das bestehende Inhalte
--   verschwinden laesst, ist ein Defekt. 'both' heisst „offen fuer alle" und
--   ist genau das, was sie heute sind.
--
-- REGION: region_code, NULL erlaubt.
--   NULL heisst „ueberregional / keine Angabe" und faellt aus KEINEM
--   Regionsfilter heraus (siehe Abfrage in Teil 4). Auch das schuetzt die
--   sechs Bestands-Communities: sie bleiben ueberall sichtbar, bis ein Admin
--   sich bewusst auf eine Region festlegt.
-- ───────────────────────────────────────────────────────────────────────────

alter table public.communities
  add column if not exists fahrzeugart text not null default 'both',
  add column if not exists region_code text;

alter table public.communities
  drop constraint if exists communities_fahrzeugart_check;
alter table public.communities
  add constraint communities_fahrzeugart_check
  check (fahrzeugart in ('car', 'motorcycle', 'both'));

-- on update cascade, damit eine spaetere Umbenennung eines Codes nicht
-- haendisch nachgezogen werden muss. KEIN on delete cascade: eine Region
-- verschwindet nicht, und wenn doch, soll das Loeschen scheitern statt
-- stillschweigend Communities zu veraendern.
alter table public.communities
  drop constraint if exists communities_region_code_fkey;
alter table public.communities
  add constraint communities_region_code_fkey
  foreign key (region_code) references public.community_regionen(code)
  on update cascade;

comment on column public.communities.fahrzeugart is
  'Fuer wen die Community gedacht ist: car | motorcycle | both. '
  'Standard both = offen fuer alle; damit faellt keine der sechs '
  'Bestands-Communities aus dem Filter. Die Werte car/motorcycle sind '
  'wortgleich mit profile_vehicles.vehicle_type.';

comment on column public.communities.region_code is
  'Bundesland/Kanton oder „ganzes Land" aus community_regionen. NULL = '
  'ueberregional; solche Communities erscheinen in JEDEM Regionsfilter. '
  'Fremdschluessel mit Absicht: ein frei getipptes Feld haette dieselbe '
  'Schreibweisen-Flut erzeugt wie das Markenfeld.';

create index if not exists communities_filter_idx
  on public.communities (is_public, fahrzeugart, region_code);
create index if not exists communities_region_idx
  on public.communities (region_code);

-- ─── Die Falle aus CLAUDE.md: SPALTENWEISES Leserecht ────────────────────
-- Seit 20260823123000 haengt das select-Recht auf public.communities an einer
-- Spaltenliste. Ohne die drei Zeilen hier waere die App fuer die beiden neuen
-- Felder blind — und schlimmer: eine Abfrage, die sie mitnimmt, faellt mit
-- 42501 „permission denied for table communities" fuer die GANZE Zeile aus,
-- nicht nur fuer die eine Spalte. Der Rueckfall _isMissingColumn im Client
-- faengt nur 42703 und greift dort NICHT.
grant select (fahrzeugart, region_code) on public.communities to anon, authenticated;
grant insert (fahrzeugart, region_code) on public.communities to anon, authenticated;
grant update (fahrzeugart, region_code) on public.communities to anon, authenticated;

-- Nachweis im Deploy selbst, nicht erst im Test: laeuft die Migration durch,
-- sind die Rechte da.
do $$
declare
  v_fehlt text;
begin
  select string_agg(s.spalte, ', ')
    into v_fehlt
  from (values ('fahrzeugart'), ('region_code')) as s(spalte)
  where not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'communities'
      and grantee = 'authenticated' and privilege_type = 'SELECT'
      and column_name = s.spalte
  );

  if v_fehlt is not null then
    raise exception
      'Spaltenrecht fehlt fuer authenticated auf communities: % — die App '
      'waere fuer das neue Feld blind.', v_fehlt;
  end if;
end $$;


-- ───────────────────────────────────────────────────────────────────────────
-- 3. ANPINNEN — eine Entscheidung JE NUTZER, eigene Tabelle
--
-- Wo gehoert das hin? Es gab zwei Vorbilder im Haus:
--
--   profiles.home_layout (20260824140000) — eine jsonb-Spalte am Konto.
--     Richtig DORT, weil die Kachel-Anordnung ein in sich geschlossener Block
--     ist: sie zeigt auf nichts, es gibt genau einen Stand je Konto, und
--     niemand muss danach sortieren oder filtern.
--
--   profile_featured_routes (20260819140000) — eigene Tabelle mit `position`.
--     Richtig DORT, weil ein Highlight auf eine Zeile in `routes` ZEIGT.
--
-- Ein Pin ist der zweite Fall, aus drei Gruenden:
--
--   1. Er zeigt auf eine Zeile in `communities`. Als jsonb-Liste auf
--      `profiles` bliebe nach dem Loeschen einer Community (erlaubt:
--      leaders_delete_communities) eine tote Kennung stehen, die jeder
--      Aufrufer selbst wegraeumen muesste. `on delete cascade` erledigt das
--      ohne eine Zeile Pflegecode — dasselbe Argument steht woertlich im Kopf
--      von 20260819140000.
--   2. Die Filterabfrage in Teil 4 muss serverseitig nach „angepinnt zuerst"
--      SORTIEREN. Gegen eine Tabelle ist das ein Index-Zugriff; gegen ein
--      jsonb-Feld muesste je Zeile im Array gesucht werden.
--   3. `profiles` ist fuer jeden angemeldeten Nutzer lesbar. Bei
--      home_layout wurde das bewusst in Kauf genommen (Kachel-Anordnung ist
--      keine Angabe ueber jemanden). Pins sind es auch nicht — aber sie
--      gehen trotzdem niemanden etwas an, und in einer eigenen Tabelle
--      kosten sie genau eine Regel statt einer Ausnahme.
--
-- REIHENFOLGE: `position`, 1..10, wie bei profile_featured_routes. Warum 10
-- und nicht 3: dort sind es drei PLAETZE in einer Praesentation. Hier wird
-- eine Arbeitsliste sortiert. Eine Grenze braucht es trotzdem — wer alles
-- anpinnt, hat nichts angepinnt. Gemessen ist die hoechste Zahl an
-- Mitgliedschaften heute 3, im Schnitt 1,55; 10 engt also niemanden ein.
--
-- Die Eindeutigkeit auf `position` ist DEFERRABLE. Ohne das scheitert schon
-- das Schliessen einer Luecke (`set position = position - 1`) an sich selbst,
-- weil Postgres jede Zeile sofort prueft und die 2 noch belegt ist, waehrend
-- die 3 gerade zur 2 wird. Deshalb liegt der Primaerschluessel auf
-- (user_id, community_id) — eine Community nur einmal angepinnt — und die
-- Platzvergabe auf einer aufgeschobenen Regel.
-- ───────────────────────────────────────────────────────────────────────────

create table if not exists public.community_pins (
  user_id      uuid     not null references auth.users(id) on delete cascade,
  community_id uuid     not null references public.communities(id) on delete cascade,
  position     smallint not null check (position between 1 and 10),
  created_at   timestamptz not null default now(),
  primary key (user_id, community_id),
  constraint community_pins_platz_eindeutig
    unique (user_id, position) deferrable initially deferred
);

comment on table public.community_pins is
  '2026-08-24: Welche Communities ein Nutzer oben haelt, und in welcher '
  'Reihenfolge. Eine Entscheidung JE NUTZER — sie sagt nichts ueber die '
  'Community aus, deshalb steht sie nicht an ihr. Privat: nur der eigene '
  'Nutzer liest seine Zeilen.';

comment on column public.community_pins.position is
  'Platz 1 bis 10, luckenlos und aufsteigend. Platz 1 steht ganz oben. '
  'Die Eindeutigkeitsregel ist aufgeschoben, damit das Umsortieren in einer '
  'Anweisung moeglich ist.';

create index if not exists community_pins_community_idx
  on public.community_pins (community_id);

alter table public.community_pins enable row level security;

-- Auch das LESEN ist auf die eigenen Zeilen begrenzt — anders als bei
-- profile_featured_routes, die absichtlich auf dem oeffentlichen Profil
-- stehen. Ein Pin ist keine Veroeffentlichung, sondern eine Sortierung der
-- eigenen Liste.
-- `(select auth.uid())` statt `auth.uid()`, sonst wertet Postgres die
-- Funktion je Zeile neu aus (Advisor-Befund auth_rls_initplan).
drop policy if exists community_pins_select_own on public.community_pins;
create policy community_pins_select_own
  on public.community_pins for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists community_pins_insert_own on public.community_pins;
create policy community_pins_insert_own
  on public.community_pins for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists community_pins_update_own on public.community_pins;
create policy community_pins_update_own
  on public.community_pins for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists community_pins_delete_own on public.community_pins;
create policy community_pins_delete_own
  on public.community_pins for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.community_pins from public, anon;
grant select, insert, update, delete on public.community_pins to authenticated;


-- ─── Anpinnen und Loesen in EINEM Aufruf ─────────────────────────────────
--
-- Warum eine Funktion statt insert/delete aus dem Client: die Plaetze muessen
-- luckenlos bleiben. Loest man Platz 2 von dreien und der Client vergisst das
-- Nachruecken, steht dauerhaft eine Luecke, und der naechste Pin bekommt
-- Platz 4 — oder scheitert an der 10er-Grenze, obwohl nur drei Pins da sind.
-- Das gehoert an EINE Stelle, nicht in jeden Aufrufer.
--
-- SECURITY INVOKER mit Absicht: die Funktion fasst ausschliesslich die Zeilen
-- des Aufrufers an, die Zeilenregeln oben decken das vollstaendig ab. Als
-- SECURITY DEFINER waere sie ein Umweg um genau diese Regeln und der Advisor
-- meldete sie zu Recht.
create or replace function public.community_pin_setzen(
  p_community_id uuid,
  p_angepinnt    boolean
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid      uuid := (select auth.uid());
  v_position smallint;
  v_anzahl   integer;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;
  if p_community_id is null then
    raise exception 'Es fehlt die Community.';
  end if;

  select position into v_position
  from public.community_pins
  where user_id = v_uid and community_id = p_community_id
  for update;

  -- ── Loesen ──
  if not coalesce(p_angepinnt, false) then
    if v_position is null then
      return jsonb_build_object('angepinnt', false, 'position', null);
    end if;

    delete from public.community_pins
    where user_id = v_uid and community_id = p_community_id;

    -- Luecke schliessen. Nur moeglich, weil die Regel aufgeschoben ist.
    update public.community_pins
       set position = position - 1
     where user_id = v_uid and position > v_position;

    return jsonb_build_object('angepinnt', false, 'position', null);
  end if;

  -- ── Anpinnen ──
  if v_position is not null then
    -- Schon oben. Zweiter Fingertipp, doppelt gesendeter Aufruf.
    return jsonb_build_object('angepinnt', true, 'position', v_position);
  end if;

  select count(*) into v_anzahl
  from public.community_pins
  where user_id = v_uid;

  if v_anzahl >= 10 then
    raise exception
      'Du hast schon 10 Communities angepinnt. Löse zuerst eine davon.';
  end if;

  -- Ans Ende. Wer eine woanders haben will, sortiert mit
  -- community_pins_ordnen.
  insert into public.community_pins (user_id, community_id, position)
  values (v_uid, p_community_id, (v_anzahl + 1)::smallint);

  return jsonb_build_object('angepinnt', true, 'position', v_anzahl + 1);
end;
$function$;

comment on function public.community_pin_setzen(uuid, boolean) is
  'Pinnt eine Community fuer den aufrufenden Nutzer an oder loest sie und '
  'haelt die Plaetze dabei luckenlos.';

revoke all on function public.community_pin_setzen(uuid, boolean) from public, anon;
grant execute on function public.community_pin_setzen(uuid, boolean) to authenticated;


-- Umsortieren in einem Rutsch. Die uebergebene Reihenfolge IST die neue
-- Reihenfolge; was fehlt, ist danach nicht mehr angepinnt.
create or replace function public.community_pins_ordnen(
  p_community_ids uuid[]
)
returns jsonb
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid   uuid := (select auth.uid());
  v_liste uuid[];
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  -- Doppelte raus, Reihenfolge des ersten Vorkommens behalten.
  select coalesce(array_agg(id order by rn), '{}'::uuid[])
    into v_liste
  from (
    select id, min(rn) as rn
    from unnest(coalesce(p_community_ids, '{}'::uuid[]))
         with ordinality as t(id, rn)
    where id is not null
    group by id
  ) eindeutig;

  if array_length(v_liste, 1) > 10 then
    raise exception 'Es lassen sich höchstens 10 Communities anpinnen.';
  end if;

  delete from public.community_pins
  where user_id = v_uid
    and not (community_id = any (v_liste));

  insert into public.community_pins (user_id, community_id, position)
  select v_uid, t.id, t.rn::smallint
  from unnest(v_liste) with ordinality as t(id, rn)
  on conflict (user_id, community_id) do update
    set position = excluded.position;

  return jsonb_build_object('anzahl', coalesce(array_length(v_liste, 1), 0));
end;
$function$;

comment on function public.community_pins_ordnen(uuid[]) is
  'Setzt die komplette Pin-Reihenfolge des Aufrufers neu. Was nicht in der '
  'Liste steht, ist danach nicht mehr angepinnt.';

revoke all on function public.community_pins_ordnen(uuid[]) from public, anon;
grant execute on function public.community_pins_ordnen(uuid[]) to authenticated;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. DER FILTER — eine Abfrage, serverseitig, Angepinntes oben
--
-- Vucko: „nach region nach auto motorrad oder beides und sonstige sachen die
-- noch sinn machen". Was drin ist und warum:
--
--   p_fahrzeugart  — beauftragt. WICHTIG: „Auto" liefert auch die
--                    'both'-Communities. Sonst waere „offen fuer alle" fuer
--                    genau die Leute unsichtbar, fuer die es gemeint ist.
--   p_region_code  — beauftragt. Nimmt ein Bundesland/einen Kanton ODER ein
--                    ganzes Land. Die Hierarchie wirkt in beide Richtungen:
--                    Filter „Vorarlberg" findet auch „ganz Österreich",
--                    Filter „ganz Österreich" findet auch „Vorarlberg".
--                    Ueberregionale Communities (region_code NULL) fallen
--                    NIE heraus.
--   p_suche        — ERGAENZT, gross-/kleinschreibungsunabhaengig (ilike).
--                    Begruendung: die Suche ist der einzige Regler,
--                    der eine BESTIMMTE Community findet statt eine Auswahl
--                    einzugrenzen. Sobald die Liste ueber eine Bildschirmhoehe
--                    waechst, ist sie der meistbenutzte Weg.
--   p_sortierung   — ERGAENZT ('aktiv' | 'gross' | 'neu', Standard 'aktiv').
--                    Begruendung aus den Messwerten: „Legacy" hat 14
--                    Mitglieder und NIE eine Nachricht gehabt, „Cruise
--                    Connector" 19 Mitglieder und seit dem 14.08. keine. Eine
--                    tote Community mit vielen Mitgliedern ist die
--                    schlechteste Empfehlung, die diese Liste geben kann.
--                    Die heutige feste Sortierung „neueste zuerst" bleibt als
--                    Wahl erhalten.
--
-- BEWUSST WEGGELASSEN (ein Filter mit acht Reglern ist schlechter als einer
-- mit dreien):
--   * Mindest-Mitgliederzahl. Gemessen 2 bis 19 bei sechs Communities — ein
--     Regler dafuer trifft entweder alles oder nichts. „Groesste zuerst"
--     leistet dasselbe ohne Regler.
--   * Oeffentlich/privat. Private Zeilen gibt die Zeilenregel
--     communities_visible_public_or_member ohnehin nicht heraus. Ein
--     Schalter, der nichts aendern kann, ist ein Versprechen, das die Liste
--     nicht haelt.
--   * Marke („BMW-Community"). Das ist ein Merkmal von PERSONEN
--     (profile_vehicles), nicht von Communities. Als freies Community-Feld
--     holt es genau das Chaos zurueck, das am 24.08. aufgeraeumt wurde.
--     Falls es kommt, dann als Fremdschluessel auf vehicle_brand_alias —
--     nicht als Textfeld, und nicht heute.
--   * Sprache/Land als eigener Regler. Alle 183 Profile sind AT, CH oder DE;
--     das Land steckt bereits in p_region_code.
--   * Entfernung in km. Es gibt keinen Ort an der Community und keinen
--     brauchbaren am Konto (siehe Teil 1). Ein Kilometerregler ohne
--     Koordinaten waere geraten.
--
-- SECURITY INVOKER: die Sichtbarkeit ergibt sich vollstaendig aus den
-- Zeilenregeln von communities und community_members. Als SECURITY DEFINER
-- muesste die Funktion sie nachbauen — und jede Abweichung waere ein Leck.
-- Deshalb sind unten auch alle Spalten EINZELN aufgezaehlt: ein `c.*` faellt
-- mit 42501 aus, weil communities.founder_id fuer `authenticated` bewusst
-- kein Leserecht hat.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.get_communities_gefiltert(
  p_bereich      text    default 'entdecken',
  p_fahrzeugart  text    default null,
  p_region_code  text    default null,
  p_suche        text    default null,
  p_sortierung   text    default 'aktiv',
  p_limit        integer default 40,
  p_offset       integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid            uuid    := (select auth.uid());
  v_bereich        text    := coalesce(nullif(btrim(p_bereich), ''), 'entdecken');
  v_sortierung     text    := coalesce(nullif(btrim(p_sortierung), ''), 'aktiv');
  v_fahrzeugart    text    := nullif(btrim(coalesce(p_fahrzeugart, '')), '');
  v_region         text    := nullif(btrim(coalesce(p_region_code, '')), '');
  v_region_land    text;
  v_region_istland boolean := false;
  v_suche          text    := nullif(btrim(coalesce(p_suche, '')), '');
  v_muster         text;
  v_limit          integer := least(greatest(coalesce(p_limit, 40), 1), 100);
  v_offset         integer := greatest(coalesce(p_offset, 0), 0);
  v_liste          jsonb;
begin
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if v_bereich not in ('entdecken', 'meine') then
    raise exception 'Unbekannter Bereich: %. Erlaubt: entdecken, meine.', v_bereich;
  end if;

  if v_sortierung not in ('aktiv', 'gross', 'neu') then
    raise exception 'Unbekannte Sortierung: %. Erlaubt: aktiv, gross, neu.', v_sortierung;
  end if;

  -- 'both' als Filterwert heisst dasselbe wie „egal": eine gemischte
  -- Community ist fuer Autofahrer UND Motorradfahrer gedacht, ein eigener
  -- Punkt „nur gemischte" waere ein Regler ohne Zweck.
  if v_fahrzeugart is not null and v_fahrzeugart not in ('car', 'motorcycle', 'both') then
    raise exception
      'Unbekannte Fahrzeugart: %. Erlaubt: car, motorcycle, both.', v_fahrzeugart;
  end if;
  if v_fahrzeugart = 'both' then
    v_fahrzeugart := null;
  end if;

  if v_region is not null then
    select r.land_code, r.ist_land
      into v_region_land, v_region_istland
    from public.community_regionen r
    where r.code = v_region;

    if not found then
      raise exception 'Unbekannte Region: %.', v_region;
    end if;
  end if;

  -- Suchtext: %, _ und \ sind in LIKE Sonderzeichen. Ohne Maskierung faende
  -- die Eingabe „%" jede Community und „_" jede mit mindestens einem
  -- Zeichen — der Nutzer hat aber nach einem Prozentzeichen gesucht.
  if v_suche is not null then
    v_muster := '%' || replace(replace(replace(v_suche, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with sichtbar as (
    select
      c.id,
      c.owner_id,
      c.name,
      c.description,
      c.is_public,
      c.created_at,
      c.updated_at,
      c.owner_only_messages,
      c.avatar_url,
      c.fahrzeugart,
      c.region_code,
      r.name       as region_name,
      r.land_code  as land_code,
      pin.position as pin_position,
      (select count(*)
         from public.community_members m
        where m.community_id = c.id)                    as mitglieder_anzahl,
      (select max(msg.created_at)
         from public.community_messages msg
        where msg.community_id = c.id
          and msg.deleted_at is null)                   as letzte_aktivitaet,
      (select m2.role
         from public.community_members m2
        where m2.community_id = c.id
          and m2.user_id = v_uid)                       as meine_rolle
    from public.communities c
    left join public.community_regionen r on r.code = c.region_code
    left join public.community_pins pin
           on pin.community_id = c.id and pin.user_id = v_uid
    where
      -- Bereich
      (
        case
          when v_bereich = 'meine' then
            exists (select 1 from public.community_members m
                     where m.community_id = c.id and m.user_id = v_uid)
          else
            coalesce(c.is_public, false)
            and c.owner_id <> v_uid
            and not exists (select 1 from public.community_members m
                             where m.community_id = c.id and m.user_id = v_uid)
        end
      )
      -- Blockierte: bisher hat NUR der Client das gefiltert
      -- (getDiscoverCommunities). Serverseitig ist es jetzt dicht.
      and not exists (
        select 1 from public.blocked_user_ids() b where b.user_id = c.owner_id
      )
      -- Fahrzeugart: „Auto" schliesst „offen fuer alle" mit ein.
      and (v_fahrzeugart is null or c.fahrzeugart in (v_fahrzeugart, 'both'))
      -- Region: NULL ist ueberregional und faellt nie heraus; die Hierarchie
      -- Land <-> Bundesland wirkt in beide Richtungen.
      and (
        v_region is null
        or c.region_code is null
        or c.region_code = v_region
        or (v_region_istland and r.land_code = v_region)
        or (not v_region_istland and c.region_code = v_region_land)
      )
      -- Suche
      -- ilike, NICHT like: gemessen am 24.08. hiess die Community
      -- „Opel-Crew" — eine Suche nach „opel" fand sie mit `like` nicht.
      and (
        v_muster is null
        or c.name ilike v_muster escape '\'
        or coalesce(c.description, '') ilike v_muster escape '\'
      )
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',                  s.id,
        'owner_id',            s.owner_id,
        'name',                s.name,
        'description',         s.description,
        'is_public',           s.is_public,
        'created_at',          s.created_at,
        'updated_at',          s.updated_at,
        'owner_only_messages', s.owner_only_messages,
        'avatar_url',          s.avatar_url,
        'fahrzeugart',         s.fahrzeugart,
        'region_code',         s.region_code,
        'region_name',         s.region_name,
        'land_code',           s.land_code,
        'mitglieder_anzahl',   s.mitglieder_anzahl,
        'letzte_aktivitaet',   s.letzte_aktivitaet,
        'angepinnt',           s.pin_position is not null,
        'pin_position',        s.pin_position,
        'meine_rolle',         s.meine_rolle,
        'ist_mitglied',        s.meine_rolle is not null,
        -- Formgleich mit `profiles:owner_id(id, username, avatar_url)` aus
        -- _communitySelect, damit der Client dieselbe Auswertung benutzen
        -- kann wie bei der bisherigen Abfrage.
        'profiles', (
          select jsonb_build_object(
            'id', pr.id, 'username', pr.username, 'avatar_url', pr.avatar_url)
          from public.profiles pr where pr.id = s.owner_id
        ),
        -- Ebenso formgleich mit `community_members(user_id, role)`. Der
        -- Client entscheidet damit heute schon ueber isCurrentUserMember.
        'community_members', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'user_id', m.user_id, 'role', m.role)), '[]'::jsonb)
          from public.community_members m where m.community_id = s.id
        )
      )
      order by
        -- Angepinntes IMMER zuerst, in der Reihenfolge des Nutzers, und zwar
        -- unabhaengig von der gewaehlten Sortierung. Auch in „Entdecken":
        -- wer eine fremde oeffentliche Community angepinnt hat, will sie oben.
        (s.pin_position is null),
        s.pin_position,
        case when v_sortierung = 'gross' then s.mitglieder_anzahl end desc,
        case when v_sortierung = 'neu'
             then extract(epoch from s.created_at) end desc,
        case when v_sortierung = 'aktiv'
             then extract(epoch from coalesce(s.letzte_aktivitaet, s.created_at)) end desc,
        -- Gleichstand: die juengere zuerst, damit die Reihenfolge stabil ist.
        s.created_at desc,
        s.id
    ),
    '[]'::jsonb
  )
  into v_liste
  from (
    select * from sichtbar
    order by
      (pin_position is null),
      pin_position,
      case when v_sortierung = 'gross' then mitglieder_anzahl end desc,
      case when v_sortierung = 'neu'
           then extract(epoch from created_at) end desc,
      case when v_sortierung = 'aktiv'
           then extract(epoch from coalesce(letzte_aktivitaet, created_at)) end desc,
      created_at desc,
      id
    limit v_limit offset v_offset
  ) s;

  return v_liste;
end;
$function$;

comment on function public.get_communities_gefiltert(text, text, text, text, text, integer, integer) is
  'Community-Liste, serverseitig gefiltert und sortiert. Angepinntes steht '
  'immer oben. p_bereich: entdecken | meine. p_fahrzeugart: car | motorcycle '
  '| both (both = egal). p_region_code: Code aus community_regionen, '
  'ueberregionale Communities fallen nie heraus. p_sortierung: aktiv | gross '
  '| neu.';

revoke all on function public.get_communities_gefiltert(text, text, text, text, text, integer, integer)
  from public, anon;
grant execute on function public.get_communities_gefiltert(text, text, text, text, text, integer, integer)
  to authenticated;


-- ───────────────────────────────────────────────────────────────────────────
-- 5. Der Weg ueber den Einladungscode kennt die neuen Felder auch
--
-- find_community_by_code ist SECURITY DEFINER und laeuft an den
-- Spaltenrechten vorbei — genau deshalb muss sie hier MITGEZOGEN werden,
-- sonst zeigt das Vorschau-Blatt bei einem per Code gefundenen Beitritt
-- weniger an als bei einem aus der Liste. Rein additiv: kein Feld faellt weg,
-- kein Typ aendert sich, alte App-Fassungen lesen weiterhin, was sie kennen.
-- ───────────────────────────────────────────────────────────────────────────

create or replace function public.find_community_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_code text;
  v_community public.communities%rowtype;
  v_member_count integer;
  v_owner jsonb;
  v_region jsonb;
begin
  v_code := public.normalize_community_invite_code(p_code);
  if v_code is null then
    return null;
  end if;

  select * into v_community
  from public.communities
  where upper(invite_code) = upper(v_code);

  if not found then
    return null;
  end if;

  select count(*) into v_member_count
  from public.community_members cm
  where cm.community_id = v_community.id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'avatar_url', p.avatar_url
  )
  into v_owner
  from public.profiles p
  where p.id = v_community.owner_id;

  select jsonb_build_object('code', r.code, 'name', r.name, 'land_code', r.land_code)
  into v_region
  from public.community_regionen r
  where r.code = v_community.region_code;

  return jsonb_build_object(
    'id', v_community.id,
    'owner_id', v_community.owner_id,
    'name', v_community.name,
    'description', v_community.description,
    'is_public', v_community.is_public,
    'owner_only_messages', v_community.owner_only_messages,
    'avatar_url', v_community.avatar_url,
    'invite_code', v_code,
    'created_at', v_community.created_at,
    'member_count', v_member_count,
    'owner_profile', v_owner,
    'fahrzeugart', v_community.fahrzeugart,
    'region_code', v_community.region_code,
    'region_name', v_region ->> 'name',
    'land_code', v_region ->> 'land_code'
  );
end;
$function$;
