-- 2026-08-28, Fehler 10: Abstimm-Stufen je Meldungsart.
--
-- ACHTUNG, DIESE FASSUNG WAR FEHLERHAFT: sie hat die Signatur um p_lat/p_lng
-- erweitert und damit eine ZWEITE Ueberladung neben die echte
-- vote_road_incident(uuid, text) gestellt — der RPC-Aufruf des Clients waere
-- dadurch mehrdeutig geworden. Die Korrektur folgt unmittelbar in
-- 20260828184838_meldungen_stufen_je_art_korrektur.sql, die diese Ueberladung
-- wieder entfernt und die richtige Funktion ersetzt.
--
-- Die Datei bleibt im Repo, weil sie in der Produktions-Historie steht und
-- ein Replay beider Migrationen denselben Endzustand ergibt.

create or replace function public.vote_road_incident(
  p_incident_id uuid,
  p_vote text,
  p_lat double precision default null,
  p_lng double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  inc record;
  v_near boolean := false;
  w_conf numeric := 0;
  w_dism numeric := 0;
  v_ttl int;
  v_cap int;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;
  if p_vote not in ('confirm', 'dismiss') then
    return jsonb_build_object('ok', false, 'error', 'bad_vote');
  end if;

  select * into inc from road_incidents where id = p_incident_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if not inc.active then
    return jsonb_build_object('ok', false, 'error', 'inactive');
  end if;
  if inc.reported_by = uid then
    return jsonb_build_object('ok', false, 'error', 'own_incident');
  end if;

  if p_lat is not null and p_lng is not null then
    v_near := ( 6371000 * acos( least(1.0,
        cos(radians(p_lat)) * cos(radians(inc.lat))
      * cos(radians(inc.lng) - radians(p_lng))
      + sin(radians(p_lat)) * sin(radians(inc.lat)) ) ) ) <= 900;
  end if;

  insert into road_incident_votes (incident_id, user_id, vote, voted_near)
  values (p_incident_id, uid, p_vote, v_near)
  on conflict (incident_id, user_id)
  do update set vote = excluded.vote, voted_near = excluded.voted_near,
                created_at = now();

  insert into road_reporter_stats (user_id) values (uid)
  on conflict (user_id) do nothing;
  update road_reporter_stats set votes_total = votes_total + 1, updated_at = now()
   where user_id = uid;

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
        least(expires_at,
              greatest(now() + interval '10 minutes',
                       now() + (expires_at - now()) / 2))
      else expires_at end,
    active = case
      when p_vote = 'dismiss' and inc.type in ('stau', 'unfall') then false
      when w_dism >= greatest(2.0, w_conf + 2.0) then false
      else active end
  where id = p_incident_id;

  return jsonb_build_object('confirm_weight', w_conf, 'dismiss_weight', w_dism,
                            'counted_near', v_near);
end;
$$;

comment on function public.vote_road_incident(uuid, text, double precision, double precision) is
  '2026-08-28: Stufen je Art — stau und unfall deaktiviert EIN Schon-weg sofort, baustelle braucht weiter die gewichtete Mehrfach-Bestaetigung. Vorher: Fassung vom 20.08.';
