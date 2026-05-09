drop policy if exists "System kann Notifications erstellen" on public.notifications;
create policy "System kann Notifications erstellen"
on public.notifications
for insert
to authenticated
with check (
  from_user_id = (select auth.uid())
  and user_id <> (select auth.uid())
  and not public.is_blocked_pair(user_id, from_user_id)
);
