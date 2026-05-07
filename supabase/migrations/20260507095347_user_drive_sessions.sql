-- Immutable drive sessions are the authoritative source for XP, driven km,
-- route count, and level progress. Saved routes can be deleted without
-- touching these records.

alter table public.profiles
  add column if not exists level int default 1,
  add column if not exists total_km double precision default 0,
  add column if not exists total_routes int default 0,
  add column if not exists total_xp int default 0;

update public.profiles
set
  level = coalesce(level, 1),
  total_km = coalesce(total_km, 0),
  total_routes = coalesce(total_routes, 0),
  total_xp = coalesce(total_xp, 0);

alter table public.profiles
  alter column level set default 1,
  alter column total_km set default 0,
  alter column total_routes set default 0,
  alter column total_xp set default 0,
  alter column total_xp set not null;

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

create table if not exists public.user_drive_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  route_id uuid references public.routes(id) on delete set null,
  distance_km numeric(10, 3) not null check (distance_km >= 0),
  duration_seconds int not null default 0 check (duration_seconds >= 0),
  xp_awarded int not null check (xp_awarded >= 0),
  completed_at_end boolean not null default false,
  route_style text,
  route_type text,
  route_fingerprint text,
  source text not null default 'navigation',
  created_at timestamptz not null default now()
);

create index if not exists idx_user_drive_sessions_user_created
  on public.user_drive_sessions (user_id, created_at desc);

create index if not exists idx_user_drive_sessions_route_id
  on public.user_drive_sessions (route_id)
  where route_id is not null;

create index if not exists idx_user_drive_sessions_fingerprint
  on public.user_drive_sessions (user_id, route_fingerprint)
  where route_fingerprint is not null;

alter table public.user_drive_sessions enable row level security;

drop policy if exists "Users read own drive sessions"
  on public.user_drive_sessions;
create policy "Users read own drive sessions"
  on public.user_drive_sessions
  for select
  using (auth.uid() = user_id);

drop policy if exists "Users insert own drive sessions"
  on public.user_drive_sessions;
create policy "Users insert own drive sessions"
  on public.user_drive_sessions
  for insert
  with check (auth.uid() = user_id);

grant select, insert on public.user_drive_sessions to authenticated;

create or replace function private.level_for_xp(total_xp int)
returns int
language sql
immutable
as $$
  select case
    when greatest(total_xp, 0) >= 25000
      then least(100, 12 + floor((greatest(total_xp, 0) - 25000) / 10000.0)::int)
    when greatest(total_xp, 0) >= 18000 then 11
    when greatest(total_xp, 0) >= 13000 then 10
    when greatest(total_xp, 0) >= 9000 then 9
    when greatest(total_xp, 0) >= 6000 then 8
    when greatest(total_xp, 0) >= 4000 then 7
    when greatest(total_xp, 0) >= 2500 then 6
    when greatest(total_xp, 0) >= 1500 then 5
    when greatest(total_xp, 0) >= 800 then 4
    when greatest(total_xp, 0) >= 350 then 3
    when greatest(total_xp, 0) >= 100 then 2
    else 1
  end;
$$;

create or replace function private.recalculate_profile_drive_totals(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  totals record;
begin
  select
    coalesce(sum(distance_km), 0)::double precision as total_km,
    coalesce(sum(xp_awarded), 0)::int as total_xp,
    count(*)::int as total_routes
  into totals
  from public.user_drive_sessions
  where user_id = target_user_id;

  update public.profiles
  set
    total_km = totals.total_km,
    total_xp = totals.total_xp,
    total_routes = totals.total_routes,
    level = private.level_for_xp(totals.total_xp)
  where id = target_user_id;
end;
$$;

create or replace function private.handle_user_drive_session_insert()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.recalculate_profile_drive_totals(new.user_id);
  return new;
end;
$$;

drop trigger if exists trg_user_drive_sessions_sync_profile
  on public.user_drive_sessions;
create trigger trg_user_drive_sessions_sync_profile
  after insert on public.user_drive_sessions
  for each row
  execute function private.handle_user_drive_session_insert();
