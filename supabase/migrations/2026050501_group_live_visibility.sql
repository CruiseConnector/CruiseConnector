-- Live groups are only visible/joinable for users who are already members.
-- Inactive public groups stay discoverable.

insert into public.group_members (group_id, user_id, role, ride_role)
select g.id, g.created_by, 'owner', 'passenger'
from public.groups g
where g.created_by is not null
on conflict (group_id, user_id) do update
set role = 'owner';

create or replace function public.is_group_member(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null
    and exists (
      select 1
      from public.group_members gm
      where gm.group_id = p_group_id
        and gm.user_id = p_user_id
    );
$$;

revoke all on function public.is_group_member(uuid, uuid) from public;
grant execute on function public.is_group_member(uuid, uuid)
  to anon, authenticated;

create or replace function public.can_join_group(
  p_group_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null
    and exists (
      select 1
      from public.groups g
      where g.id = p_group_id
        and coalesce(g.is_active, false) = false
        and (
          coalesce(g.is_public, false) = true
          or exists (
            select 1
            from public.notifications n
            where n.user_id = p_user_id
              and n.reference_id = g.id
              and n.type = 'group_invite'
          )
        )
    );
$$;

revoke all on function public.can_join_group(uuid, uuid) from public;
grant execute on function public.can_join_group(uuid, uuid)
  to authenticated;

do $$
declare
  p record;
begin
  for p in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'groups'
      and cmd = 'SELECT'
  loop
    execute format('drop policy if exists %I on public.groups', p.policyname);
  end loop;
end $$;

create policy "groups_visible_before_live_or_member"
  on public.groups for select
  using (
    (coalesce(is_public, false) = true and coalesce(is_active, false) = false)
    or public.is_group_member(id, auth.uid())
  );

do $$
declare
  p record;
begin
  for p in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'group_members'
      and cmd = 'SELECT'
  loop
    execute format(
      'drop policy if exists %I on public.group_members',
      p.policyname
    );
  end loop;

  for p in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'group_members'
      and cmd = 'INSERT'
  loop
    execute format(
      'drop policy if exists %I on public.group_members',
      p.policyname
    );
  end loop;
end $$;

create policy "group_members_visible_before_live_or_member"
  on public.group_members for select
  using (
    exists (
      select 1
      from public.groups g
      where g.id = group_members.group_id
        and coalesce(g.is_public, false) = true
        and coalesce(g.is_active, false) = false
    )
    or public.is_group_member(group_id, auth.uid())
  );

create policy "users_join_inactive_public_groups"
  on public.group_members for insert
  with check (
    auth.uid() = user_id
    and public.can_join_group(group_id, auth.uid())
  );
