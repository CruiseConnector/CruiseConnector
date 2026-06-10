-- Community lifecycle actions:
-- - Members can leave communities.
-- - Admins can delete communities.
-- - If the primary Admin leaves, the earliest remaining member becomes Admin.
-- - If the last member leaves, the community is deleted.

create or replace function public.ensure_community_primary_admin(
  p_community_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_next_admin_id uuid;
begin
  select owner_id into v_owner_id
  from public.communities
  where id = p_community_id
  for update;

  if not found then
    return jsonb_build_object('deleted', true);
  end if;

  if not exists (
    select 1
    from public.community_members cm
    where cm.community_id = p_community_id
  ) then
    delete from public.communities
    where id = p_community_id;

    return jsonb_build_object('deleted', true);
  end if;

  if exists (
    select 1
    from public.community_members cm
    where cm.community_id = p_community_id
      and cm.user_id = v_owner_id
      and cm.role = 'owner'
  ) then
    return jsonb_build_object(
      'deleted', false,
      'admin_id', v_owner_id
    );
  end if;

  select cm.user_id into v_next_admin_id
  from public.community_members cm
  where cm.community_id = p_community_id
  order by cm.created_at asc
  limit 1
  for update;

  update public.community_members
     set role = 'owner'
   where community_id = p_community_id
     and user_id = v_next_admin_id;

  update public.communities
     set owner_id = v_next_admin_id
   where id = p_community_id;

  return jsonb_build_object(
    'deleted', false,
    'admin_id', v_next_admin_id
  );
end;
$$;

create or replace function public.leave_community(
  p_community_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.community_member_role;
begin
  if v_actor_id is null then
    raise exception 'Bitte melde dich an.';
  end if;

  select role into v_actor_role
  from public.community_members
  where community_id = p_community_id
    and user_id = v_actor_id
  for update;

  if not found then
    raise exception 'Du bist kein Mitglied dieser Community.';
  end if;

  delete from public.community_members
  where community_id = p_community_id
    and user_id = v_actor_id;

  return public.ensure_community_primary_admin(p_community_id);
end;
$$;

drop function if exists public.remove_community_member(uuid, uuid);

create or replace function public.remove_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.community_member_role;
  v_target_role public.community_member_role;
begin
  if v_actor_id is null then
    raise exception 'Bitte melde dich an.';
  end if;

  v_actor_role := public.community_member_role_for(p_community_id, v_actor_id);

  select role into v_target_role
  from public.community_members
  where community_id = p_community_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Mitglied nicht gefunden.';
  end if;

  if p_user_id <> v_actor_id then
    if v_actor_role = 'owner' then
      null;
    elsif v_actor_role = 'moderator' and v_target_role = 'member' then
      null;
    else
      raise exception 'Du darfst dieses Mitglied nicht entfernen.';
    end if;
  end if;

  delete from public.community_members
  where community_id = p_community_id
    and user_id = p_user_id;

  return public.ensure_community_primary_admin(p_community_id);
end;
$$;

create or replace function public.delete_community(
  p_community_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Bitte melde dich an.';
  end if;

  if public.community_member_role_for(p_community_id, auth.uid())
    is distinct from 'owner' then
    raise exception 'Nur Admins koennen diese Community loeschen.';
  end if;

  delete from public.communities
  where id = p_community_id;
end;
$$;

drop policy if exists "members_leave_or_leaders_remove" on public.community_members;
drop policy if exists "community_members_delete_via_rpc" on public.community_members;
create policy "community_members_delete_via_rpc"
  on public.community_members for delete
  using (false);

revoke all on function public.ensure_community_primary_admin(uuid) from public;
revoke all on function public.leave_community(uuid) from public;
revoke all on function public.remove_community_member(uuid, uuid) from public;
revoke all on function public.delete_community(uuid) from public;

grant execute on function public.leave_community(uuid) to authenticated;
grant execute on function public.remove_community_member(uuid, uuid) to authenticated;
grant execute on function public.delete_community(uuid) to authenticated;

notify pgrst, 'reload schema';
