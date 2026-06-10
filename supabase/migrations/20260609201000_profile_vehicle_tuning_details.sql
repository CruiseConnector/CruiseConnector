-- Optional tuning / modification notes for garage vehicle cards.

alter table public.profile_vehicles
  add column if not exists tuning_details text;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_tuning_details_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_tuning_details_length
  check (
    tuning_details is null
    or char_length(tuning_details) <= 500
  );

notify pgrst, 'reload schema';
