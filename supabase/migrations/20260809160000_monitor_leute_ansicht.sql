-- ═══════════════════════════════════════════════════════════════════════════
-- Monitoring: „Leute" — wer ist dazugekommen, wer ist zuletzt gefahren
--
-- Auftrag Vucko 2026-08-09: „ich moechte sehen, wer dazugekommen ist in die
-- App — nur mit In-App-Name — und wie viele Personen zuletzt gefahren sind,
-- in einer schoenen und klaren und immer geupdateten Ansicht."
--
-- BEWUSST NUR DER IN-APP-NAME: keine E-Mail, keine user_id, kein Standort.
-- Das Dashboard ist ein Betriebswerkzeug, kein Personenverzeichnis — und was
-- hier nicht ausgeliefert wird, kann auch nicht versehentlich weitergegeben
-- werden. Wer keinen Namen gesetzt hat, erscheint als „(ohne Namen)".
--
-- WARUM IM SCHNAPPSCHUSS UND NICHT LIVE: Vuckos Regel „die Datenbank NIE
-- ueberlasten, hoechstens 4 Abfragen in 24 Stunden" gilt auch fuer diese
-- Ansicht. Sie wird viermal taeglich mitgerechnet und danach nur noch gelesen.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.admin_monitor_leute()
returns jsonb
language sql
security definer
set search_path to 'public', 'pg_temp'
stable
as $function$
  with neu as (
    select coalesce(nullif(btrim(p.display_name), ''),
                    nullif(btrim(p.username), ''),
                    '(ohne Namen)') as name,
           p.created_at
      from public.profiles p
     where p.created_at > now() - interval '30 days'
     order by p.created_at desc
     limit 50
  ),
  fahrten as (
    select s.user_id, s.created_at, s.distance_km
      from public.user_drive_sessions s
     where s.created_at > now() - interval '30 days'
  ),
  zuletzt as (
    select coalesce(nullif(btrim(p.display_name), ''),
                    nullif(btrim(p.username), ''),
                    '(ohne Namen)') as name,
           max(f.created_at) as zuletzt,
           count(*)          as fahrten,
           round(sum(f.distance_km)::numeric, 1) as km
      from fahrten f
      left join public.profiles p on p.id = f.user_id
     group by 1
     order by max(f.created_at) desc
     limit 50
  )
  select jsonb_build_object(
    'neue_nutzer', jsonb_build_object(
      'h24',  (select count(*) from public.profiles where created_at > now() - interval '24 hours'),
      'd7',   (select count(*) from public.profiles where created_at > now() - interval '7 days'),
      'd30',  (select count(*) from public.profiles where created_at > now() - interval '30 days'),
      'gesamt',(select count(*) from public.profiles),
      'liste', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'seit', created_at)) from neu), '[]'::jsonb)
    ),
    'gefahren', jsonb_build_object(
      'personen_h24', (select count(distinct user_id) from fahrten where created_at > now() - interval '24 hours'),
      'personen_d7',  (select count(distinct user_id) from fahrten where created_at > now() - interval '7 days'),
      'personen_d30', (select count(distinct user_id) from fahrten),
      'fahrten_h24',  (select count(*) from fahrten where created_at > now() - interval '24 hours'),
      'fahrten_d7',   (select count(*) from fahrten where created_at > now() - interval '7 days'),
      'fahrten_d30',  (select count(*) from fahrten),
      'km_d7',        (select round(coalesce(sum(distance_km),0)::numeric, 1) from fahrten where created_at > now() - interval '7 days'),
      'liste', coalesce((select jsonb_agg(jsonb_build_object(
                          'name', name, 'zuletzt', zuletzt, 'fahrten', fahrten, 'km', km)) from zuletzt), '[]'::jsonb)
    )
  );
$function$;

comment on function public.admin_monitor_leute() is
  'Monitoring: neue Nutzer und zuletzt Gefahrene — ausschliesslich In-App-Name, keine E-Mail, keine ID.';

revoke all on function public.admin_monitor_leute() from public, anon, authenticated;

alter table public.admin_metric_snapshots
  add column if not exists leute jsonb;

create or replace function public.admin_monitor_take_snapshot()
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_slot text := public.monitor_slot_key();
begin
  -- Idempotent: liegt fuer diesen Zeitschlitz schon etwas vor, wird NICHTS
  -- gerechnet. Genau das macht einen versehentlich zu haeufigen Aufruf harmlos
  -- und haelt die Last bei hoechstens 4 Rechnungen in 24 Stunden.
  if exists (select 1 from public.admin_metric_snapshots where slot_key = v_slot) then
    return 'uebersprungen (liegt bereits vor): ' || v_slot;
  end if;

  insert into public.admin_metric_snapshots
        (taken_at, slot_key, metrics, history, today, compare, analytics, leute)
  values (now(), v_slot,
          public.admin_monitor_metrics(),
          public.admin_monitor_history(),
          public.admin_monitor_today(),
          public.admin_monitor_compare(),
          public.admin_monitor_analytics(),
          public.admin_monitor_leute())
  on conflict (slot_key) do nothing;

  return 'geschrieben: ' || v_slot;
end;
$function$;
