create or replace function public.is_blocked_pair(left_user uuid, right_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when (select auth.uid()) is null then false
    when left_user is null or right_user is null then false
    when (select auth.uid()) not in (left_user, right_user) then false
    else exists (
      select 1
        from public.user_blocks ub
       where (ub.blocker_id = left_user and ub.blocked_id = right_user)
          or (ub.blocker_id = right_user and ub.blocked_id = left_user)
    )
  end;
$$;
