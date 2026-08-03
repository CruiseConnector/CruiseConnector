-- 2026-07-29 (vucko „wenn man 400 m in der Baustelle drin ist und dann erst
-- meldet, soll das zur urspruenglichen Baustelle gehoeren"):
--
-- Der Zusammenfuehr-Radius war fuer alle Arten gleich (200 m). Fuer einen
-- Unfall ist das richtig — ein Unfall 400 m weiter IST ein anderer Unfall.
-- Eine Baustelle ist dagegen linear und oft ueber einen Kilometer lang. Wer
-- mitten drin erst meldet, legte bisher eine zweite Baustelle an, und auf der
-- Karte standen zwei Marker fuer dieselbe Sperre.
--
-- Belegt: Fahrer B meldete 30 m entfernt -> zusammengefuehrt; derselbe Fahrer
-- 400 m weiter in derselben Baustelle -> ZWEITE Meldung.
alter table public.road_incident_settings
  add column if not exists merge_radius_baustelle_m double precision not null default 900;

-- Stau ist ebenfalls linear (Rueckstau), aber kuerzer als eine Baustelle.
alter table public.road_incident_settings
  add column if not exists merge_radius_stau_m double precision not null default 500;

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
  v_merge_m      double precision;
  v_box_lat      double precision;
  v_box_lng      double precision;
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

  if st.blocked_until is not null and st.blocked_until > now() then
    raise exception 'Melden gesperrt bis %', to_char(st.blocked_until, 'DD.MM.YYYY HH24:MI')
      using errcode = '42501';
  end if;

  if extract(epoch from (now() - prof.created_at)) < s.min_account_age_sec
     and not exists (select 1 from user_drive_sessions where user_id = uid) then
    raise exception 'Melden erst nach der ersten Fahrt moeglich' using errcode = '42501';
  end if;

  v_daily_limit := case
    when st.trust >= 1.2 then s.report_daily_limit_high
    when st.trust <  s.trust_shadow_below then s.report_daily_limit_low
    else s.report_daily_limit_normal end;
  select count(*) into v_used_today from road_incidents
   where reported_by = uid and created_at > now() - interval '24 hours';
  if v_used_today >= v_daily_limit then
    raise exception 'Tageslimit fuer Meldungen erreicht' using errcode = '42901';
  end if;

  -- Zusammenfuehr-Radius je Art. Muss VOR der Selbstwiederholungs-Pruefung
  -- feststehen, denn innerhalb dieses Radius ist eine erneute Meldung kein
  -- Spam, sondern eine Bestaetigung.
  v_merge_m := case p_type
    when 'baustelle' then s.merge_radius_baustelle_m
    when 'stau'      then s.merge_radius_stau_m
    else s.merge_radius_m end;

  -- Vorauswahl per Bounding-Box (Index-tauglich), dann exakt nachmessen.
  v_box_lat := v_merge_m / 111320.0;
  v_box_lng := v_merge_m / (111320.0 * cos(radians(p_lat)));

  select id into v_existing from road_incidents
   where active and expires_at > now() and type = p_type
     and visibility = 'public'
     and lat between p_lat - v_box_lat and p_lat + v_box_lat
     and lng between p_lng - v_box_lng and p_lng + v_box_lng
     and geo_distance_m(lat, lng, p_lat, p_lng) <= v_merge_m
   order by geo_distance_m(lat, lng, p_lat, p_lng) asc
   limit 1;

  -- Gibt es hier schon dieselbe Art, ist das eine BESTAETIGUNG — dann greifen
  -- weder Zeit- noch Selbstwiederholungs-Sperre, sonst koennte ein zweiter
  -- Fahrer eine echte Baustelle nicht bestaetigen.
  if v_existing is not null then
    if exists (select 1 from road_incident_votes
                where incident_id = v_existing and user_id = uid)
       or exists (select 1 from road_incidents
                   where id = v_existing and reported_by = uid) then
      -- Schon bestaetigt oder eigene Meldung: nichts tun, aber auch nicht
      -- meckern — der Nutzer hat ja recht.
      return jsonb_build_object('incident_id', v_existing, 'merged', true,
                                'verified', true, 'visibility', 'public',
                                'already', true);
    end if;
    perform vote_road_incident(v_existing, 'confirm');
    return jsonb_build_object('incident_id', v_existing, 'merged', true,
                              'verified', true, 'visibility', 'public');
  end if;

  -- Ab hier entsteht wirklich etwas Neues -> Spam-Bremsen greifen.
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

  if prof.last_known_position_at is not null
     and prof.last_known_position_at > now() - make_interval(secs => s.position_max_age_sec)
     and geo_distance_m(prof.last_known_lat, prof.last_known_lng, p_lat, p_lng)
         <= s.proximity_max_m then
    v_verified := true;
  end if;

  if (st.shadow_until is not null and st.shadow_until > now())
     or st.trust < s.trust_shadow_below then
    v_visibility := 'shadow';
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
