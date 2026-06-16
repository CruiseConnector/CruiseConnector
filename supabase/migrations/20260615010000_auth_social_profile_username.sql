-- Makes profile creation robust for Google/Apple users. Provider names and
-- email prefixes can contain spaces, dots or umlauts, while profiles.username
-- only allows A-Z, a-z, 0-9 and underscore.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_username text;
  normalized_username text;
begin
  raw_username := coalesce(
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    nullif(trim(new.raw_user_meta_data->>'preferred_username'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'cruiser'
  );

  normalized_username := regexp_replace(raw_username, '[^A-Za-z0-9_]', '_', 'g');
  normalized_username := regexp_replace(normalized_username, '_+', '_', 'g');
  normalized_username := trim(both '_' from normalized_username);
  normalized_username := left(normalized_username, 20);

  if normalized_username is null or char_length(normalized_username) < 3 then
    normalized_username := 'cruiser_' || left(replace(new.id::text, '-', ''), 8);
  end if;

  insert into public.profiles (id, email, username)
  values (new.id, new.email, normalized_username)
  on conflict (id) do nothing;

  return new;
exception
  when others then
    raise warning 'handle_new_user failed for auth user %: %', new.id, sqlerrm;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
