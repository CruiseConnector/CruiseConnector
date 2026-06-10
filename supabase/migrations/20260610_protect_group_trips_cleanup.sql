-- 2026-06-10 (Gruppen-Trip mehrtägig): Der 24h-Cleanup darf Gruppen mit
-- laufendem/pausiertem Trip NICHT löschen — Gruppen-Trips dürfen über mehrere
-- Tage gehen (App-Kill/Neustart-fest) und enden erst bei Zielerreichung oder
-- wenn alle Mitglieder die Gruppe verlassen haben.
-- Anwenden: supabase db push  (oder via SQL-Editor ausführen)
create or replace function public.cleanup_expired_cruise_groups()
returns void
language plpgsql
security definer
as $$
begin
  delete from public.groups g
  where g.activated_at is not null
    and g.activated_at < now() - interval '24 hours'
    and not exists (
      select 1
      from public.trips t
      where t.group_id = g.id
        and t.status in ('active', 'paused')
    );
end;
$$;
