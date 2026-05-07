drop policy if exists "User sieht eigene Notifications" on public.notifications;
create policy "User sieht eigene Notifications"
on public.notifications
for select
to authenticated
using (
  (select auth.uid()) = user_id
  and (
    from_user_id is null
    or not public.is_blocked_pair(user_id, from_user_id)
  )
);

drop policy if exists "System kann Notifications erstellen" on public.notifications;
create policy "System kann Notifications erstellen"
on public.notifications
for insert
to authenticated
with check (
  from_user_id is null
  or not public.is_blocked_pair(user_id, from_user_id)
);
