-- Keep private group creation readable for the creator during INSERT
-- RETURNING and allow a safe self-membership fallback if the owner trigger
-- ever has to be bypassed by client code.

insert into public.group_members (group_id, user_id, role, ride_role)
select g.id, g.created_by, 'owner', 'passenger'
from public.groups g
where g.created_by is not null
on conflict (group_id, user_id) do update
set role = 'owner';

create or replace function public.set_owner_on_group_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.group_members (group_id, user_id, role, ride_role)
  values (new.id, new.created_by, 'owner', 'passenger')
  on conflict (group_id, user_id) do update
    set role = 'owner';
  return new;
end;
$$;

drop policy if exists "groups_visible_before_live_or_member" on public.groups;
create policy "groups_visible_before_live_or_member"
  on public.groups for select
  using (
    created_by = auth.uid()
    or (coalesce(is_public, false) = true and coalesce(is_active, false) = false)
    or public.is_group_member(id, auth.uid())
  );

drop policy if exists "group_creator_can_insert_self_membership"
  on public.group_members;
create policy "group_creator_can_insert_self_membership"
  on public.group_members for insert
  with check (
    auth.uid() = user_id
    and public.is_group_owner(group_id, auth.uid())
  );

alter table public.notifications
  drop constraint if exists notifications_type_check;

alter table public.notifications
  add constraint notifications_type_check
  check (
    type in (
      'follow',
      'like',
      'comment',
      'group_invite',
      'repost',
      'mention',
      'group_public_created',
      'group_joined',
      'group_ride_started'
    )
  );

notify pgrst, 'reload schema';
