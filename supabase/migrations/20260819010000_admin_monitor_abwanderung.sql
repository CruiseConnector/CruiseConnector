-- 2026-08-19 (Vucko nachts): "wie viele schon abgesprungen sind von der app
-- oder sie deinstalliert haben?"
--
-- EHRLICH VORWEG: Eine Deinstallation ist von hier aus NICHT direkt messbar.
-- Weder Apple noch Google melden sie, und eine geloeschte App kann sich nicht
-- abmelden. Der beste verfuegbare Anhaltspunkt ist ein Geraete-Token, das sich
-- lange nicht mehr gemeldet hat. Ein stilles Geraet kann eine Deinstallation
-- sein, genauso aber ein ausgeschaltetes Handy oder jemand, der die App
-- laenger nicht oeffnet. Deshalb heissen die Felder "geraete_still" und nicht
-- "deinstalliert".
--
-- Was dagegen HART gemessen ist: wer sich registriert und nie eine einzige
-- Fahrt gemacht hat. Das ist die eigentliche Abwanderung. Stand 19.08.:
-- 139 von 151 Profilen, also 92 Prozent.
create or replace function public.admin_monitor_abwanderung()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  with fahrten as (
    select user_id, min(created_at) as erste, max(created_at) as letzte,
           count(*) as anzahl
    from public.user_drive_sessions
    group by user_id
  ),
  geraete as (
    select user_id,
           max(coalesce(last_seen_at, updated_at, created_at)) as gesehen
    from public.user_device_tokens
    group by user_id
  ),
  basis as (
    select p.id, p.created_at, f.letzte, f.anzahl, g.gesehen
    from public.profiles p
    left join fahrten f on f.user_id = p.id
    left join geraete g on g.user_id = p.id
  ),
  kennzahlen as (
    select
      count(*) as gesamt,
      count(*) filter (where anzahl is null) as nie_gefahren,
      count(*) filter (where anzahl = 1) as eine_fahrt,
      count(*) filter (where created_at < now() - interval '7 days'
                         and coalesce(letzte, created_at) < now() - interval '7 days')
        as inaktiv_7d,
      count(*) filter (where created_at < now() - interval '30 days'
                         and coalesce(letzte, created_at) < now() - interval '30 days')
        as inaktiv_30d,
      count(*) filter (where gesehen < now() - interval '7 days') as geraete_still_7d,
      count(*) filter (where gesehen < now() - interval '30 days') as geraete_still_30d,
      count(*) filter (where gesehen is null) as ohne_geraet
    from basis
  ),
  wochen as (
    select
      to_char(date_trunc('week', created_at), 'YYYY-MM-DD') as ab,
      count(*)::int as neu,
      count(letzte)::int as gefahren,
      round(100.0 * count(letzte) / greatest(count(*), 1))::int as prozent,
      count(*) filter (where letzte > now() - interval '14 days')::int as noch_aktiv,
      date_trunc('week', created_at) as sortier
    from basis
    group by date_trunc('week', created_at)
    order by date_trunc('week', created_at) desc
    limit 12
  )
  select jsonb_build_object(
    'gesamt', k.gesamt,
    'nie_gefahren', k.nie_gefahren,
    'eine_fahrt', k.eine_fahrt,
    'inaktiv_7d', k.inaktiv_7d,
    'inaktiv_30d', k.inaktiv_30d,
    'geraete_still_7d', k.geraete_still_7d,
    'geraete_still_30d', k.geraete_still_30d,
    'ohne_geraet', k.ohne_geraet,
    'wochen', coalesce(
      (select jsonb_agg(jsonb_build_object(
         'ab', w.ab, 'neu', w.neu, 'gefahren', w.gefahren,
         'prozent', w.prozent, 'noch_aktiv', w.noch_aktiv
       ) order by w.sortier desc) from wochen w),
      '[]'::jsonb)
  )
  from kennzahlen k;
$function$;

-- Nur der Service-Role-Key der Monitoring-Edge ruft das auf. Kein Zugriff
-- fuer angemeldete Nutzer oder anonym: die Zahlen sind Betriebsdaten.
revoke all on function public.admin_monitor_abwanderung() from public;
revoke all on function public.admin_monitor_abwanderung() from anon;
revoke all on function public.admin_monitor_abwanderung() from authenticated;
