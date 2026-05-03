alter table public.profiles
  add column if not exists bio_title text;

alter table public.profiles
  drop constraint if exists profiles_bio_title_length;

alter table public.profiles
  add constraint profiles_bio_title_length
  check (bio_title is null or char_length(bio_title) <= 40);

alter table public.profile_vehicles
  add column if not exists drivetrain text,
  add column if not exists zero_to_hundred_seconds numeric(3, 1);

alter table public.profile_vehicles
  alter column zero_to_hundred_seconds type numeric(3, 1)
  using zero_to_hundred_seconds::numeric(3, 1);

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_highlight_length;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_description_title_length;

alter table public.profile_vehicles
  drop column if exists highlight,
  drop column if exists description_title;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_drivetrain_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_drivetrain_length
  check (drivetrain is null or char_length(drivetrain) <= 12);

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_zero_to_hundred_seconds_range;

alter table public.profile_vehicles
  add constraint profile_vehicles_zero_to_hundred_seconds_range
  check (
    zero_to_hundred_seconds is null
    or (zero_to_hundred_seconds >= 0 and zero_to_hundred_seconds < 100)
  );
