-- Multi-vehicle garage for car and motorcycle riders.
-- Existing single-car profile fields remain as a compatibility fallback.

create table if not exists public.profile_vehicles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_type text not null default 'car'
    check (vehicle_type in ('car', 'motorcycle')),
  brand text,
  model text,
  description text,
  country_code text check (country_code is null or country_code ~ '^[A-Z]{2,3}$'),
  top_speed integer,
  engine_size numeric(5, 1),
  displacement integer,
  cylinders integer,
  horsepower integer,
  year integer,
  first_reg text,
  mileage integer,
  image_url text,
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profile_vehicles enable row level security;

create index if not exists idx_profile_vehicles_user_order
  on public.profile_vehicles (user_id, sort_order, created_at);

drop policy if exists "profile_vehicles_public_read" on public.profile_vehicles;
create policy "profile_vehicles_public_read"
  on public.profile_vehicles for select
  using (true);

drop policy if exists "profile_vehicles_owner_insert" on public.profile_vehicles;
create policy "profile_vehicles_owner_insert"
  on public.profile_vehicles for insert
  with check (auth.uid() = user_id);

drop policy if exists "profile_vehicles_owner_update" on public.profile_vehicles;
create policy "profile_vehicles_owner_update"
  on public.profile_vehicles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "profile_vehicles_owner_delete" on public.profile_vehicles;
create policy "profile_vehicles_owner_delete"
  on public.profile_vehicles for delete
  using (auth.uid() = user_id);

create or replace function public.set_profile_vehicle_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_profile_vehicles_updated_at on public.profile_vehicles;
create trigger trg_profile_vehicles_updated_at
  before update on public.profile_vehicles
  for each row
  execute function public.set_profile_vehicle_updated_at();

-- Backfill the first garage vehicle from legacy profile car fields.
insert into public.profile_vehicles (
  user_id,
  vehicle_type,
  brand,
  model,
  country_code,
  top_speed,
  engine_size,
  displacement,
  cylinders,
  horsepower,
  year,
  first_reg,
  mileage,
  image_url,
  sort_order,
  is_primary
)
select
  p.id,
  'car',
  p.car_brand,
  p.car_name,
  p.car_country_code,
  p.car_top_speed,
  p.car_engine_size,
  p.car_displacement,
  p.car_cylinders,
  p.car_horsepower,
  p.car_year,
  p.car_first_reg,
  p.car_mileage,
  p.car_image_url,
  0,
  true
from public.profiles p
where not exists (
    select 1
    from public.profile_vehicles v
    where v.user_id = p.id
  )
  and (
    nullif(trim(coalesce(p.car_brand, '')), '') is not null
    or nullif(trim(coalesce(p.car_name, '')), '') is not null
    or p.car_top_speed is not null
    or p.car_engine_size is not null
    or p.car_displacement is not null
    or p.car_cylinders is not null
    or p.car_horsepower is not null
    or p.car_year is not null
    or nullif(trim(coalesce(p.car_first_reg, '')), '') is not null
    or p.car_mileage is not null
    or nullif(trim(coalesce(p.car_image_url, '')), '') is not null
  );
