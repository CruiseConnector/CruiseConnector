-- ===========================================================================
-- Teil 3: Abstimmen und Zuruecknehmen.
--
-- Alte Regel: 3 Ablehnungen loeschten JEDE Meldung — unabhaengig davon, wie oft
-- sie bestaetigt war und ob der Abstimmende ueberhaupt in der Naehe war. Drei
-- Zweitkonten haetten damit jede echte Warnung im Land ausknipsen koennen.
-- Neue Regel: Ablehnungen muessen die Bestaetigungen deutlich uebertreffen,
-- zaehlen voll nur mit Ortsnachweis und werden nach Vertrauen gewichtet.
-- ===========================================================================
drop function if exists public.vote_road_incident(uuid, text);

create function public.vote_road_incident(
  p_incident_id uuid, p_vote text
) returns jsonb
language plpgsql security definer
set search_path to 'public'
as $$
declare
  s          road_incident_settings%rowtype;
  inc        road_incidents%rowtype;
  prof       record;
  uid        uuid := auth.uid();
  v_near     boolean := false;
  w_conf     numeric;
  w_dism     numeric;
  v_today    int;
  v_ttl      int;
begin
  if uid is null then raise exception 'nicht angemeldet' using errcode = '28000'; end if;
  if p_vote not in ('confirm','dismiss') then
    raise exception 'ungueltige Stimme' using errcode = '22023';
  end if;

  select * into s from road_incident_settings where id;
  select * into inc from road_incidents where id = p_incident_id for update;
  if not found then raise exception 'Meldung unbekannt' using errcode = '02000'; end if;

  -- Eigene Meldung bestaetigt man nicht — dafuer gibt es das Zuruecknehmen.
  if inc.reported_by = uid then
    raise exception 'eigene Meldung' using errcode = '42501';
  end if;

  insert into road_reporter_stats (user_id) values (uid) on conflict do nothing;

  select count(*) into v_today from road_incident_votes
   where user_id = uid and created_at > now() - interval '24 hours';
  if v_today >= s.vote_daily_limit then
    raise exception 'Tageslimit fuer Bewertungen erreicht' using errcode = '42901';
  end if;

  select last_known_lat, last_known_lng, last_known_position_at, is_banned
    into prof from profiles where id = uid;
  if prof.is_banned then raise exception 'Konto gesperrt' using errcode = '42501'; end if;

  if prof.last_known_position_at is not null
     and prof.last_known_position_at > now() - interval '5 minutes'
     and geo_distance_m(prof.last_known_lat, prof.last_known_lng, inc.lat, inc.lng)
         <= s.vote_proximity_max_m then
    v_near := true;
  end if;

  insert into road_incident_votes (incident_id, user_id, vote)
  values (p_incident_id, uid, p_vote)
  on conflict (incident_id, user_id) do update set vote = excluded.vote;

  update road_reporter_stats set votes_total = votes_total + 1, updated_at = now()
   where user_id = uid;

  -- Gewichtete Summen ueber ALLE Stimmen. Wer nicht in der Naehe war, zaehlt
  -- halb; wer als Falschmelder auffiel, weniger. Gewicht 0 gibt es bewusst
  -- nicht — sonst waere fuer den Abstimmenden nicht erklaerbar, warum sich
  -- nichts tut.
  select
    coalesce(sum(case when q.vote = 'confirm' then q.w else 0 end), 0),
    coalesce(sum(case when q.vote = 'dismiss' then q.w else 0 end), 0)
    into w_conf, w_dism
  from (
    select v.vote,
           greatest(0.2, least(1.5, coalesce(rs.trust, 1.0)))
             * (case when v.user_id = uid and not v_near then 0.5 else 1.0 end) as w
      from road_incident_votes v
      left join road_reporter_stats rs on rs.user_id = v.user_id
     where v.incident_id = p_incident_id
  ) q;

  v_ttl := case
    when inc.type = 'stau'   then s.ttl_stau_sec
    when inc.type = 'unfall' then s.ttl_unfall_sec
    else s.ttl_baustelle_sec end;

  update road_incidents set
    confirmed_count = 1 + (select count(*) from road_incident_votes
                            where incident_id = p_incident_id and vote = 'confirm'),
    dismissed_count = (select count(*) from road_incident_votes
                        where incident_id = p_incident_id and vote = 'dismiss'),
    last_confirmed_at = case when p_vote = 'confirm' then now() else last_confirmed_at end,
    -- Jede Bestaetigung verlaengert um die typische Lebensdauer, hart gedeckelt.
    expires_at = case
      when p_vote = 'confirm'
        then least(now() + make_interval(secs => v_ttl),
                   created_at + make_interval(secs => s.ttl_cap_sec))
      else expires_at end,
    -- Eine gut bestaetigte Meldung ist gegen Zweitkonten immun.
    active = case when w_dism >= greatest(2.0, w_conf + 2.0) then false else active end
  where id = p_incident_id;

  return jsonb_build_object('confirm_weight', w_conf, 'dismiss_weight', w_dism,
                            'counted_near', v_near);
end;
$$;

-- Der billigste richtige Weg, eine falsche Meldung loszuwerden: der Melder
-- selbst. Kostet ihn nichts und schuetzt sein Vertrauen.
create or replace function public.retract_road_incident(p_incident_id uuid)
returns void
language plpgsql security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then raise exception 'nicht angemeldet' using errcode = '28000'; end if;
  update road_incidents
     set active = false, retracted_at = now()
   where id = p_incident_id and reported_by = auth.uid();
  if not found then raise exception 'nicht deine Meldung' using errcode = '42501'; end if;
end;
$$;;
