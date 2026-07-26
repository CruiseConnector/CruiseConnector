-- ===========================================================================
-- Teil 2: Melden. Ab hier schreibt der Client NICHT mehr selbst — er ruft an,
-- der Server entscheidet. Damit kann kein Client mehr expires_at, active,
-- confirmed_count oder reported_by bestimmen.
-- ===========================================================================

-- Live-Position: wird NUR waehrend laufender Navigation gesetzt und beim
-- Fahrtende wieder geloescht (vuckos Vorgabe, Datensparsamkeit). Sie ist der
-- Anker fuer die Ortspruefung — ohne sie waere jede Meldung ungeprueft.
create or replace function public.set_live_position(
  p_lat double precision, p_lng double precision
) returns void
language plpgsql security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then raise exception 'nicht angemeldet'; end if;
  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'ungueltige Koordinaten';
  end if;
  update profiles
     set last_known_lat = p_lat,
         last_known_lng = p_lng,
         last_known_position_at = now()
   where id = auth.uid();
end;
$$;

create or replace function public.clear_live_position()
returns void
language plpgsql security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then return; end if;
  update profiles
     set last_known_lat = null, last_known_lng = null,
         last_known_position_at = null
   where id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------------
create or replace function public.report_road_incident(
  p_type text,
  p_lat double precision,
  p_lng double precision,
  p_jam_end_lat double precision default null,
  p_jam_end_lng double precision default null
) returns jsonb
language plpgsql security definer
set search_path to 'public'
as $$
declare
  s              road_incident_settings%rowtype;
  st             road_reporter_stats%rowtype;
  prof           record;
  uid            uuid := auth.uid();
  v_verified     boolean := false;
  v_visibility   text := 'public';
  v_ttl          int;
  v_existing     uuid;
  v_daily_limit  int;
  v_used_today   int;
  v_last         record;
  v_dist         double precision;
  v_gap_sec      double precision;
begin
  if uid is null then raise exception 'nicht angemeldet' using errcode = '28000'; end if;
  if p_type not in ('unfall','baustelle','stau') then
    raise exception 'unbekannte Meldungsart' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'ungueltige Koordinaten' using errcode = '22023';
  end if;

  select * into s from road_incident_settings where id;

  select id, created_at, is_banned, last_known_lat, last_known_lng,
         last_known_position_at
    into prof from profiles where id = uid;
  if not found then raise exception 'Profil fehlt' using errcode = '28000'; end if;
  if prof.is_banned then
    raise exception 'Konto gesperrt' using errcode = '42501';
  end if;

  insert into road_reporter_stats (user_id) values (uid) on conflict do nothing;
  select * into st from road_reporter_stats where user_id = uid for update;

  -- Stufe 2: harte Sperre — der Nutzer soll sie sehen und den Grund erfahren.
  if st.blocked_until is not null and st.blocked_until > now() then
    raise exception 'Melden gesperrt bis %', to_char(st.blocked_until, 'DD.MM.YYYY HH24:MI')
      using errcode = '42501';
  end if;

  -- Zweitkonto-Bremse: entweder das Konto ist einen Tag alt, oder es hat schon
  -- eine echte Fahrt hinter sich. Wer sich frisch registriert, um sofort zu
  -- spammen, faellt durch beide Raster.
  if extract(epoch from (now() - prof.created_at)) < s.min_account_age_sec
     and not exists (select 1 from user_drive_sessions where user_id = uid) then
    raise exception 'Melden erst nach der ersten Fahrt moeglich' using errcode = '42501';
  end if;

  -- Tageslimit richtet sich nach Vertrauen.
  v_daily_limit := case
    when st.trust >= 1.2 then s.report_daily_limit_high
    when st.trust <  s.trust_shadow_below then s.report_daily_limit_low
    else s.report_daily_limit_normal end;
  select count(*) into v_used_today from road_incidents
   where reported_by = uid and created_at > now() - interval '24 hours';
  if v_used_today >= v_daily_limit then
    raise exception 'Tageslimit fuer Meldungen erreicht' using errcode = '42901';
  end if;

  -- Letzte eigene Meldung: Mindestabstand in Zeit UND Raum, dazu die
  -- Unmoeglichkeitspruefung (wer in 2 Minuten 80 km weiter meldet, faehrt nicht).
  select lat, lng, created_at into v_last from road_incidents
   where reported_by = uid order by created_at desc limit 1;
  if found then
    v_gap_sec := extract(epoch from (now() - v_last.created_at));
    v_dist    := geo_distance_m(v_last.lat, v_last.lng, p_lat, p_lng);
    if v_gap_sec < s.report_min_interval_sec then
      raise exception 'Bitte kurz warten, bevor du wieder meldest' using errcode = '42901';
    end if;
    if v_gap_sec < s.self_repeat_window_sec and v_dist < s.self_repeat_radius_m then
      raise exception 'Du hast hier gerade erst gemeldet' using errcode = '42901';
    end if;
    if v_gap_sec > 0 and (v_dist / v_gap_sec) * 3.6 > s.max_plausible_kmh then
      raise exception 'Meldung nicht plausibel' using errcode = '42901';
    end if;
  end if;

  -- Ortspruefung: nur was frisch und nah ist, gilt als belegt.
  if prof.last_known_position_at is not null
     and prof.last_known_position_at > now() - make_interval(secs => s.position_max_age_sec)
     and geo_distance_m(prof.last_known_lat, prof.last_known_lng, p_lat, p_lng)
         <= s.proximity_max_m then
    v_verified := true;
  end if;

  -- Stille Sperre (Stufe 1) oder zu geringes Vertrauen: die Meldung entsteht,
  -- erreicht aber niemanden ausser dem Melder selbst.
  if (st.shadow_until is not null and st.shadow_until > now())
     or st.trust < s.trust_shadow_below then
    v_visibility := 'shadow';
  end if;

  -- Zusammenfuehren statt vervielfachen: gibt es hier schon dieselbe Art,
  -- wird bestaetigt statt neu angelegt. Das raeumt Duplikate weg UND macht
  -- Spam auf einen Punkt wirkungslos.
  select id into v_existing from road_incidents
   where active and expires_at > now() and type = p_type
     and visibility = 'public'
     and lat between p_lat - 0.01 and p_lat + 0.01
     and lng between p_lng - 0.02 and p_lng + 0.02
     and geo_distance_m(lat, lng, p_lat, p_lng) <= s.merge_radius_m
   order by geo_distance_m(lat, lng, p_lat, p_lng) asc
   limit 1;

  if v_existing is not null and v_visibility = 'public' then
    perform vote_road_incident(v_existing, 'confirm');
    return jsonb_build_object('incident_id', v_existing, 'merged', true,
                              'verified', v_verified, 'visibility', 'public');
  end if;

  v_ttl := case
    when not v_verified then s.ttl_unverified_sec
    when p_type = 'stau'      then s.ttl_stau_sec
    when p_type = 'unfall'    then s.ttl_unfall_sec
    else s.ttl_baustelle_sec end;

  insert into road_incidents (
    type, lat, lng, reported_by, expires_at, jam_end_lat, jam_end_lng,
    visibility, position_verified
  ) values (
    p_type, p_lat, p_lng, uid, now() + make_interval(secs => v_ttl),
    p_jam_end_lat, p_jam_end_lng, v_visibility, v_verified
  ) returning id into v_existing;

  update road_reporter_stats
     set reports_total = reports_total + 1, updated_at = now()
   where user_id = uid;

  return jsonb_build_object('incident_id', v_existing, 'merged', false,
                            'verified', v_verified, 'visibility', v_visibility);
end;
$$;;
