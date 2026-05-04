-- Social fixes: avatar storage ownership, separate ride roles in groups,
-- and owner moderation actions for group members.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.role() = 'authenticated'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

alter table public.group_members
  add column if not exists ride_role text not null default 'passenger';

alter table public.group_members
  drop constraint if exists group_members_ride_role_check;

alter table public.group_members
  add constraint group_members_ride_role_check
  check (ride_role in ('driver', 'passenger'));

update public.group_members
set ride_role = case
  when role::text = 'driver' then 'driver'
  else 'passenger'
end
where ride_role is null
   or ride_role not in ('driver', 'passenger');

drop policy if exists "Owner kann Mitglieder entfernen" on public.group_members;
create policy "Owner kann Mitglieder entfernen"
  on public.group_members for delete
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = group_members.group_id
        and gm.user_id = auth.uid()
        and gm.role = 'owner'
    )
  );
