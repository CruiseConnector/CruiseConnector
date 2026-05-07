alter table public.groups
  drop constraint if exists groups_name_length;

alter table public.groups
  add constraint groups_name_length
  check (char_length(coalesce(name, '')) between 1 and 25) not valid;
