-- X3 Gruppen-Rangliste (2026-06-23, vucko)
-- 1) Drive-Sessions einer Gruppe zuordnen + erreichte Top-Speed mitschreiben.
--    Additiv & nullable -> bricht keine bestehenden Inserts/Reads (Single-Mode
--    schreibt group_id/top_speed_kmh schlicht nicht).
-- 2) Deterministische Rangliste-RPC: aggregiert je Mitglied die Fahrleistung
--    dieser Gruppe. SECURITY DEFINER, damit Mitglieder die Fahrten ihrer
--    Mitfahrer sehen (RLS auf user_drive_sessions ist sonst own-rows-only),
--    aber streng gegated: nur wer selbst Mitglied der Gruppe ist, bekommt
--    Zeilen. Stabile Sortierung (Distanz desc, Top-Speed desc, user_id) ->
--    jeder Client sieht exakt dasselbe Ergebnis.

alter table public.user_drive_sessions
  add column if not exists group_id uuid references public.groups(id) on delete set null,
  add column if not exists top_speed_kmh real;

create index if not exists user_drive_sessions_group_id_idx
  on public.user_drive_sessions (group_id)
  where group_id is not null;

create or replace function public.get_group_leaderboard(p_group_id uuid)
returns table (
  user_id uuid,
  username text,
  avatar_url text,
  total_distance_km double precision,
  max_top_speed_kmh double precision,
  total_duration_seconds bigint,
  session_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.user_id as user_id,
    p.username as username,
    p.avatar_url as avatar_url,
    coalesce(sum(s.distance_km), 0)::double precision as total_distance_km,
    coalesce(max(s.top_speed_kmh), 0)::double precision as max_top_speed_kmh,
    coalesce(sum(s.duration_seconds), 0)::bigint as total_duration_seconds,
    count(*)::bigint as session_count
  from public.user_drive_sessions s
  join public.profiles p on p.id = s.user_id
  where s.group_id = p_group_id
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = p_group_id and gm.user_id = auth.uid()
    )
  group by s.user_id, p.username, p.avatar_url
  order by total_distance_km desc, max_top_speed_kmh desc, user_id asc;
$$;

revoke all on function public.get_group_leaderboard(uuid) from public, anon;
grant execute on function public.get_group_leaderboard(uuid) to authenticated;
