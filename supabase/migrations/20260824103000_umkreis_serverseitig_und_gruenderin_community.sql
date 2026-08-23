-- 2026-08-24 - Zwei Befunde, eine Migration.
--
-- ============================================================================
-- TEIL A - Aufgabe 3.1: Der Umkreisfilter filtert einen Ausschnitt, der schon
--                       falsch zusammengestellt wurde.
-- ============================================================================
--
-- Vucko, Norddeutschland-Beispiel: "der 50-km-Filter zeigt nichts, obwohl es
-- Treffer gaebe."
--
-- Der Regler selbst ist in Ordnung. Er sitzt in community_page.dart (10 bis
-- 100 km, Haken fuer "alle", Fallback ohne Position blendet nichts aus). Der
-- Fehler sitzt eine Ebene tiefer, in
-- lib/data/services/social_service.dart:1834-1873 (getDiscoverGroups):
--
--     .limit(80)          <- Server liefert 80 Gruppen, entfernungsblind
--     ...
--     .take(40)           <- Client schneidet auf 40, entfernungsblind
--
-- Erst DANACH laeuft der Umkreisfilter. Solange es weniger als 80 offene
-- Gruppen gibt, faellt das nicht auf. Sobald es mehr sind, entscheidet die
-- Zufallsreihenfolge des Servers, welche 80 der Client ueberhaupt zu sehen
-- bekommt - und die Gruppe 20 km entfernt kann darunter fehlen.
--
-- GEMESSEN am 24.08. (Gegenprobe mit 100 fiktiven Gruppen, 95 davon in
-- Norddeutschland und frisch angelegt, 5 im Umkreis von 50 km um Bregenz und
-- aelter, kein Schreibzugriff):
--     limit(80) zuerst, dann 50-km-Filter  ->  0 Treffer
--     50-km-Filter zuerst                  ->  5 Treffer
-- Der Nutzer sieht "keine Gruppen in deiner Naehe", obwohl fuenf in Reichweite
-- stehen. Genau Vuckos Beispiel.
--
-- LOESUNG: Entfernung filtern und sortieren, BEVOR abgeschnitten wird. Das
-- geht nur auf dem Server, weil nur der Server alle Zeilen sieht.
--
-- Bewusst KEIN SECURITY DEFINER. Die Sichtbarkeitsregel
-- groups_visible_before_live_or_member_or_invited erlaubt das Lesen dieser
-- Gruppen ohnehin (oeffentlich und nicht aktiv). Eine Funktion mit fremden
-- Rechten waere hier ein Recht ohne Anlass.
--
-- Bewusst public.geo_distance_m statt PostGIS. PostGIS 3.3.7 ist installiert
-- und koennte das auch, aber geo_distance_m ist im Projekt der eingefahrene
-- Weg fuer Entfernungen (Meldungs-Umkreis, Ortsnachweis). Zwei Rechenwege fuer
-- dieselbe Groesse driften irgendwann auseinander - das hat uns schon einmal
-- die Laender-Klassifikation gekostet.

create or replace function public.gruppen_in_der_naehe(
  p_lat      double precision default null,
  p_lng      double precision default null,
  p_radius_m double precision default null,
  p_limit    integer          default 40
)
returns table (
  id                   uuid,
  name                 text,
  created_by           uuid,
  is_active            boolean,
  is_public            boolean,
  closed_at            timestamptz,
  start_time           timestamptz,
  start_location       jsonb,
  route_name           text,
  stats                text,
  time_location        text,
  max_people           integer,
  invite_code          text,
  created_at           timestamptz,
  mitglieder_anzahl    integer,
  gastgeber_username   text,
  gastgeber_avatar_url text,
  entfernung_m         double precision
)
language sql
stable
security invoker
set search_path to 'public', 'pg_temp'
as $function$
  with ich as (
    select (select auth.uid()) as uid
  ),
  kandidaten as (
    select
      g.id, g.name, g.created_by, g.is_active, g.is_public, g.closed_at,
      g.start_time, g.start_location, g.route_name, g.stats, g.time_location,
      g.max_people, g.invite_code, g.created_at,
      -- Entfernung nur, wenn BEIDE Seiten wirklich Zahlen liefern. Ohne die
      -- jsonb_typeof-Pruefung wuerde ein kaputtes start_location die ganze
      -- Abfrage mit einem Cast-Fehler abbrechen statt eine Gruppe zu
      -- ueberspringen.
      case
        when p_lat is null or p_lng is null then null
        when jsonb_typeof(g.start_location -> 'lat') <> 'number' then null
        when jsonb_typeof(g.start_location -> 'lng') <> 'number' then null
        else public.geo_distance_m(
               p_lat, p_lng,
               (g.start_location ->> 'lat')::double precision,
               (g.start_location ->> 'lng')::double precision)
      end as entfernung_m
    from public.groups g
    cross join ich
    where coalesce(g.is_public, false) = true
      and coalesce(g.is_active, false) = false
      and g.closed_at is null
      -- Ersetzt _filterExpired im Client. Dort lief die Pruefung ins Leere,
      -- weil activated_at im select von getDiscoverGroups gar nicht mit
      -- geholt wurde und deshalb immer null war.
      and (g.activated_at is null
           or g.activated_at > now() - interval '24 hours')
      -- Eigene Gruppen und Gruppen, in denen ich schon Mitglied bin, raus.
      -- Der Client wirft sie ohnehin weg - nur hat er sie vorher aus dem
      -- Kontingent von 80 bezahlt.
      and g.created_by is distinct from ich.uid
      and not exists (
        select 1 from public.group_members m
         where m.group_id = g.id and m.user_id = ich.uid
      )
      and not exists (
        select 1 from public.blocked_user_ids() b
         where b.user_id = g.created_by
      )
  )
  select
    k.id, k.name, k.created_by, k.is_active, k.is_public, k.closed_at,
    k.start_time, k.start_location, k.route_name, k.stats, k.time_location,
    k.max_people, k.invite_code, k.created_at,
    (select count(*)::int from public.group_members m where m.group_id = k.id),
    p.username,
    p.avatar_url,
    k.entfernung_m
  from kandidaten k
  left join public.profiles p on p.id = k.created_by
  where
    -- Radius "alle": kein Filter, aber weiter nach Entfernung sortiert, damit
    -- der Schnitt bei p_limit die naechsten behaelt statt irgendwelche.
    p_radius_m is null
    -- Nutzer ohne Standort: kein Filter. Nichts ausblenden, was wir nicht
    -- beurteilen koennen.
    or p_lat is null or p_lng is null
    -- Gruppe ohne brauchbares start_location: bleibt drin, aber mit
    -- entfernung_m = null. Sie verschwindet nicht, und sie gilt auch nicht
    -- faelschlich als nah - die Sortierung schiebt sie hinter alle Gruppen
    -- mit bekannter Entfernung, und der Client kann "Entfernung unbekannt"
    -- anschreiben.
    or k.entfernung_m is null
    or k.entfernung_m <= p_radius_m
  order by
    (k.entfernung_m is null),      -- unbekannte Entfernung zuletzt
    k.entfernung_m asc,
    k.start_time asc nulls last,
    k.created_at desc
  limit least(greatest(coalesce(p_limit, 40), 1), 200);
$function$;

comment on function public.gruppen_in_der_naehe(double precision, double precision, double precision, integer) is
  'Offene oeffentliche Gruppen fuer die Entdecken-Liste, serverseitig nach '
  'Entfernung gefiltert und sortiert. p_lat/p_lng null = kein Umkreisfilter, '
  'p_radius_m null = Radius "alle". Gruppen ohne Startpunkt bleiben drin mit '
  'entfernung_m = null. Ersetzt das entfernungsblinde limit(80)/take(40) in '
  'social_service.dart:getDiscoverGroups (2026-08-24).';

revoke execute on function public.gruppen_in_der_naehe(double precision, double precision, double precision, integer) from public;
revoke execute on function public.gruppen_in_der_naehe(double precision, double precision, double precision, integer) from anon;
grant  execute on function public.gruppen_in_der_naehe(double precision, double precision, double precision, integer) to authenticated;

-- Zum Index, ehrlich gerechnet: heute steht EINE Gruppe in der Tabelle.
-- Jeder Index waere hier reine Behauptung - Postgres liest einen Seq Scan
-- ueber eine Seite schneller als jeden Indexeintrag. Ein Index auf die
-- Entfernung ginge ohnehin nicht direkt: geo_distance_m rechnet gegen einen
-- Parameter, das ist nicht indizierbar. Der Weg waere spaeter ein Vorfilter
-- ueber ein Rechteck (generierte lat/lng-Spalten plus btree) oder PostGIS
-- geography mit GiST.
--
-- Schwelle, ab der sich das rechnet: wenn
--   select count(*) from groups
--    where is_public and not is_active and closed_at is null;
-- ueber ein paar tausend steigt. Vorher misst man nur Rauschen. Bis dahin
-- kostet der Seq Scan ueber die offenen Gruppen weniger als die Pflege.

-- ============================================================================
-- TEIL B - Aufgabe 10: Wer hat die Community GEGRUENDET? Die Datenbank konnte
--                      das bisher nicht beantworten.
-- ============================================================================
--
-- Vucko am 24.08.: "dass community ein enzelnes badge bekommen mit
-- gruendungsdatum und man dafuer bei den analytics ein badge bekommt aber nur
-- eins das heisst Gruende eine Community wenn man draufklickt und sonnst nur
-- Community heisst wenn es das nicht schon gibt und wie gesagt ein badge in
-- der community wo man sieht wann es gegruendet wurde."
--
-- Geprueft am 24.08.: es gibt zwei Kandidaten, und BEIDE taugen nicht als
-- Gruendernachweis.
--
-- 1) community_members.role = 'owner' ist NICHT der Gruender, sondern die
--    Admin-Rolle. Die Fehlermeldungen sagen es selbst
--    ("Nur Admins koennen Rollen aendern."). Gemessen: 7 Zeilen mit
--    role='owner' auf 6 Communities. "Has.Crew" hat zwei, und eine davon
--    gehoert einem Nutzer, der nicht communities.owner_id ist. Ueber diese
--    Rolle bekaemen also mehrere Leute je Community das Gruender-Abzeichen.
--
-- 2) communities.owner_id ist NICHT dauerhaft der Gruender, sondern der
--    jeweils erste Admin. Zwei Wege schreiben ihn um:
--      * ensure_community_primary_admin() setzt owner_id auf das aelteste
--        verbliebene Mitglied, sobald der Gruender die Community verlaesst.
--      * Die Regel leaders_update_communities erlaubt JEDEM Admin ein UPDATE
--        auf communities ohne Spalteneinschraenkung - owner_id eingeschlossen.
--    Heute stimmt owner_id noch bei allen 6 Communities mit dem Gruender
--    ueberein (geprueft: die aelteste Zeile in community_members gehoert
--    jedes Mal owner_id, und ihr created_at ist auf die Mikrosekunde
--    communities.created_at). Genau deshalb ist JETZT der richtige Zeitpunkt,
--    den Wert festzuschreiben - in einem halben Jahr waere er verloren.
--
-- Deshalb eine eigene Spalte: founder_id. Wer sie einmal hat, behaelt sie.
-- Das Gruendungsdatum ist communities.created_at, das gab es schon.
alter table public.communities
  add column if not exists founder_id uuid
    references public.profiles(id) on delete set null;

comment on column public.communities.founder_id is
  'Wer diese Community gegruendet hat. SCHREIB-EINMALIG, siehe Trigger '
  'trg_guard_community_founder_id. Nicht zu verwechseln mit owner_id (der '
  'jeweils erste Admin, wird von ensure_community_primary_admin umgesetzt) '
  'und nicht mit community_members.role = owner (das ist die Admin-Rolle, es '
  'gibt mehrere je Community). Gruendungsdatum ist created_at.';

-- Nachzug fuer die 6 Bestands-Communities. Zulaessig, weil oben geprueft:
-- owner_id ist bei allen 6 noch der Gruender.
update public.communities
   set founder_id = owner_id
 where founder_id is null;

-- SECURITY INVOKER mit Absicht: die Funktion liest nur OLD/NEW und auth.uid()
-- und braucht keine fremden Rechte. Als SECURITY DEFINER wuerde der
-- Supabase-Advisor sie zu Recht als per RPC aufrufbar melden
-- (anon_security_definer_function_executable) - dieselbe Falle wie bei
-- guard_starter_bonus_ende am 19.08.
create or replace function public.guard_community_founder_id()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $function$
begin
  if tg_op = 'INSERT' then
    -- Aus der App kommend zaehlt ausschliesslich, wer die Zeile anlegt. Die
    -- Regel users_create_own_communities erzwingt owner_id = auth.uid(),
    -- also ist owner_id hier der Gruender. Ein mitgeschicktes founder_id
    -- wird verworfen, sonst koennte sich jeder die Gruendung fremder
    -- Communities anschreiben.
    if auth.uid() is not null then
      new.founder_id := new.owner_id;
    elsif new.founder_id is null then
      new.founder_id := new.owner_id;
    end if;
    return new;
  end if;

  -- UPDATE: einmal gesetzt, nie wieder geaendert. Weder durch einen zweiten
  -- Admin noch durch ensure_community_primary_admin. Serverjobs und Support
  -- (auth.uid() is null, service_role) bleiben aussen vor, damit ein Fehler
  -- noch korrigierbar ist.
  if auth.uid() is not null
     and old.founder_id is not null
     and new.founder_id is distinct from old.founder_id
  then
    new.founder_id := old.founder_id;
  end if;

  if new.founder_id is null then
    new.founder_id := old.founder_id;
  end if;

  return new;
end;
$function$;

revoke execute on function public.guard_community_founder_id() from public;
revoke execute on function public.guard_community_founder_id() from anon;

drop trigger if exists trg_guard_community_founder_id on public.communities;
create trigger trg_guard_community_founder_id
  before insert or update on public.communities
  for each row
  execute function public.guard_community_founder_id();

-- Ein Nutzer fragt hoechstens nach seiner eigenen Gruendung, deshalb eine
-- Abfrage statt einer Liste. Sie liefert gleich das Datum mit, damit der
-- Client fuer Abzeichen und Anzeige nicht zweimal fragen muss.
--
-- SECURITY DEFINER hier mit Grund: die Sichtbarkeitsregel
-- communities_visible_public_or_member zeigt eine private Community nur
-- Mitgliedern und owner_id. Wer eine private Community gegruendet und spaeter
-- verlassen hat, saehe seine eigene Gruendung nicht mehr - und verloere das
-- Abzeichen wieder. Die Funktion liest ausschliesslich Zeilen mit
-- founder_id = auth.uid(), gibt also nichts preis, was nicht dem Aufrufer
-- selbst gehoert.
create or replace function public.meine_community_gruendung()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'gegruendet',        count(*) > 0,
    'anzahl',            count(*),
    'erste_gruendung',   min(c.created_at),
    'erste_community_id', (
      select c2.id from public.communities c2
       where c2.founder_id = (select auth.uid())
       order by c2.created_at asc limit 1
    ),
    'erster_name', (
      select c2.name from public.communities c2
       where c2.founder_id = (select auth.uid())
       order by c2.created_at asc limit 1
    )
  )
  from public.communities c
  where c.founder_id = (select auth.uid());
$function$;

comment on function public.meine_community_gruendung() is
  'Hat der angemeldete Nutzer je eine Community gegruendet, und wann die '
  'erste? Grundlage fuer das einmalige Gruender-Abzeichen. gegruendet ist '
  'false, wenn niemand angemeldet ist.';

revoke execute on function public.meine_community_gruendung() from public;
revoke execute on function public.meine_community_gruendung() from anon;
grant  execute on function public.meine_community_gruendung() to authenticated;

-- Das Abzeichen selbst wird BEWUSST NICHT hier vergeben. Die Datenbank liefert
-- die Wahrheit, der Client vergibt - so wie bei badge_15 und badge_16 auch.
-- Ein Trigger, der profiles.badges beschreibt, muesste eine Badge-ID in SQL
-- hartkodieren; dann gaebe es wieder zwei Listen, die auseinanderlaufen
-- koennen. Genau diese Fehlerklasse hat die Migration vom 18.08.
-- (badge_whitelist_ohne_pflege) abgeschafft. Sicher ist das Vergeben im
-- Client trotzdem: trg_preserve_profile_badges vereinigt alte und neue Liste,
-- ein einmal verdientes Abzeichen kann also nicht mehr verloren gehen.

-- Ein Index, und zwar nur dieser eine. Der Unterschied zu Teil A ist nicht
-- Willkuer: dort filtert die Abfrage ueber eine gerechnete Entfernung gegen
-- einen Parameter, das ist mit einem btree gar nicht indizierbar. Hier ist es
-- eine schlichte Gleichheit auf einer Spalte - genau das, was
-- meine_community_gruendung() bei JEDEM Abzeichen-Abgleich fragt, und genau
-- der Index, den der Fremdschluessel ohnehin haben will (der Advisor meldet
-- ihn sonst als unindexed_foreign_keys). Bei heute 6 Zeilen bringt er nichts,
-- er kostet aber auch nichts, und die Abfrage laeuft je Nutzer und Start.
create index if not exists communities_founder_idx
  on public.communities (founder_id);
