-- Canonical route state for active group rides.
-- The original route_data remains the planned route; current_route_data is the
-- live source of truth that can advance through driver/owner reroutes.

alter table public.groups
  add column if not exists current_route_data jsonb,
  add column if not exists route_revision bigint not null default 1,
  add column if not exists route_updated_by uuid references auth.users(id) on delete set null,
  add column if not exists route_updated_at timestamptz;

update public.groups
set
  current_route_data = coalesce(current_route_data, route_data),
  route_updated_by = coalesce(route_updated_by, created_by),
  route_updated_at = coalesce(route_updated_at, activated_at, created_at, now())
where current_route_data is null
   or route_updated_by is null
   or route_updated_at is null;

create index if not exists idx_groups_route_revision
  on public.groups(id, route_revision);

create or replace function public.update_group_current_route(
  p_group_id uuid,
  p_expected_revision bigint,
  p_route_data jsonb
)
returns table(new_route_revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_route_data is null or jsonb_typeof(p_route_data) <> 'object' then
    raise exception 'invalid_route_data';
  end if;

  return query
  with updated as (
    update public.groups as g
    set
      current_route_data = p_route_data,
      route_revision = g.route_revision + 1,
      route_updated_by = v_user_id,
      route_updated_at = now()
    where g.id = p_group_id
      and g.route_revision = p_expected_revision
      and exists (
        select 1
        from public.group_members gm
        where gm.group_id = g.id
          and gm.user_id = v_user_id
          and (
            gm.role = 'owner'
            or gm.role = 'driver'
            or gm.ride_role = 'driver'
          )
      )
    returning g.route_revision, g.route_updated_at
  )
  select
    updated.route_revision,
    updated.route_updated_at
  from updated;
end;
$$;

revoke all on function public.update_group_current_route(uuid, bigint, jsonb)
  from public;
grant execute on function public.update_group_current_route(uuid, bigint, jsonb)
  to authenticated;
