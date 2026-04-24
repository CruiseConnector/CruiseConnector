-- 24h-Auto-Delete für Gruppen, deren Route gestartet wurde.
-- Owner kann Gruppe jederzeit manuell löschen (siehe deleteGroup im Client).
-- Nach activated_at + 24h räumt pg_cron die Gruppe ab.

create extension if not exists pg_cron;

create or replace function public.cleanup_expired_cruise_groups()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.groups
  where activated_at is not null
    and activated_at < now() - interval '24 hours';
end;
$$;

-- Stündlich laufen lassen; idempotent via unschedule-first.
do $$
begin
  perform cron.unschedule('cruise_groups_cleanup');
exception when others then
  null;
end;
$$;

select cron.schedule(
  'cruise_groups_cleanup',
  '0 * * * *',
  $$select public.cleanup_expired_cruise_groups();$$
);
