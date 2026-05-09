-- Country code shown on the CruiserConnect car card.
-- Nullable for old profiles; the Flutter UI defaults to AT when no value is set.

alter table public.profiles
  add column if not exists car_country_code text;

alter table public.profiles
  drop constraint if exists profiles_car_country_code_format;

alter table public.profiles
  add constraint profiles_car_country_code_format
  check (
    car_country_code is null
    or car_country_code ~ '^[A-Z]{2,3}$'
  );
