-- ===========================================================================
-- Teil 4: Zusperren, Vertrauen pflegen, Sanktionen staffeln.
-- ===========================================================================

alter table public.road_incidents
  add column if not exists trust_scored boolean not null default false;

-- Der Client schreibt ab jetzt NICHTS mehr direkt. Damit sind expires_at,
-- active, confirmed_count, visibility und reported_by fuer ihn unerreichbar.
revoke insert, update, delete on public.road_incidents from authenticated, anon;
revoke insert, update, delete on public.road_incident_votes from authenticated, anon;

drop policy if exists ri_insert on public.road_incidents;
drop policy if exists ri_update_own on public.road_incidents;
drop policy if exists ri_select on public.road_incidents;

-- Sichtbar ist, was aktiv und nicht abgelaufen ist — plus die eigenen
-- Meldungen, auch wenn sie still gestellt sind. So merkt ein stiller
-- Gesperrter nichts von der Sperre.
create policy ri_select on public.road_incidents
  for select to authenticated
  using (
    active and expires_at > now()
    and (visibility = 'public' or reported_by = auth.uid())
  );

-- Funktionsrechte: NIE ueber PUBLIC gewaehren (Cron-EXECUTE-Leck 2026-06-27).
revoke execute on function public.report_road_incident(text, double precision, double precision, double precision, double precision) from public, anon;
revoke execute on function public.vote_road_incident(uuid, text) from public, anon;
revoke execute on function public.retract_road_incident(uuid) from public, anon;
revoke execute on function public.set_live_position(double precision, double precision) from public, anon;
revoke execute on function public.clear_live_position() from public, anon;

grant execute on function public.report_road_incident(text, double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.vote_road_incident(uuid, text) to authenticated;
grant execute on function public.retract_road_incident(uuid) to authenticated;
grant execute on function public.set_live_position(double precision, double precision) to authenticated;
grant execute on function public.clear_live_position() to authenticated;

-- ---------------------------------------------------------------------------
-- Vertrauen neu berechnen + Sanktionen staffeln. Laeuft stuendlich.
create or replace function public.recompute_reporter_trust()
returns void
language plpgsql security definer
set search_path to 'public'
as $$
declare
  s   road_incident_settings%rowtype;
  rec record;
begin
  select * into s from road_incident_settings where id;

  -- Abgelaufenes stilllegen (die Policy filtert ohnehin, aber so ist der
  -- Zustand in der Tabelle ehrlich und die Bewertung unten sauber).
  update road_incidents set active = false
   where active and expires_at <= now();

  -- Jede abgeschlossene Meldung genau EINMAL bewerten. Still gestellte
  -- Meldungen zaehlen bewusst gar nicht: sie sieht niemand, also kann sie
  -- niemand bestaetigen — sie duerften weder helfen noch schaden.
  for rec in
    select id, reported_by, dismissed_count, confirmed_count, visibility, retracted_at
      from road_incidents
     where not trust_scored and not active and reported_by is not null
     for update
  loop
    if rec.visibility = 'public' and rec.retracted_at is null then
      if rec.dismissed_count >= 2 and rec.confirmed_count <= 1 then
        update road_reporter_stats
           set reports_rejected = reports_rejected + 1, updated_at = now()
         where user_id = rec.reported_by;
      else
        update road_reporter_stats
           set reports_upheld = reports_upheld + 1, updated_at = now()
         where user_id = rec.reported_by;
      end if;
    end if;
    update road_incidents set trust_scored = true where id = rec.id;
  end loop;

  -- Vertrauen: Anteil gehaltener Meldungen mit Vorab-Gutschrift (damit ein
  -- einzelner Ausrutscher niemanden sofort verurteilt), leicht belohnt fuer
  -- viele gute Meldungen.
  update road_reporter_stats
     set trust = least(2.0, greatest(0.0,
           ((reports_upheld + 2.0) / (reports_upheld + reports_rejected + 2.0))
           * (1.0 + least(reports_upheld, 10) * 0.05)
         )),
         updated_at = now();

  -- Stufe 1: stille Sperre, 7 Tage. Stufe 2 (Wiederholung): harte, sichtbare
  -- Sperre, 30 Tage — die darf der Nutzer erfahren und sich melden.
  update road_reporter_stats
     set strikes = strikes + 1,
         shadow_until = case when strikes = 0 then now() + interval '7 days' else shadow_until end,
         blocked_until = case when strikes >= 1 then now() + interval '30 days' else blocked_until end,
         blocked_reason = case when strikes >= 1
           then 'Wiederholt Meldungen, die von anderen Fahrern als falsch bewertet wurden.'
           else blocked_reason end,
         updated_at = now()
   where trust < s.trust_block_below
     and coalesce(shadow_until, 'epoch'::timestamptz) < now()
     and coalesce(blocked_until, 'epoch'::timestamptz) < now();

  -- Bewaehrung: Laeuft eine stille Sperre aus, startet der Nutzer knapp
  -- oberhalb der Schwelle neu. Ohne das bliebe er fuer immer still gestellt —
  -- seine Meldungen sieht ja niemand, also kann er kein Vertrauen zurueck
  -- verdienen. Das waere eine Sackgasse, keine Sanktion.
  update road_reporter_stats
     set trust = 0.6, reports_rejected = 0, shadow_until = null, updated_at = now()
   where shadow_until is not null and shadow_until < now()
     and coalesce(blocked_until, 'epoch'::timestamptz) < now()
     and trust < 0.6;
end;
$$;
revoke execute on function public.recompute_reporter_trust() from public, anon, authenticated;

select cron.schedule('road-incident-trust', '7 * * * *',
                     $$select public.recompute_reporter_trust();$$);

-- ---------------------------------------------------------------------------
-- Fuers Monitoring-Dashboard: wer faellt auf?
create or replace view public.road_incident_abuse_watch as
select rs.user_id, p.username, p.created_at as konto_seit,
       rs.reports_total, rs.reports_upheld, rs.reports_rejected,
       round(rs.trust, 2) as vertrauen,
       rs.strikes, rs.shadow_until, rs.blocked_until,
       (select count(*) from road_incidents i
         where i.reported_by = rs.user_id and not i.position_verified) as ohne_ortsnachweis
  from road_reporter_stats rs
  join profiles p on p.id = rs.user_id
 where rs.reports_rejected > 0 or rs.trust < 1.0 or rs.strikes > 0
 order by rs.trust asc, rs.reports_rejected desc;
revoke all on public.road_incident_abuse_watch from public, anon, authenticated;;
