-- Fix recursive group_members policies by moving owner checks into a
-- SECURITY DEFINER helper. The group creator is always treated as an owner
-- for permissions, even if the visible member role is managed separately.

create or replace function public.is_group_owner(
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
    and (
      exists (
        select 1
        from public.groups g
        where g.id = p_group_id
          and g.created_by = p_user_id
      )
      or exists (
        select 1
        from public.group_members gm
        where gm.group_id = p_group_id
          and gm.user_id = p_user_id
          and gm.role = 'owner'
      )
    );
$$;

revoke all on function public.is_group_owner(uuid, uuid) from public;
grant execute on function public.is_group_owner(uuid, uuid)
  to anon, authenticated;

drop policy if exists "Owner kann Gruppe updaten" on public.groups;
create policy "Owner kann Gruppe updaten"
  on public.groups for update
  using (public.is_group_owner(id, auth.uid()))
  with check (public.is_group_owner(id, auth.uid()));

drop policy if exists "Member kann sich updaten" on public.group_members;
create policy "Member kann sich updaten"
  on public.group_members for update
  using (
    auth.uid() = user_id
    or public.is_group_owner(group_id, auth.uid())
  )
  with check (
    auth.uid() = user_id
    or public.is_group_owner(group_id, auth.uid())
  );

drop policy if exists "Owner kann Mitglieder entfernen" on public.group_members;
create policy "Owner kann Mitglieder entfernen"
  on public.group_members for delete
  using (
    auth.uid() = user_id
    or public.is_group_owner(group_id, auth.uid())
  );

drop policy if exists "Owner sieht Requests seiner Gruppe"
  on public.group_join_requests;
create policy "Owner sieht Requests seiner Gruppe"
  on public.group_join_requests for select
  using (public.is_group_owner(group_id, auth.uid()));

drop policy if exists "Owner updated Requests seiner Gruppe"
  on public.group_join_requests;
create policy "Owner updated Requests seiner Gruppe"
  on public.group_join_requests for update
  using (public.is_group_owner(group_id, auth.uid()))
  with check (public.is_group_owner(group_id, auth.uid()));

create or replace function public.accept_group_join_request(req_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.group_join_requests%rowtype;
begin
  select * into rec
  from public.group_join_requests
  where id = req_id
  for update;

  if not found then
    raise exception 'request not found';
  end if;

  if rec.status <> 'pending' then
    raise exception 'request is not pending';
  end if;

  if not public.is_group_owner(rec.group_id, auth.uid()) then
    raise exception 'only owner may accept requests';
  end if;

  insert into public.group_members (group_id, user_id, role, ride_role)
  values (rec.group_id, rec.user_id, 'passenger', 'passenger')
  on conflict (group_id, user_id) do nothing;

  update public.group_join_requests
     set status = 'accepted', responded_at = now()
   where id = req_id;
end;
$$;

create or replace function public.reject_group_join_request(req_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.group_join_requests%rowtype;
begin
  select * into rec
  from public.group_join_requests
  where id = req_id
  for update;

  if not found then
    raise exception 'request not found';
  end if;

  if not public.is_group_owner(rec.group_id, auth.uid()) then
    raise exception 'only owner may reject requests';
  end if;

  update public.group_join_requests
     set status = 'rejected', responded_at = now()
   where id = req_id
     and status = 'pending';
end;
$$;

grant execute on function public.accept_group_join_request(uuid)
  to authenticated;
grant execute on function public.reject_group_join_request(uuid)
  to authenticated;

notify pgrst, 'reload schema';
