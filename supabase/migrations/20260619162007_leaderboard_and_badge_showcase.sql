alter table public.profiles
  add column if not exists badge_showcase jsonb not null default '[]'::jsonb;

update public.profiles
set badge_showcase = '[]'::jsonb
where badge_showcase is null;

create schema if not exists private;

create or replace function private.badge_showcase_entry_id(entry_json jsonb)
returns text
language sql
immutable
as $$
  select trim(
    coalesce(
      case
        when jsonb_typeof(entry_json) = 'object' then entry_json->>'id'
        when jsonb_typeof(entry_json) = 'string' then entry_json#>>'{}'
        else ''
      end,
      ''
    )
  );
$$;

create or replace function private.badge_showcase_has_unique_nonempty_ids(
  input_json jsonb
)
returns boolean
language sql
immutable
as $$
  select case
    when input_json is null then true
    when jsonb_typeof(input_json) <> 'array' then false
    else (
      select count(*) = count(distinct private.badge_showcase_entry_id(elem))
      from jsonb_array_elements(input_json) as elements(elem)
      where private.badge_showcase_entry_id(elem) <> ''
    )
  end;
$$;

update public.profiles p
set badge_showcase = coalesce(
  (
    select jsonb_agg(elem order by first_ord)
    from (
      select elem, first_ord
      from (
        select distinct on (badge_id)
          case
            when jsonb_typeof(raw_elem) = 'object' then raw_elem
            else jsonb_build_object('id', badge_id)
          end as elem,
          badge_id,
          ord as first_ord
        from (
          select
            item.elem as raw_elem,
            private.badge_showcase_entry_id(item.elem) as badge_id,
            item.ord
          from jsonb_array_elements(
            case
              when jsonb_typeof(p.badge_showcase) = 'array'
                then p.badge_showcase
              else '[]'::jsonb
            end
          ) with ordinality as item(elem, ord)
        ) entries
        where badge_id <> ''
        order by badge_id, ord
      ) deduped
      order by first_ord
      limit 5
    ) unique_badges
  ),
  '[]'::jsonb
);

alter table public.profiles
  drop constraint if exists profiles_badge_showcase_shape;

alter table public.profiles
  add constraint profiles_badge_showcase_shape
  check (
    jsonb_typeof(badge_showcase) = 'array'
    and jsonb_array_length(badge_showcase) <= 5
    and private.badge_showcase_has_unique_nonempty_ids(badge_showcase)
  );

create table if not exists public.user_distance_leaderboard (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  all_time_km double precision not null default 0 check (all_time_km >= 0),
  week_start date not null default date_trunc('week', now())::date,
  week_km double precision not null default 0 check (week_km >= 0),
  month_start date not null default date_trunc('month', now())::date,
  month_km double precision not null default 0 check (month_km >= 0),
  route_count int not null default 0 check (route_count >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists idx_user_distance_leaderboard_all_time
  on public.user_distance_leaderboard (all_time_km desc);

create index if not exists idx_user_distance_leaderboard_week
  on public.user_distance_leaderboard (week_start, week_km desc);

create index if not exists idx_user_distance_leaderboard_month
  on public.user_distance_leaderboard (month_start, month_km desc);

alter table public.user_distance_leaderboard enable row level security;

drop policy if exists "distance leaderboard public read"
  on public.user_distance_leaderboard;
create policy "distance leaderboard public read"
  on public.user_distance_leaderboard
  for select
  using (true);

grant select on public.user_distance_leaderboard to anon, authenticated;

create or replace function private.recalculate_user_distance_leaderboard(
  target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  current_week_start date := date_trunc('week', now())::date;
  current_month_start date := date_trunc('month', now())::date;
  totals record;
begin
  select
    coalesce(sum(distance_km), 0)::double precision as all_time_km,
    coalesce(
      sum(distance_km) filter (
        where created_at >= current_week_start::timestamptz
          and created_at < (current_week_start + interval '7 days')::timestamptz
      ),
      0
    )::double precision as week_km,
    coalesce(
      sum(distance_km) filter (
        where created_at >= current_month_start::timestamptz
          and created_at < (current_month_start + interval '1 month')::timestamptz
      ),
      0
    )::double precision as month_km,
    count(*)::int as route_count
  into totals
  from public.user_drive_sessions
  where user_id = target_user_id;

  insert into public.user_distance_leaderboard (
    user_id,
    all_time_km,
    week_start,
    week_km,
    month_start,
    month_km,
    route_count,
    updated_at
  )
  values (
    target_user_id,
    coalesce(totals.all_time_km, 0),
    current_week_start,
    coalesce(totals.week_km, 0),
    current_month_start,
    coalesce(totals.month_km, 0),
    coalesce(totals.route_count, 0),
    now()
  )
  on conflict (user_id) do update
  set
    all_time_km = excluded.all_time_km,
    week_start = excluded.week_start,
    week_km = excluded.week_km,
    month_start = excluded.month_start,
    month_km = excluded.month_km,
    route_count = excluded.route_count,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function private.handle_user_distance_leaderboard_session()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  perform private.recalculate_user_distance_leaderboard(new.user_id);
  return new;
end;
$$;

drop trigger if exists zz_trg_user_drive_sessions_sync_leaderboard
  on public.user_drive_sessions;
create trigger zz_trg_user_drive_sessions_sync_leaderboard
  after insert on public.user_drive_sessions
  for each row
  execute function private.handle_user_distance_leaderboard_session();

insert into public.user_distance_leaderboard (
  user_id,
  all_time_km,
  week_start,
  week_km,
  month_start,
  month_km,
  route_count,
  updated_at
)
select
  p.id,
  coalesce(sum(s.distance_km), p.total_km, 0)::double precision,
  date_trunc('week', now())::date,
  coalesce(
    sum(s.distance_km) filter (
      where s.created_at >= date_trunc('week', now())
        and s.created_at < date_trunc('week', now()) + interval '7 days'
    ),
    0
  )::double precision,
  date_trunc('month', now())::date,
  coalesce(
    sum(s.distance_km) filter (
      where s.created_at >= date_trunc('month', now())
        and s.created_at < date_trunc('month', now()) + interval '1 month'
    ),
    0
  )::double precision,
  case
    when count(s.id) > 0 then count(s.id)::int
    else coalesce(p.total_routes, 0)
  end,
  now()
from public.profiles p
left join public.user_drive_sessions s on s.user_id = p.id
group by p.id, p.total_km, p.total_routes
on conflict (user_id) do update
set
  all_time_km = excluded.all_time_km,
  week_start = excluded.week_start,
  week_km = excluded.week_km,
  month_start = excluded.month_start,
  month_km = excluded.month_km,
  route_count = excluded.route_count,
  updated_at = excluded.updated_at;
