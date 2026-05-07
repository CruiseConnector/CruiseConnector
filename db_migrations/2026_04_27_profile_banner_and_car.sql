-- ============================================================================
-- CruiseConnect — Profile-Banner + Auto-Card Erweiterung
-- ============================================================================
-- Diese Migration ergänzt das `profiles`-Table um Banner-URL, Link/Webseite,
-- ein "Top Trumps"-Stil Auto-Profil sowie ein Username-Change-Tracking.
-- Auf Supabase Studio in den SQL-Editor einfügen oder via `supabase db push`
-- deployen. Alle Statements sind idempotent (if not exists) — kann
-- gefahrlos mehrfach ausgeführt werden.
-- ============================================================================

-- 1) Banner-Bild (Storage-URL)
alter table public.profiles
  add column if not exists banner_url text;

-- 1b) Link/Webseite (vom Profil-Editor genutzt)
alter table public.profiles
  add column if not exists link text;

-- 1c) Username-Change-Tracking — Service erlaubt nur 1x pro 30 Tage.
alter table public.profiles
  add column if not exists username_changed_at timestamptz;

-- 2) Auto-Profil — Stammdaten im Ferrari-F8-Spider-Stil.
alter table public.profiles
  add column if not exists car_brand       text,
  add column if not exists car_name        text,    -- Modell-Bezeichnung
  add column if not exists car_top_speed   integer, -- km/h
  add column if not exists car_engine_size numeric(5,1), -- Liter, z.B. 2.3
  add column if not exists car_displacement integer, -- Hubraum in cm^3
  add column if not exists car_cylinders   integer, -- Zylinder-Anzahl
  add column if not exists car_horsepower  integer, -- PS
  add column if not exists car_year        integer, -- Baujahr
  add column if not exists car_first_reg   text,    -- Erstzulassung MM/YYYY
  add column if not exists car_mileage     integer, -- km
  add column if not exists car_image_url   text;
-- Legacy-Spalten (vorherige Version mit Cool Factor / Innovation). Bleiben
-- in der DB, werden vom Code aber nicht mehr gelesen oder geschrieben.
--   car_cool_factor integer
--   car_innovation  integer

-- 3) Storage-Bucket für Banner — public, damit URLs in der App direkt
--    geladen werden können. Existiert er schon: skip.
insert into storage.buckets (id, name, public)
values ('banners', 'banners', true)
on conflict (id) do nothing;

-- 4) RLS-Policies für Banner-Bucket: Owner schreibt, alle lesen.
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'storage'
       and tablename  = 'objects'
       and policyname = 'banners_owner_write'
  ) then
    create policy "banners_owner_write"
      on storage.objects for all
      using  (bucket_id = 'banners' and auth.uid()::text = (storage.foldername(name))[1])
      with check (bucket_id = 'banners' and auth.uid()::text = (storage.foldername(name))[1]);
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname = 'storage'
       and tablename  = 'objects'
       and policyname = 'banners_public_read'
  ) then
    create policy "banners_public_read"
      on storage.objects for select
      using (bucket_id = 'banners');
  end if;
end$$;
