-- Safer community role management for Admin / Moderator / User.

create or replace function public.community_member_role_for(
  p_community_id uuid,
  p_user_id uuid
)
returns public.community_member_role
language sql
stable
security definer
set search_path = public
as $$
  select cm.role
  from public.community_members cm
  where cm.community_id = p_community_id
    and cm.user_id = p_user_id
  limit 1;
$$;

create or replace function public.is_community_admin(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.community_member_role_for(p_community_id, p_user_id) = 'owner';
$$;

create or replace function public.can_moderate_community(
  p_community_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.community_member_role_for(p_community_id, p_user_id)
    in ('owner', 'moderator');
$$;

create or replace function public.set_community_member_role(
  p_community_id uuid,
  p_user_id uuid,
  p_role public.community_member_role
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_role public.community_member_role;
  v_target_role public.community_member_role;
  v_admin_count integer;
begin
  v_actor_role := public.community_member_role_for(p_community_id, auth.uid());
  if v_actor_role is distinct from 'owner' then
    raise exception 'Nur Admins koennen Rollen aendern.';
  end if;

  select role into v_target_role
  from public.community_members
  where community_id = p_community_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Mitglied nicht gefunden.';
  end if;

  select count(*) into v_admin_count
  from public.community_members
  where community_id = p_community_id
    and role = 'owner';

  if v_target_role = 'owner' and p_role <> 'owner' and v_admin_count <= 1 then
    raise exception 'Eine Community braucht mindestens einen Admin.';
  end if;

  update public.community_members
     set role = p_role
   where community_id = p_community_id
     and user_id = p_user_id;
end;
$$;

create or replace function public.remove_community_member(
  p_community_id uuid,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_actor_role public.community_member_role;
  v_target_role public.community_member_role;
  v_admin_count integer;
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

  select count(*) into v_admin_count
  from public.community_members
  where community_id = p_community_id
    and role = 'owner';

  if v_target_role = 'owner' and v_admin_count <= 1 then
    raise exception 'Eine Community braucht mindestens einen Admin.';
  end if;

  delete from public.community_members
  where community_id = p_community_id
    and user_id = p_user_id;
end;
$$;

drop policy if exists "leaders_update_communities" on public.communities;
create policy "leaders_update_communities"
  on public.communities for update
  using (public.is_community_admin(id, auth.uid()))
  with check (public.is_community_admin(id, auth.uid()));

drop policy if exists "leaders_delete_communities" on public.communities;
create policy "leaders_delete_communities"
  on public.communities for delete
  using (public.is_community_admin(id, auth.uid()));

drop policy if exists "users_join_public_communities" on public.community_members;
create policy "users_join_public_communities"
  on public.community_members for insert
  with check (
    role = 'member'
    and (
      (
        user_id = auth.uid()
        and exists (
          select 1 from public.communities c
          where c.id = community_members.community_id
            and coalesce(c.is_public, false) = true
        )
      )
      or public.can_moderate_community(community_id, auth.uid())
    )
  );

drop policy if exists "members_leave_or_leaders_remove" on public.community_members;
create policy "members_leave_or_leaders_remove"
  on public.community_members for delete
  using (
    user_id = auth.uid()
    or public.is_community_admin(community_id, auth.uid())
    or (
      public.community_member_role_for(community_id, auth.uid()) = 'moderator'
      and role = 'member'
    )
  );

drop policy if exists "leaders_update_community_members" on public.community_members;
create policy "leaders_update_community_members"
  on public.community_members for update
  using (public.is_community_admin(community_id, auth.uid()))
  with check (public.is_community_admin(community_id, auth.uid()));

revoke all on function public.community_member_role_for(uuid, uuid) from public;
revoke all on function public.is_community_admin(uuid, uuid) from public;
revoke all on function public.can_moderate_community(uuid, uuid) from public;
revoke all on function public.set_community_member_role(uuid, uuid, public.community_member_role) from public;
revoke all on function public.remove_community_member(uuid, uuid) from public;

grant execute on function public.community_member_role_for(uuid, uuid) to anon, authenticated;
grant execute on function public.is_community_admin(uuid, uuid) to anon, authenticated;
grant execute on function public.can_moderate_community(uuid, uuid) to anon, authenticated;
grant execute on function public.set_community_member_role(uuid, uuid, public.community_member_role) to authenticated;
grant execute on function public.remove_community_member(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
