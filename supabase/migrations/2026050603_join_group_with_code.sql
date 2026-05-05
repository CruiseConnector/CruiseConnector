-- Invite-code lookup/join path for private groups. Joining by code is allowed
-- only before the route starts; once activated, late joins are rejected with a
-- user-facing message.

create or replace function public.normalize_group_invite_code(p_code text)
returns text
language sql
immutable
set search_path = public
as $$
  with cleaned as (
    select regexp_replace(upper(coalesce(p_code, '')), '[^A-Z0-9]', '', 'g')
      as value
  )
  select case
    when value ~ '^CC[A-Z2-9]{6}$'
      then 'CC-' || substring(value from 3)
    else null
  end
  from cleaned;
$$;

create or replace function public.find_group_by_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text;
  v_group public.groups%rowtype;
  v_members jsonb;
  v_profile jsonb;
begin
  v_code := public.normalize_group_invite_code(p_code);
  if v_code is null then
    return null;
  end if;

  select * into v_group
  from public.groups
  where upper(invite_code) = upper(v_code);

  if not found then
    return null;
  end if;

  select coalesce(
    jsonb_agg(jsonb_build_object('user_id', gm.user_id)),
    '[]'::jsonb
  )
  into v_members
  from public.group_members gm
  where gm.group_id = v_group.id;

  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'email', p.email
  )
  into v_profile
  from public.profiles p
  where p.id = v_group.created_by;

  return jsonb_build_object(
    'id', v_group.id,
    'created_at', v_group.created_at,
    'created_by', v_group.created_by,
    'name', v_group.name,
    'description', v_group.description,
    'route_name', v_group.route_name,
    'stats', v_group.stats,
    'time_location', v_group.time_location,
    'route_data', v_group.route_data,
    'start_location', v_group.start_location,
    'is_public', v_group.is_public,
    'is_active', v_group.is_active,
    'max_people', v_group.max_people,
    'start_time', v_group.start_time,
    'activated_at', v_group.activated_at,
    'invite_code', v_code,
    '_join_code', v_code,
    'group_members', v_members,
    'profiles', v_profile
  );
end;
$$;

create or replace function public.join_group_with_code(p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_group public.groups%rowtype;
  v_uid uuid;
  v_member_count integer;
  v_already_member boolean;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_code := public.normalize_group_invite_code(p_code);
  if v_code is null then
    raise exception 'Code ungueltig.';
  end if;

  select * into v_group
  from public.groups
  where upper(invite_code) = upper(v_code)
  for update;

  if not found then
    raise exception 'Code ungueltig.';
  end if;

  if coalesce(v_group.is_active, false) = true
     or v_group.activated_at is not null then
    raise exception 'Die Session laeuft bereits oder wurde schon beendet.';
  end if;

  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = v_group.id
      and gm.user_id = v_uid
  )
  into v_already_member;

  if v_already_member then
    return v_group.id;
  end if;

  select count(*) into v_member_count
  from public.group_members gm
  where gm.group_id = v_group.id;

  if v_member_count >= v_group.max_people then
    raise exception 'Gruppe voll.';
  end if;

  insert into public.group_members (group_id, user_id, role, ride_role)
  values (v_group.id, v_uid, 'passenger', 'passenger')
  on conflict (group_id, user_id) do nothing;

  return v_group.id;
end;
$$;

revoke all on function public.normalize_group_invite_code(text) from public;
revoke all on function public.find_group_by_code(text) from public;
revoke all on function public.join_group_with_code(text) from public;

grant execute on function public.normalize_group_invite_code(text)
  to anon, authenticated;
grant execute on function public.find_group_by_code(text)
  to authenticated;
grant execute on function public.join_group_with_code(text)
  to authenticated;

notify pgrst, 'reload schema';
