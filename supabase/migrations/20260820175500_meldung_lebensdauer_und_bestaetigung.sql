-- ===========================================================================
-- Verkehrsmeldungen: Lebensdauern, Bestaetigung und Ortsnachweis geradeziehen
--
-- 2026-08-20, Vucko: "Die neue Funktion mit Unfaelle melden, Baustellen und
-- auch Stau ist leider noch nicht so funktional. Ich moechte, dass du das
-- System von Google Maps uebernimmst. Und die Meldung ist auch nicht synchron.
-- Ich habe es gemeldet, und dann bin ich spaeter wieder diese Strasse
-- gefahren, wo eine Baustelle ist, und mir wurde nichts angezeigt von meiner
-- vorherigen Meldung."
--
-- GEMESSEN (Stand 20.08., alle 6 Zeilen in road_incidents, alle abgelaufen):
--   * 3 Baustellen lebten GENAU 15 Minuten (ttl_unverified_sec), weil der
--     Ortsnachweis nicht zustande kam (position_verified = false).
--   * 2 Baustellen mit Ortsnachweis lebten 12 Stunden, 1 Unfall 3 Stunden.
--     Die Baustelle vom 19.08. 14:53 war um 20.08. 02:53 nachts weg, obwohl
--     die Baustelle selbst natuerlich noch stand.
--   * 0 Zeilen in road_incident_votes seit dem 24.07.: es gab nie eine
--     Bestaetigung, weil vorher immer schon alles abgelaufen war.
--
-- Es war also NIE ein Synchronisationsfehler. Die Meldungen kamen an, sie
-- waren beim naechsten Vorbeifahren nur schon tot.
--
-- Diese Migration aendert drei Regeln und fasst den Missbrauchsschutz vom
-- 26.07. (Melde-Intervall, Tageslimits, Vertrauensstufen, stille Sperre,
-- Plausibilitaetspruefung) NICHT an.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. LEBENSDAUERN. Vorher galt eine GLOBALE Obergrenze von 89.000 s (24,7 h)
--    fuer alles. Damit konnte eine Baustelle prinzipiell nie laenger leben als
--    einen Tag, egal wie oft sie bestaetigt wurde. Ab jetzt hat jede Art ihre
--    eigene Grundfrist und ihre eigene Obergrenze.
--
--    Begruendung der Werte, an Google Maps und an der Sache orientiert:
--
--    Stau      Grundfrist  60 min, Obergrenze   4 h.
--              Ein Stau loest sich in Minuten bis Stunden auf. Google haelt
--              Stau-Meldungen nur kurz und ersetzt sie laufend durch neue.
--              Eine Stunde ohne jede Bestaetigung heisst: entweder ist er weg,
--              oder der naechste Fahrer meldet ihn neu. Mit Bestaetigungen
--              deckt die Obergrenze von 4 h auch einen Rueckstau nach einer
--              Vollsperrung ab.                 Vorher: 45 min, Deckel 24,7 h.
--
--    Unfall    Grundfrist   4 h, Obergrenze  12 h.
--              Bergung, Polizei, Fahrbahnreinigung. Drei Stunden waren zu
--              knapp fuer eine Bergung mit Sperre; zwoelf Stunden sind das
--              Aeusserste, was ein Unfall eine Strasse blockiert.
--                                               Vorher:  3 h, Deckel 24,7 h.
--
--    Baustelle Grundfrist  14 Tage, Obergrenze 90 Tage.
--              DAS ist der Fehler, den Vucko gemeldet hat. Eine Baustelle
--              steht Wochen bis Monate. Google bezieht Baustellen aus
--              amtlichen Meldungen und haelt sie ueber die gesamte Bauzeit.
--              14 Tage sind kurz genug, dass eine falsche Meldung von allein
--              verschwindet, und lang genug, dass die naechste Fahrt ueber
--              dieselbe Strasse sie wiederfindet. Wird sie dabei bestaetigt,
--              laeuft die Frist erneut 14 Tage, bis hoechstens 90 Tage ab der
--              ersten Meldung.                  Vorher: 12 h, Deckel 24,7 h.
-- ---------------------------------------------------------------------------
alter table public.road_incident_settings
  add column if not exists ttl_cap_stau_sec      int not null default 14400,
  add column if not exists ttl_cap_unfall_sec    int not null default 43200,
  add column if not exists ttl_cap_baustelle_sec int not null default 7776000,
  -- Ortsnachweis ohne Nachweis, je Art gestaffelt. Siehe Block 3.
  add column if not exists ttl_unverified_stau_sec      int not null default 1800,
  add column if not exists ttl_unverified_unfall_sec    int not null default 5400,
  add column if not exists ttl_unverified_baustelle_sec int not null default 86400,
  -- Geschwindigkeits-Ausgleich fuer den Ortsnachweis. Siehe Block 3.
  add column if not exists proximity_speed_mps   double precision not null default 36,
  add column if not exists proximity_hard_max_m  double precision not null default 3000;

comment on column public.road_incident_settings.ttl_cap_sec is
  'Altbestand vom 26.07., wird seit dem 20.08.2026 nicht mehr gelesen. Die '
  'Obergrenze gilt jetzt je Art: ttl_cap_stau_sec / _unfall_sec / _baustelle_sec.';
comment on column public.road_incident_settings.ttl_unverified_sec is
  'Altbestand vom 26.07. (900 s), wird seit dem 20.08.2026 nicht mehr gelesen. '
  'Ohne Ortsnachweis gilt jetzt ttl_unverified_stau_sec / _unfall_sec / _baustelle_sec.';

-- Die Defaults oben gelten nur fuer NEUE Zeilen. Die eine vorhandene
-- Einstellungszeile muss ausdruecklich nachgezogen werden.
update public.road_incident_settings set
  ttl_stau_sec                 = 3600,      -- 60 min
  ttl_unfall_sec               = 14400,     -- 4 h
  ttl_baustelle_sec            = 1209600,   -- 14 Tage
  ttl_cap_stau_sec             = 14400,     -- 4 h
  ttl_cap_unfall_sec           = 43200,     -- 12 h
  ttl_cap_baustelle_sec        = 7776000,   -- 90 Tage
  ttl_unverified_stau_sec      = 1800,      -- 30 min
  ttl_unverified_unfall_sec    = 5400,      -- 90 min
  ttl_unverified_baustelle_sec = 86400,     -- 24 h
  proximity_speed_mps          = 36,
  proximity_hard_max_m         = 3000,
  updated_at                   = now()
where id;

-- Der harte Deckel in der Tabellenpruefung stammt aus der ersten Fassung
-- (25 Stunden fuer ALLES) und wuerde jede laengere Baustelle schon beim INSERT
-- abweisen. Er bleibt als zweites Netz gegen Programmierfehler bestehen,
-- jetzt aber je Art und mit Puffer oberhalb der Obergrenzen von oben.
alter table public.road_incidents
  drop constraint if exists road_incidents_expires_sane;
alter table public.road_incidents
  add constraint road_incidents_expires_sane
  check (
    expires_at > created_at
    and expires_at <= created_at + case type
      when 'baustelle' then interval '100 days'
      when 'unfall'    then interval '24 hours'
      else                  interval '12 hours'
    end
  );

-- Die Frist-Regel stand bisher an DREI Stellen als kopiertes CASE
-- (report_road_incident, vote_road_incident und der Tabellen-Deckel). Genau so
-- laufen Werte auseinander. Ab jetzt gibt es eine Quelle.
create or replace function public.road_incident_ttl_sec(
  p_type text, p_verified boolean
) returns int
language sql stable security definer
set search_path to 'public'
as $$
  select case
    when p_type = 'stau'   then case when p_verified then s.ttl_stau_sec
                                     else s.ttl_unverified_stau_sec end
    when p_type = 'unfall' then case when p_verified then s.ttl_unfall_sec
                                     else s.ttl_unverified_unfall_sec end
    else                        case when p_verified then s.ttl_baustelle_sec
                                     else s.ttl_unverified_baustelle_sec end
  end
  from road_incident_settings s where s.id;
$$;

create or replace function public.road_incident_cap_sec(p_type text)
returns int
language sql stable security definer
set search_path to 'public'
as $$
  select case p_type
    when 'stau'   then s.ttl_cap_stau_sec
    when 'unfall' then s.ttl_cap_unfall_sec
    else               s.ttl_cap_baustelle_sec
  end
  from road_incident_settings s where s.id;
$$;

-- Funktionsrechte nie ueber PUBLIC (EXECUTE-Leck vom 27.06.). Beide Funktionen
-- lesen die Schwellwerte und werden ausschliesslich aus den Melde- und
-- Abstimmfunktionen heraus aufgerufen, die selbst SECURITY DEFINER sind.
revoke execute on function public.road_incident_ttl_sec(text, boolean)
  from public, anon, authenticated;
revoke execute on function public.road_incident_cap_sec(text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. BESTAETIGUNGEN MUESSEN WIRKEN. Bisher war nicht nachvollziehbar, ob eine
--    Bestaetigung die Lebensdauer verlaengert: sie tat es zwar, lief aber gegen
--    den globalen 24,7-h-Deckel, blieb bei einer Baustelle also folgenlos.
--    Ausserdem wurde die Naehe des Abstimmenden nirgends gespeichert. In der
--    gewichteten Summe wurde nur die GERADE abgegebene Stimme abgewertet, jede
--    aeltere zaehlte beim naechsten Aufruf wieder voll.
-- ---------------------------------------------------------------------------
alter table public.road_incident_votes
  add column if not exists voted_near boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3. ORTSNACHWEIS. Bisher: Position hoechstens 180 s alt UND hoechstens 500 m
--    entfernt. Gemessen scheitert das fast immer, weil set_live_position nur
--    einmal pro 60 s laeuft: ab 30 km/h ist die letzte bekannte Position
--    weiter als 500 m weg, und die Meldung faellt auf die kurze Frist zurueck.
--    Genau das erklaert die drei 15-Minuten-Zeilen.
--
--    a) Die Zeit seit der letzten bekannten Position wird jetzt mit hoechstens
--       130 km/h (36 m/s) in Entfernung umgerechnet. Wer vor 60 s bei
--       Kilometer 0 war, kann jetzt plausibel bei Kilometer 2,2 sein. Der
--       Nachweis bleibt ein echter Nachweis, denn die Position kommt weiterhin
--       nur aus set_live_position waehrend der Fahrt, nicht aus der Meldung
--       selbst. Absolute Obergrenze 3 km, damit eine alte Position nicht die
--       halbe Landschaft belegt.
--
--    b) Ohne Nachweis galten 15 Minuten fuer ALLES. Das ist praktisch dasselbe
--       wie verwerfen. Neu, je Art gestaffelt und immer deutlich kuerzer als
--       mit Nachweis:
--         Stau      30 min statt  60 min  (Haelfte)
--         Unfall    90 min statt   4 h    (ein Drittel)
--         Baustelle 24 h   statt  14 Tage (ein Vierzehntel)
--       Die 24 h fuer die ungeprueft gemeldete Baustelle sind der eigentliche
--       Punkt: der Melde-Knopf ist schon sichtbar, sobald die Route bestaetigt
--       ist, also VOR dem Fahrtstart. Wer dort meldet, hat noch nie eine
--       Position gesendet und bekommt nie einen Ortsnachweis. Mit 24 h findet
--       ihn dieselbe Fahrt am selben Tag wieder, und das Wiederfinden hebt die
--       Meldung ueber Block 4 auf die vollen 14 Tage.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 4. MELDEN. Aenderungen gegenueber dem 26.07.:
--    a) Fristen aus road_incident_ttl_sec statt aus kopiertem CASE.
--    b) Ortspruefung mit Geschwindigkeits-Ausgleich (Block 3a).
--    c) Wer dieselbe Stelle ERNEUT meldet, hat sie gerade wieder gesehen.
--       Vorher passierte in diesem Zweig gar nichts, die Meldung lief trotzdem
--       ab. Das ist woertlich Vuckos Fall: "bin ich spaeter wieder diese
--       Strasse gefahren, wo eine Baustelle ist, und mir wurde nichts
--       angezeigt". Jetzt schiebt die eigene erneute Sichtung die Frist nach
--       vorn, aber nur mit Ortsnachweis, sonst waere es ein Freifahrtschein
--       fuer Dauerlaeufer. Die Obergrenze ab Erstmeldung bleibt bindend.
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
  v_merge_m      double precision;
  v_box_lat      double precision;
  v_box_lng      double precision;
  v_pos_age      double precision;
  v_allow_m      double precision;
  v_own          boolean;
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

  -- 2026-08-20: Die Ortspruefung steht jetzt VOR dem Zusammenfuehren, denn sie
  -- wird dort gebraucht, um zu entscheiden, ob eine erneute eigene Sichtung
  -- die Frist verlaengern darf. Inhaltlich haengt sie von nichts darunter ab.
  v_pos_age := extract(epoch from (now() - prof.last_known_position_at));
  if prof.last_known_position_at is not null
     and v_pos_age <= s.position_max_age_sec then
    v_allow_m := least(s.proximity_hard_max_m,
                       s.proximity_max_m + v_pos_age * s.proximity_speed_mps);
    if geo_distance_m(prof.last_known_lat, prof.last_known_lng, p_lat, p_lng)
       <= v_allow_m then
      v_verified := true;
    end if;
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

  if v_existing is not null then
    v_own := exists (select 1 from road_incident_votes
                      where incident_id = v_existing and user_id = uid)
          or exists (select 1 from road_incidents
                      where id = v_existing and reported_by = uid);

    if v_own then
      -- 2026-08-20 (Vucko: "bin ich spaeter wieder diese Strasse gefahren, wo
      -- eine Baustelle ist, und mir wurde nichts angezeigt von meiner
      -- vorherigen Meldung"): eigene erneute Sichtung verlaengert die Frist.
      -- Ohne Ortsnachweis passiert weiterhin nichts, sonst koennte jemand vom
      -- Sofa aus eine Meldung ewig am Leben halten.
      if v_verified then
        update road_incidents set
          last_confirmed_at = now(),
          position_verified = true,
          expires_at = least(
            greatest(expires_at,
                     now() + make_interval(secs => road_incident_ttl_sec(p_type, true))),
            created_at + make_interval(secs => road_incident_cap_sec(p_type)))
        where id = v_existing;
      end if;
      return jsonb_build_object('incident_id', v_existing, 'merged', true,
                                'verified', v_verified, 'visibility', 'public',
                                'already', true, 'refreshed', v_verified);
    end if;

    perform vote_road_incident(v_existing, 'confirm');
    return jsonb_build_object('incident_id', v_existing, 'merged', true,
                              'verified', true, 'visibility', 'public');
  end if;

  -- Ab hier entsteht wirklich etwas Neues, also greifen die Spam-Bremsen.
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

  if (st.shadow_until is not null and st.shadow_until > now())
     or st.trust < s.trust_shadow_below then
    v_visibility := 'shadow';
  end if;

  v_ttl := road_incident_ttl_sec(p_type, v_verified);

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
$$;

-- ---------------------------------------------------------------------------
-- 5. ABSTIMMEN. Aenderungen gegenueber dem 26.07.:
--    a) Obergrenze je Art statt global. Eine bestaetigte Baustelle kann jetzt
--       wirklich Wochen leben, vorher war bei 24,7 h Schluss. Ausserdem
--       verlaengert eine Bestaetigung nur noch (greatest), sie kann eine
--       bereits laengere Frist nicht mehr verkuerzen.
--    b) Eine Bestaetigung aus der Naehe hebt eine ungeprueft angelegte Meldung
--       auf "geprueft" und auf die volle Frist ihrer Art. Der zweite Fahrer
--       liefert den Ortsnachweis nach, den der erste nicht erbringen konnte.
--    c) Ablehnungen wirken jetzt GESTAFFELT: ueberwiegen sie die
--       Bestaetigungen, halbiert jede Ablehnung die Restfrist (mindestens
--       10 Minuten bleiben, damit nichts unter den Haenden verschwindet).
--       Erst das alte Kriterium (deutliches Uebergewicht) legt die Meldung
--       ganz still. Damit wirkt Vuckos "Auf- und Abwertung anhand der
--       eingehenden Bestaetigungen" in beide Richtungen, ohne dass zwei
--       Zweitkonten eine gut bestaetigte Warnung ausknipsen koennen.
--    d) Die Naehe wird an der Stimme gespeichert (voted_near) statt nur fuer
--       die gerade abgegebene Stimme zu gelten.
--    e) Abgelaufene oder stillgelegte Meldungen nehmen keine Stimme mehr an.
--       Vorher haette eine alte, noch offene App eine laengst abgelaufene
--       Meldung wiederbeleben koennen, solange der Aufraeum-Job sie noch nicht
--       erwischt hatte. Das Ergebnis haette vom Cron-Takt abgehangen.
-- ---------------------------------------------------------------------------
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
    -- Eine gut bestaetigte Meldung bleibt gegen Zweitkonten immun.
    active = case when w_dism >= greatest(2.0, w_conf + 2.0) then false else active end
  where id = p_incident_id;

  return jsonb_build_object('confirm_weight', w_conf, 'dismiss_weight', w_dism,
                            'counted_near', v_near);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. AUFRAEUMEN. Geprueft am 20.08.: der Job road-incident-trust laeuft, 86
--    Laeufe, 0 Fehler, zuletzt 17:07 UTC. Er setzt in recompute_reporter_trust
--    `active = false` fuer alles, was abgelaufen ist — das ist korrekt und
--    bleibt unveraendert. Nur der Takt aendert sich: bei 60 min Grundfrist
--    fuer Stau stuende eine abgelaufene Stau-Meldung sonst bis zu einer Stunde
--    als aktiv in der Tabelle. Sichtbar war sie nie (die Lesepolicy filtert
--    selbst auf `active and expires_at > now()`), aber die Vertrauens-
--    bewertung im selben Job soll zeitnah greifen. Alle 15 Minuten statt
--    stuendlich.
-- ---------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule('road-incident-trust');
exception when others then null;
end $$;

select cron.schedule('road-incident-trust', '7,22,37,52 * * * *',
                     $$select public.recompute_reporter_trust();$$);
