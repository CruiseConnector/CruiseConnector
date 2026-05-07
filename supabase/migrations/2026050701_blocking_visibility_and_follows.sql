create or replace function public.is_blocked_pair(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.user_blocks ub
     where (ub.blocker_id = left_user and ub.blocked_id = right_user)
        or (ub.blocker_id = right_user and ub.blocked_id = left_user)
  );
$$;

create or replace function public.is_blocked_either_way(other uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_blocked_pair((select auth.uid()), other);
$$;

create or replace function public.block_relationship(other uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  i_blocked boolean;
  blocked_me boolean;
begin
  if uid is null or other is null then
    return 'none';
  end if;

  select exists (
    select 1 from public.user_blocks
     where blocker_id = uid and blocked_id = other
  ) into i_blocked;

  select exists (
    select 1 from public.user_blocks
     where blocker_id = other and blocked_id = uid
  ) into blocked_me;

  if i_blocked and blocked_me then
    return 'mutual';
  elsif i_blocked then
    return 'blocked_by_me';
  elsif blocked_me then
    return 'blocked_me';
  end if;

  return 'none';
end;
$$;

create or replace function public.blocked_user_ids()
returns table(user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select case
           when ub.blocker_id = (select auth.uid()) then ub.blocked_id
           else ub.blocker_id
         end as user_id
    from public.user_blocks ub
   where ub.blocker_id = (select auth.uid())
      or ub.blocked_id = (select auth.uid());
$$;

create or replace function public.block_user(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if uid = target then
    raise exception 'cannot block yourself';
  end if;

  insert into public.user_blocks(blocker_id, blocked_id)
  values (uid, target)
  on conflict do nothing;

  delete from public.follows
   where (follower_id = uid and following_id = target)
      or (follower_id = target and following_id = uid);

  delete from public.notifications
   where (user_id = uid and from_user_id = target)
      or (user_id = target and from_user_id = uid);
end;
$$;

create or replace function public.unblock_user(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from public.user_blocks
   where blocker_id = uid and blocked_id = target;
end;
$$;

drop policy if exists "Profile sind öffentlich lesbar" on public.profiles;
drop policy if exists "Profile sind fuer nicht blockierte Nutzer lesbar" on public.profiles;
create policy "Profile sind fuer nicht blockierte Nutzer lesbar"
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
  or not public.is_blocked_either_way(id)
);

drop policy if exists "User kann folgen" on public.follows;
create policy "User kann folgen"
on public.follows
for insert
to authenticated
with check (
  (select auth.uid()) = follower_id
  and not public.is_blocked_either_way(following_id)
);

drop policy if exists "Profilinhaber kann Follow-Anfragen annehmen" on public.follows;
create policy "Profilinhaber kann Follow-Anfragen annehmen"
on public.follows
for update
to authenticated
using (
  (select auth.uid()) = following_id
  and status = 'pending'
  and not public.is_blocked_either_way(follower_id)
)
with check (
  (select auth.uid()) = following_id
  and status = 'accepted'
  and not public.is_blocked_either_way(follower_id)
);

grant execute on function public.block_relationship(uuid) to authenticated;
grant execute on function public.blocked_user_ids() to authenticated;
