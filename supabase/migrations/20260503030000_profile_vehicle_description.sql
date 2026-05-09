-- Optional short description shown on the vehicle garage card.

alter table public.profile_vehicles
  add column if not exists description text;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_description_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_description_length
  check (description is null or char_length(description) <= 500);
