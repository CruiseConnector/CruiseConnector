-- Nachweis fuer die Migration 20260828184838 (Fehler 10 der Meldungen vom
-- 28.08.): Abstimm-Stufen je Meldungsart.
--
-- Erwartung:
--   stau      + 1x dismiss -> active = false  (sofort weg)
--   unfall    + 1x dismiss -> active = false  (sofort weg)
--   baustelle + 1x dismiss -> active = true   (bleibt, bis die gewichtete
--                                              Mehrfach-Bestaetigung greift)
--
-- Am 28.08. gegen die Produktion gelaufen (in einer Transaktion mit
-- Rollback); Ergebnis exakt wie erwartet, dismissed_count jeweils 1.
--
-- Das Skript ist selbstaufraeumend: alles zwischen begin und rollback
-- verschwindet wieder, inklusive der Stimme und der votes_total-Erhoehung
-- in road_reporter_stats.

begin;

create temporary table _t on commit drop as
  select p.id as voter from public.profiles p
   where coalesce(p.is_banned, false) = false
   limit 1;

insert into public.road_incidents (id, type, lat, lng, reported_by, expires_at, active)
values
  ('00000000-0000-4000-8000-00000000aa01', 'stau',      47.5, 9.7, null, now() + interval '1 hour', true),
  ('00000000-0000-4000-8000-00000000aa02', 'unfall',    47.5, 9.7, null, now() + interval '1 hour', true),
  ('00000000-0000-4000-8000-00000000aa03', 'baustelle', 47.5, 9.7, null, now() + interval '1 hour', true);

-- Als echter, nicht gesperrter Nutzer abstimmen (auth.uid() liest den sub
-- aus request.jwt.claims).
select set_config('request.jwt.claims',
  json_build_object('sub', (select voter from _t), 'role', 'authenticated')::text,
  true);

select public.vote_road_incident('00000000-0000-4000-8000-00000000aa01', 'dismiss');
select public.vote_road_incident('00000000-0000-4000-8000-00000000aa02', 'dismiss');
select public.vote_road_incident('00000000-0000-4000-8000-00000000aa03', 'dismiss');

-- Erwartet: stau false, unfall false, baustelle true.
select id, type, active, dismissed_count
  from public.road_incidents
 where id::text like '00000000-0000-4000-8000-00000000aa%'
 order by id;

rollback;
