-- Active group route updates must come from a current client that already
-- passed the local "front-most vehicle" guard. This blocks older active
-- clients from overwriting the canonical group route with a diverging reroute.

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
  v_publish_meta jsonb := p_route_data -> 'route_publish';
  v_publisher_progress_meters double precision;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_route_data is null or jsonb_typeof(p_route_data) <> 'object' then
    raise exception 'invalid_route_data';
  end if;

  if jsonb_typeof(v_publish_meta) = 'object'
     and (v_publish_meta ->> 'publisher_progress_meters') ~ '^[0-9]+(\.[0-9]+)?$' then
    v_publisher_progress_meters :=
      (v_publish_meta ->> 'publisher_progress_meters')::double precision;
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
            (
              g.is_active = true
              and jsonb_typeof(v_publish_meta) = 'object'
              and lower(coalesce(v_publish_meta ->> 'is_leading_vehicle', 'false'))
                in ('true', 't', '1', 'yes')
              and v_publisher_progress_meters is not null
              and v_publisher_progress_meters >= 0
            )
            or (
              coalesce(g.is_active, false) = false
              and (
                gm.role = 'owner'
                or gm.role = 'driver'
                or gm.ride_role = 'driver'
              )
            )
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
