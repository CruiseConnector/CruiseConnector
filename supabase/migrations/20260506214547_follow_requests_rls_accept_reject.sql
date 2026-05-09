drop policy if exists "User kann eigene Follows updaten" on public.follows;
drop policy if exists "Profilinhaber kann Follow-Anfragen annehmen" on public.follows;
drop policy if exists "Profilinhaber kann Follow-Anfragen ablehnen" on public.follows;

revoke update on public.follows from anon, authenticated;
grant update(status) on public.follows to authenticated;

create policy "Profilinhaber kann Follow-Anfragen annehmen"
on public.follows
for update
to authenticated
using ((select auth.uid()) = following_id and status = 'pending')
with check ((select auth.uid()) = following_id and status = 'accepted');

create policy "Profilinhaber kann Follow-Anfragen ablehnen"
on public.follows
for delete
to authenticated
using ((select auth.uid()) = following_id and status = 'pending');
