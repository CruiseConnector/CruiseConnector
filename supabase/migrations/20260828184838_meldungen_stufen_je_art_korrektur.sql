-- 2026-08-28, Korrektur zur vorigen Migration: Die erste Fassung hatte die
-- Signatur veraendert (p_lat/p_lng ergaenzt) und damit eine ZWEITE Ueberladung
-- neben die echte Funktion gestellt — ein RPC-Aufruf mit zwei Argumenten waere
-- ab da mehrdeutig gewesen. Die Ueberladung fliegt raus; die echte Funktion
-- vom 20.08. wird zeichengetreu wiederhergestellt, mit GENAU EINER Aenderung:
-- der active-Klausel je Meldungsart (Fehler 10).

drop function if exists public.vote_road_incident(uuid, text, double precision, double precision);

create or replace function public.vote_road_incident(
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
  v_cap      int;
begin
  if uid is null then raise exception 'nicht angemeldet' using errcode = '28000'; end if;
  if p_vote not in ('confirm','dismiss') then
    raise exception 'ungueltige Stimme' using errcode = '22023';
  end if;

  select * into s from road_incident_settings where id;
  select * into inc from road_incidents where id = p_incident_id for update;
  if not found then raise exception 'Meldung unbekannt' using errcode = '02000'; end if;

  -- 2026-08-20: siehe 5e. Ohne diese Pruefung entscheidet der Cron-Takt.
  if not inc.active or inc.expires_at <= now() then
    raise exception 'Meldung ist nicht mehr aktuell' using errcode = '02000';
  end if;

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

  insert into road_incident_votes (incident_id, user_id, vote, voted_near)
  values (p_incident_id, uid, p_vote, v_near)
  on conflict (incident_id, user_id) do update
    set vote = excluded.vote, voted_near = excluded.voted_near;

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
             * (case when v.voted_near then 1.0 else 0.5 end) as w
      from road_incident_votes v
      left join road_reporter_stats rs on rs.user_id = v.user_id
     where v.incident_id = p_incident_id
  ) q;

  -- Bestaetigt wird immer auf die volle Frist der Art, auch wenn die Meldung
  -- ungeprueft angelegt wurde.
  v_ttl := road_incident_ttl_sec(inc.type, true);
  v_cap := road_incident_cap_sec(inc.type);

  update road_incidents set
    confirmed_count = 1 + (select count(*) from road_incident_votes
                            where incident_id = p_incident_id and vote = 'confirm'),
    dismissed_count = (select count(*) from road_incident_votes
                        where incident_id = p_incident_id and vote = 'dismiss'),
    last_confirmed_at = case when p_vote = 'confirm' then now() else last_confirmed_at end,
    position_verified = position_verified or (p_vote = 'confirm' and v_near),
    expires_at = case
      when p_vote = 'confirm' then
        least(greatest(expires_at,
                       now() + make_interval(secs => v_ttl)),
              created_at + make_interval(secs => v_cap))
      when w_dism > w_conf then
        -- Abwertung: Restfrist halbieren, nie verlaengern, nie unter 10 min.
        least(expires_at,
              greatest(now() + interval '10 minutes',
                       now() + (expires_at - now()) / 2))
      else expires_at end,
    -- 2026-08-28, Fehler 10, Wunsch des Betreibers woertlich: "Stau sollte
    -- direkt angezeigt werden und auch direkt wieder weggehen koennen ...
    -- Unfaelle koennen auch direkt von den Nutzern wieder weggemacht werden.
    -- Baustellen sollten mehrfach verifiziert werden."
    -- Stau und Unfall: EIN "Schon weg" eines angemeldeten Nutzers (Tageslimit
    -- und Bann-Pruefung oben gelten weiter) deaktiviert sofort. Baustelle:
    -- unveraendert die gewichtete Mehrfach-Bestaetigung — eine gut
    -- bestaetigte Baustelle bleibt gegen Zweitkonten immun.
    active = case
      when p_vote = 'dismiss' and inc.type in ('stau', 'unfall') then false
      when w_dism >= greatest(2.0, w_conf + 2.0) then false
      else active end
  where id = p_incident_id;

  return jsonb_build_object('confirm_weight', w_conf, 'dismiss_weight', w_dism,
                            'counted_near', v_near);
end;
$$;

comment on function public.vote_road_incident(uuid, text) is
  '2026-08-28: Stufen je Art — stau und unfall deaktiviert EIN Schon-weg sofort, baustelle braucht weiter die gewichtete Mehrfach-Bestaetigung. Sonst zeichengleich zur Fassung vom 20.08.';
