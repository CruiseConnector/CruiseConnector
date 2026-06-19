-- Allow the front-most active group participant to publish the canonical route.
-- Before a ride is active, route updates stay restricted to owner/driver roles.

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
            g.is_active = true
            or gm.role = 'owner'
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
