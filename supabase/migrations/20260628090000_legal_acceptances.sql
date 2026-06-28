-- Versioned legal acceptance/audit trail for Terms and Privacy notices.
-- Users can insert and read only their own records. Existing records are
-- append-only from the client side so old acceptances remain auditable.

create table if not exists public.legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text,
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  privacy_version text not null,
  privacy_acknowledged_at timestamptz not null,
  legal_locale text not null default 'de-AT',
  legal_source text not null,
  app_version text,
  platform text,
  acceptance_ip inet,
  user_agent text,
  device_info jsonb not null default '{}'::jsonb,
  constraint legal_acceptances_terms_version_not_empty check (
    length(trim(terms_version)) > 0
  ),
  constraint legal_acceptances_privacy_version_not_empty check (
    length(trim(privacy_version)) > 0
  ),
  constraint legal_acceptances_source_not_empty check (
    length(trim(legal_source)) > 0
  )
);

alter table public.legal_acceptances enable row level security;

drop policy if exists "Users can read own legal acceptances"
  on public.legal_acceptances;
create policy "Users can read own legal acceptances"
  on public.legal_acceptances
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert own legal acceptances"
  on public.legal_acceptances;
create policy "Users can insert own legal acceptances"
  on public.legal_acceptances
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

revoke all on public.legal_acceptances from anon;
grant select, insert on public.legal_acceptances to authenticated;

create index if not exists idx_legal_acceptances_user_created
  on public.legal_acceptances (user_id, created_at desc);

create index if not exists idx_legal_acceptances_user_versions
  on public.legal_acceptances (user_id, terms_version, privacy_version);

create or replace function public.record_initial_legal_acceptance()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_terms_version text := nullif(trim(new.raw_user_meta_data->>'terms_version'), '');
  v_terms_accepted_at timestamptz;
  v_privacy_version text := nullif(trim(new.raw_user_meta_data->>'privacy_version'), '');
  v_privacy_acknowledged_at timestamptz;
  v_legal_locale text := coalesce(
    nullif(trim(new.raw_user_meta_data->>'legal_locale'), ''),
    'de-AT'
  );
  v_legal_source text := coalesce(
    nullif(trim(new.raw_user_meta_data->>'legal_source'), ''),
    'app_onboarding'
  );
  v_app_version text := nullif(trim(new.raw_user_meta_data->>'app_version'), '');
  v_platform text := nullif(trim(new.raw_user_meta_data->>'platform'), '');
begin
  if v_terms_version is null or v_privacy_version is null then
    return new;
  end if;

  begin
    v_terms_accepted_at :=
      (new.raw_user_meta_data->>'terms_accepted_at')::timestamptz;
  exception when others then
    v_terms_accepted_at := now();
  end;

  begin
    v_privacy_acknowledged_at :=
      (new.raw_user_meta_data->>'privacy_acknowledged_at')::timestamptz;
  exception when others then
    v_privacy_acknowledged_at := now();
  end;

  insert into public.legal_acceptances (
    user_id,
    email,
    terms_version,
    terms_accepted_at,
    privacy_version,
    privacy_acknowledged_at,
    legal_locale,
    legal_source,
    app_version,
    platform
  )
  values (
    new.id,
    new.email,
    v_terms_version,
    v_terms_accepted_at,
    v_privacy_version,
    v_privacy_acknowledged_at,
    v_legal_locale,
    v_legal_source,
    v_app_version,
    v_platform
  );

  return new;
exception
  when others then
    raise warning 'record_initial_legal_acceptance failed for auth user %: %',
      new.id,
      sqlerrm;
    return new;
end;
$$;

revoke all on function public.record_initial_legal_acceptance() from public;

drop trigger if exists on_auth_user_legal_acceptance on auth.users;
create trigger on_auth_user_legal_acceptance
  after insert on auth.users
  for each row execute function public.record_initial_legal_acceptance();
