alter table public.profiles
  drop constraint if exists profiles_username_not_empty;

alter table public.profiles
  drop constraint if exists profiles_username_format;

alter table public.profiles
  add constraint profiles_username_format
  check (
    username is not null
    and char_length(username) between 3 and 20
    and username ~ '^[A-Za-z0-9_]+$'
  ) not valid;

alter table public.profiles validate constraint profiles_username_format;

alter table public.posts
  drop constraint if exists posts_content_length;

alter table public.posts
  add constraint posts_content_length
  check (char_length(coalesce(content, '')) between 1 and 1000) not valid;

alter table public.comments
  drop constraint if exists comments_content_length;

alter table public.comments
  add constraint comments_content_length
  check (char_length(coalesce(content, '')) between 1 and 1000) not valid;

alter table public.comments validate constraint comments_content_length;

alter table public.profiles
  drop constraint if exists profiles_bio_title_length;

alter table public.profiles
  add constraint profiles_bio_title_length
  check (bio_title is null or char_length(bio_title) <= 40) not valid;

alter table public.profiles validate constraint profiles_bio_title_length;

alter table public.profiles
  drop constraint if exists profiles_bio_length;

alter table public.profiles
  add constraint profiles_bio_length
  check (bio is null or char_length(bio) <= 500) not valid;

alter table public.profiles validate constraint profiles_bio_length;

alter table public.profiles
  drop constraint if exists profiles_link_length;

alter table public.profiles
  add constraint profiles_link_length
  check (link is null or char_length(link) <= 200) not valid;

alter table public.profiles validate constraint profiles_link_length;

alter table public.profiles
  drop constraint if exists profiles_car_brand_length;

alter table public.profiles
  add constraint profiles_car_brand_length
  check (car_brand is null or char_length(car_brand) <= 32) not valid;

alter table public.profiles validate constraint profiles_car_brand_length;

alter table public.profiles
  drop constraint if exists profiles_car_name_length;

alter table public.profiles
  add constraint profiles_car_name_length
  check (car_name is null or char_length(car_name) <= 32) not valid;

alter table public.profiles validate constraint profiles_car_name_length;

alter table public.groups
  drop constraint if exists groups_name_length;

alter table public.groups
  add constraint groups_name_length
  check (char_length(coalesce(name, '')) between 1 and 50) not valid;

alter table public.groups validate constraint groups_name_length;

alter table public.groups
  drop constraint if exists groups_description_length;

alter table public.groups
  add constraint groups_description_length
  check (description is null or char_length(description) <= 300) not valid;

alter table public.groups validate constraint groups_description_length;

alter table public.groups
  drop constraint if exists groups_route_name_length;

alter table public.groups
  add constraint groups_route_name_length
  check (route_name is null or char_length(route_name) <= 80) not valid;

alter table public.groups validate constraint groups_route_name_length;

alter table public.groups
  drop constraint if exists groups_stats_length;

alter table public.groups
  add constraint groups_stats_length
  check (stats is null or char_length(stats) <= 120) not valid;

alter table public.groups validate constraint groups_stats_length;

alter table public.groups
  drop constraint if exists groups_time_location_length;

alter table public.groups
  add constraint groups_time_location_length
  check (time_location is null or char_length(time_location) <= 160) not valid;

alter table public.groups validate constraint groups_time_location_length;

alter table public.routes
  drop constraint if exists routes_name_length;

alter table public.routes
  add constraint routes_name_length
  check (name is null or char_length(name) <= 60) not valid;

alter table public.routes validate constraint routes_name_length;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_brand_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_brand_length
  check (brand is null or char_length(brand) <= 32) not valid;

alter table public.profile_vehicles validate constraint profile_vehicles_brand_length;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_model_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_model_length
  check (model is null or char_length(model) <= 32) not valid;

alter table public.profile_vehicles validate constraint profile_vehicles_model_length;

alter table public.profile_vehicles
  drop constraint if exists profile_vehicles_drivetrain_length;

alter table public.profile_vehicles
  add constraint profile_vehicles_drivetrain_length
  check (drivetrain is null or char_length(drivetrain) <= 12) not valid;

alter table public.profile_vehicles validate constraint profile_vehicles_drivetrain_length;
