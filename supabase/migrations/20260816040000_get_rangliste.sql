-- 2026-08-16 (vucko Testfahrt T6): Rangliste fuer das Home-Widget.
-- Top-N nach gefahrenen Kilometern im Zeitraum (Woche/Monat, Wiener Zeit)
-- PLUS die eigene Zeile mit Rang, auch wenn sie nicht in den Top-N liegt.
-- SECURITY DEFINER, weil user_drive_sessions per RLS nur die eigenen Zeilen
-- zeigt; herausgegeben werden nur Username, Avatar und Summen — keine
-- Sessions, keine Tracks.
create or replace function public.get_rangliste(
  p_zeitraum text default 'woche',
  p_limit integer default 3
)
returns table(
  rang bigint,
  user_id uuid,
  username text,
  avatar_url text,
  distance_km double precision,
  xp bigint,
  session_count bigint,
  is_me boolean
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with grenze as (
    select case
      when p_zeitraum = 'monat'
        then date_trunc('month', now() at time zone 'Europe/Vienna')
      else date_trunc('week', now() at time zone 'Europe/Vienna')
    end as ab_lokal
  ),
  summen as (
    select
      s.user_id,
      coalesce(sum(s.distance_km), 0)::double precision as distance_km,
      coalesce(sum(s.xp_awarded), 0)::bigint as xp,
      count(*)::bigint as session_count
    from public.user_drive_sessions s, grenze g
    where s.distance_km > 0
      and (s.created_at at time zone 'Europe/Vienna') >= g.ab_lokal
    group by s.user_id
  ),
  gereiht as (
    select
      row_number() over (order by su.distance_km desc, su.xp desc, su.user_id asc) as rang,
      su.user_id,
      p.username,
      p.avatar_url,
      su.distance_km,
      su.xp,
      su.session_count,
      (su.user_id = auth.uid()) as is_me
    from summen su
    join public.profiles p on p.id = su.user_id
    where p.username is not null and length(trim(p.username)) > 0
  )
  select * from gereiht
  where rang <= greatest(1, least(coalesce(p_limit, 3), 50)) or is_me
  order by rang;
$$;

revoke all on function public.get_rangliste(text, integer) from public;
grant execute on function public.get_rangliste(text, integer) to authenticated;
