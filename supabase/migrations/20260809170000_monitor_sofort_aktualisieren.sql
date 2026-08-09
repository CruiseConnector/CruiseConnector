-- ═══════════════════════════════════════════════════════════════════════════
-- Sofort-Aktualisierung des Monitorings, auf Knopfdruck
--
-- Auftrag Vucko 2026-08-09: „schau, dass die Aktualisierungen wirklich
-- zuverlaessig alle 6 Stunden passieren und eine sofortige Aktualisierung auch
-- noch moeglich waere."
--
-- Anders als admin_monitor_take_snapshot() (idempotent, ueberspringt einen
-- bereits vorhandenen 6-Stunden-Slot) rechnet DIESE Funktion bewusst neu und
-- ueberschreibt den aktuellen Slot mit frischen Zahlen. Man sieht sofort den
-- Stand von jetzt, ohne auf den naechsten 6-Stunden-Lauf zu warten.
--
-- SCHUTZ GEGEN DAUERKLICKEN: hoechstens einmal alle 90 Sekunden. Der geplante
-- 6-Stunden-Rhythmus bleibt unberuehrt — es wird nur der laufende Slot
-- aktualisiert, kein zusaetzlicher angelegt.
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.admin_monitor_refresh_now()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_slot text := public.monitor_slot_key();
  v_last timestamptz;
  v_cooldown constant interval := interval '90 seconds';
  v_wait int;
begin
  select taken_at into v_last
    from public.admin_metric_snapshots
   where slot_key = v_slot;

  if v_last is not null and v_last > now() - v_cooldown then
    v_wait := ceil(extract(epoch from (v_last + v_cooldown - now())));
    return jsonb_build_object('ok', false, 'grund', 'zu_frueh', 'wartesekunden', v_wait);
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
  on conflict (slot_key) do update
    set taken_at  = excluded.taken_at,
        metrics   = excluded.metrics,
        history   = excluded.history,
        today     = excluded.today,
        compare   = excluded.compare,
        analytics = excluded.analytics,
        leute     = excluded.leute;

  return jsonb_build_object('ok', true, 'slot', v_slot);
end;
$function$;

revoke all on function public.admin_monitor_refresh_now() from public, anon, authenticated;
