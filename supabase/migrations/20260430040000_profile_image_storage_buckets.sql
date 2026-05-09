-- Storage buckets for profile avatars and car images.
-- Banner storage already exists in older local db_migrations, but is included
-- here as an idempotent safety net for Supabase migration deployments.

insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('car_images', 'car_images', true),
  ('banners', 'banners', true)
on conflict (id) do update
set public = excluded.public;

-- Public read: these URLs are stored on public profiles and rendered directly
-- by Flutter widgets.
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "car_images_public_read" on storage.objects;
create policy "car_images_public_read"
  on storage.objects for select
  using (bucket_id = 'car_images');

drop policy if exists "banners_public_read" on storage.objects;
create policy "banners_public_read"
  on storage.objects for select
  using (bucket_id = 'banners');

-- Owner writes: the app uploads user files under `<auth.uid()>/<filename>`.
drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "car_images_owner_insert" on storage.objects;
create policy "car_images_owner_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'car_images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "car_images_owner_update" on storage.objects;
create policy "car_images_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'car_images'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'car_images'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "banners_owner_insert" on storage.objects;
create policy "banners_owner_insert"
  on storage.objects for insert
  with check (
    bucket_id = 'banners'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "banners_owner_update" on storage.objects;
create policy "banners_owner_update"
  on storage.objects for update
  using (
    bucket_id = 'banners'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'banners'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
