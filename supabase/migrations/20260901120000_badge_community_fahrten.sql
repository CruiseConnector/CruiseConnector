-- 2026-09-01 — Neue Badge-Familie "Fahrten mit der Community" (badge_74 bis
-- badge_76) aus der Figma-Serie.
--
-- Kriterium laut Board: beendete Gruppenfahrten, bei denen mindestens ein
-- Mitfahrer aus einer der eigenen Communities stammt.
--
-- WARUM SERVERSEITIG: Der Client kennt die Mitgliederlisten fremder
-- Communities nicht und darf sie auch nicht kennen. Er koennte die Zahl also
-- gar nicht ehrlich bilden. Ausserdem gilt dieselbe Regel wie beim Heimatland:
-- eine Zahl, die ein Abzeichen freischaltet, gehoert nicht in die Hand einer
-- alten App-Fassung.
--
-- KEIN PARAMETER, mit Absicht. Die erste Fassung hatte einen `p_user uuid`
-- zum Pruefen. Der Advisor hat danach zu Recht angeschlagen: die Funktion war
-- auch fuer `anon` ausfuehrbar, und mit dem Parameter haette ein nicht
-- angemeldeter Aufrufer die Zahl eines beliebigen anderen Nutzers abfragen
-- koennen. Wer fragt, steht jetzt allein im Anmelde-Token.
--
-- EHRLICHER BEFUND ZUR DATENLAGE, gemessen am 01.09.: In
-- user_drive_sessions ist group_id bei ALLEN 257 Zeilen leer. Auch die
-- bestehende Gruppenfahrten-Familie (badge_04, badge_19, badge_37) kann
-- deshalb derzeit nicht ausloesen; zwei Profile tragen badge_04 noch aus
-- frueherer Zeit. Diese Funktion ist richtig, liefert heute aber fuer jeden 0,
-- bis die Gruppen-Kennung beim Abschluss einer Fahrt wieder mitgeschrieben
-- wird. Das ist ein eigener Defekt und wird getrennt gemeldet.

create or replace function public.badge_community_fahrten()
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  with ich as (
    select auth.uid() as id
  ),
  meine_communities as (
    select cm.community_id
    from public.community_members cm, ich
    where ich.id is not null and cm.user_id = ich.id
  ),
  meine_leute as (
    select distinct cm.user_id
    from public.community_members cm
    join meine_communities mc on mc.community_id = cm.community_id
    where cm.user_id is distinct from (select id from ich)
  )
  select count(distinct s.id)::int
  from public.user_drive_sessions s, ich
  where ich.id is not null
    and s.user_id = ich.id
    and s.completed_at_end
    and s.group_id is not null
    and exists (
      select 1
      from public.group_members gm
      join meine_leute ml on ml.user_id = gm.user_id
      where gm.group_id = s.group_id
    );
$$;

comment on function public.badge_community_fahrten() is
  'Beendete Gruppenfahrten des ANGEMELDETEN Nutzers mit mindestens einem '
  'Mitfahrer aus einer eigenen Community. Grundlage fuer badge_74 bis '
  'badge_76. Nimmt bewusst keinen Parameter: wer fragt, steht im Token.';

revoke all on function public.badge_community_fahrten() from public;
revoke all on function public.badge_community_fahrten() from anon;
grant execute on function public.badge_community_fahrten() to authenticated, service_role;
