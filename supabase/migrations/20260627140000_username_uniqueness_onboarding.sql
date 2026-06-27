-- 2026-06-27 (vucko): Task 2 — global eindeutige @-Namen + server-seitiger,
-- manipulationssicherer 30-Tage-Lock + Onboarding-Felder. LIVE per MCP angewandt;
-- diese Datei spiegelt den Stand (idempotent re-applybar).

alter table public.profiles
  add column if not exists display_name text,
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists country_code text,
  add column if not exists region text,
  add column if not exists app_language text;

update public.profiles set display_name = coalesce(display_name, username)
  where display_name is null;
update public.profiles set onboarding_completed = true
  where onboarding_completed = false and created_at < now();

drop index if exists public.idx_profiles_username;
create unique index if not exists ux_profiles_username_lower
  on public.profiles (lower(username))
  where username is not null and btrim(username) <> '';

create table if not exists public.reserved_usernames (name text primary key);
insert into public.reserved_usernames(name) values
  ('admin'),('administrator'),('support'),('help'),('mod'),('moderator'),
  ('cruiseconnect'),('cruiseconnector'),('cruise'),('team'),('official'),
  ('root'),('system'),('api'),('null'),('undefined'),('me'),('you'),
  ('settings'),('profile'),('user'),('users'),('account')
on conflict do nothing;
alter table public.reserved_usernames enable row level security;

create or replace function public.is_valid_username_format(p text)
returns boolean language sql immutable as $$
  select p ~ '^[A-Za-z0-9_]{3,20}$' and p !~ '__' and p !~ '^_' and p !~ '_$';
$$;

create or replace function public.username_available(p_username text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_clean text := btrim(coalesce(p_username,''));
begin
  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('available', false, 'reason', 'invalid_format');
  end if;
  if exists (select 1 from public.reserved_usernames where name = lower(v_clean)) then
    return jsonb_build_object('available', false, 'reason', 'reserved');
  end if;
  if exists (select 1 from public.profiles
             where lower(username) = lower(v_clean) and (v_uid is null or id <> v_uid)) then
    return jsonb_build_object('available', false, 'reason', 'taken');
  end if;
  return jsonb_build_object('available', true, 'reason', 'ok');
end; $$;

create or replace function public.username_change_status()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_last timestamptz; v_next timestamptz;
begin
  if v_uid is null then return jsonb_build_object('can_change', false); end if;
  select username_changed_at into v_last from public.profiles where id = v_uid;
  if v_last is null then
    return jsonb_build_object('can_change', true, 'next_change_at', null, 'days_remaining', 0);
  end if;
  v_next := v_last + interval '30 days';
  return jsonb_build_object('can_change', now() >= v_next, 'next_change_at', v_next,
    'days_remaining', greatest(0, ceil(extract(epoch from (v_next - now())) / 86400.0))::int);
end; $$;

create or replace function public.set_username(p_username text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); v_clean text := btrim(coalesce(p_username,''));
        v_last timestamptz; v_next timestamptz; v_days int;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'error', 'not_authenticated'); end if;
  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('ok', false, 'error', 'invalid_format'); end if;
  if exists (select 1 from public.reserved_usernames where name = lower(v_clean)) then
    return jsonb_build_object('ok', false, 'error', 'reserved'); end if;
  select username_changed_at into v_last from public.profiles where id = v_uid;
  if v_last is not null then
    v_next := v_last + interval '30 days';
    if now() < v_next then
      v_days := greatest(0, ceil(extract(epoch from (v_next - now())) / 86400.0))::int;
      return jsonb_build_object('ok', false, 'error', 'too_soon', 'next_change_at', v_next, 'days_remaining', v_days);
    end if;
  end if;
  if exists (select 1 from public.profiles where lower(username) = lower(v_clean) and id <> v_uid) then
    return jsonb_build_object('ok', false, 'error', 'taken'); end if;
  perform set_config('app.username_change_ok', '1', true);
  update public.profiles set username = v_clean, username_changed_at = now() where id = v_uid;
  return jsonb_build_object('ok', true, 'username', v_clean,
    'next_change_at', now() + interval '30 days', 'days_remaining', 30);
exception when unique_violation then
  return jsonb_build_object('ok', false, 'error', 'taken');
end; $$;

-- Guard: blockt JEDE Username-Änderung ohne Durchlass-Flag (= nicht via set_username)
create or replace function public.guard_username_change()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is not null
     and (new.username is distinct from old.username
       or new.username_changed_at is distinct from old.username_changed_at)
     and coalesce(current_setting('app.username_change_ok', true), '') <> '1'
  then
    new.username := old.username;
    new.username_changed_at := old.username_changed_at;
  end if;
  return new;
end; $$;
drop trigger if exists trg_guard_username_change on public.profiles;
create trigger trg_guard_username_change before update on public.profiles
  for each row execute function public.guard_username_change();

revoke execute on function public.set_username(text) from public, anon;
revoke execute on function public.username_change_status() from public, anon;
grant execute on function public.set_username(text) to authenticated;
grant execute on function public.username_available(text) to authenticated, anon;
grant execute on function public.username_change_status() to authenticated;
