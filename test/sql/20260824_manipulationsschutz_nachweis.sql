-- ═══════════════════════════════════════════════════════════════════════════
-- Nachweis zur Migration 20260824100000_startklar_fuer_alle_und_manipulationsschutz
--
-- Auftrag Vucko 2026-08-24 (4.1): „ab dem naechsten Update moechte ich ja,
-- dass halt jeder ein Badge bekommt [...] wirklich jede Person, mit mir
-- eingeschlossen."
-- Auftrag (4.3): Manipulationsschutz. Vucko dachte an die Uhr, gemessen war
-- es schlimmer: authenticated hatte INSERT, DELETE und TRUNCATE auf
-- user_drive_sessions, und der Client schrieb xp_awarded selbst.
--
-- Diese Datei ist KEIN Dart-Test, sondern wird ueber den Supabase-MCP gegen
-- die Datenbank gefahren. Sie legt Testzeilen an und raeumt sie selbst wieder
-- weg (nachgerechnet: user_drive_sessions danach wieder 147 Zeilen, keine
-- Zeile mit source 'gruen' oder 'gegenprobe' uebrig).
--
-- Schritt 0 ist die GEGENPROBE: sie zeigt, was OHNE die Migration passiert.
-- Sie wurde am 24.08. VOR dem Anwenden gefahren und ist hier nur noch
-- dokumentiert, weil sie sich nach der Migration nicht mehr wiederholen
-- laesst (genau das ist der Punkt).
--
-- GEMESSENES ERGEBNIS am 24.08.2026:
--   0  GEGENPROBE (vor der Migration)
--        9999 km, 999999 XP, Zeitstempel 2027-09-27 ... ANGENOMMEN
--        profiles.total_xp sprang dabei 14.860 -> 1.014.859
--   1  XP 999999 auf 10 km ...... abgewiesen: „XP unplausibel: 999999 XP
--                                 fuer 10.000 km. Hoechstens 2091 XP."
--   2  9999 km .................. abgewiesen: „Strecke unplausibel"
--   3  999 km/h ................. abgewiesen: „Hoechstgeschwindigkeit unplausibel"
--   4  300 km in 5 s ............ abgewiesen: „Strecke und Dauer passen nicht zusammen"
--   5  Zeitstempel +400 Tage .... auf Serverzeit gesetzt (Fahrt bleibt erhalten)
--   6  Echte Rekordfahrt ........ angenommen (195,2 km / 7739 s / 3123 XP)
--   7  Tutorial-Zeile ........... angenommen (0 km / 125 XP)
--   8  profiles.total_xp = 900000 -> Server rechnet zurueck auf 14.860, Level 10
--   9  get_fahrt_serie() ........ 4  (Anzeige)
--   10 get_fahrt_serie(heute) ... 5  (Gutschrift)
--        Handprobe an denselben Fahrtagen (23., 21., 20., 19., 17., 16. ...):
--        Anzeige startet am 23., 22. ist Fehltag, 21./20./19. zaehlen, der 18.
--        ist der zweite Fehltag innerhalb der Schonfrist -> 4. Gutschrift
--        zaehlt den heutigen Tag zusaetzlich -> 5. Deckt sich mit
--        GamificationService._serieRueckwaerts.
--   11 Rechte danach ............ anon: SELECT | authenticated: SELECT, INSERT
--                                 (plus das Spaltenrecht UPDATE(photo_url))
--   12 Frisches Konto ........... badges direkt nach der Registrierung: ["badge_15"]
--   13 Zweiter Lauf der Migration 0 Zeilen, Bonus-Ende unveraendert
--
-- Advisor nach der Migration: 0 Fehler (Security und Performance).

-- ---------------------------------------------------------------------------
-- Schritt 1 bis 10: Angriffe und echte Faelle als angemeldeter Nutzer.
-- ---------------------------------------------------------------------------
create temp table nachweis(schritt text, ergebnis text);

do $$
declare
  v_uid uuid; v_id uuid; v_msg text; v_ts timestamptz; v_xp int; v_lvl int;
begin
  select id into v_uid from public.profiles order by created_at limit 1;
  -- Als dieser Nutzer auftreten, ohne Rollenwechsel: die Waechter haengen an
  -- auth.uid(), nicht an der Datenbankrolle.
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  begin
    insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, completed_at_end, source)
    values (v_uid, 10, 1200, 999999, true, 'gruen');
    insert into nachweis values ('1 XP 999999 auf 10 km', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('1 XP 999999 auf 10 km', 'abgewiesen: ' || v_msg);
  end;

  begin
    insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, completed_at_end, source)
    values (v_uid, 9999, 90000, 10, true, 'gruen');
    insert into nachweis values ('2 9999 km', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('2 9999 km', 'abgewiesen: ' || v_msg);
  end;

  begin
    insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, top_speed_kmh, completed_at_end, source)
    values (v_uid, 10, 1200, 10, 999, true, 'gruen');
    insert into nachweis values ('3 999 km/h', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('3 999 km/h', 'abgewiesen: ' || v_msg);
  end;

  begin
    insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, completed_at_end, source)
    values (v_uid, 300, 5, 10, true, 'gruen');
    insert into nachweis values ('4 300 km in 5 s', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('4 300 km in 5 s', 'abgewiesen: ' || v_msg);
  end;

  -- Die Uhr: echte Fahrt, falscher Zeitstempel. Die Fahrt bleibt, der
  -- Zeitstempel wird auf die Serverzeit gesetzt.
  insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, completed_at_end, source, created_at)
  values (v_uid, 12.5, 1800, 125, true, 'gruen', now() + interval '400 days')
  returning id, created_at into v_id, v_ts;
  insert into nachweis values ('5 Zeitstempel 400 Tage in der Zukunft',
    'auf Serverzeit gesetzt: ' || v_ts::text);
  delete from public.user_drive_sessions where id = v_id;

  -- Die echte Rekordfahrt der Produktivdaten darf NICHT durchfallen.
  insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, top_speed_kmh, completed_at_end, source)
  values (v_uid, 195.209, 7739, 3123, 145.6, true, 'gruen') returning id into v_id;
  insert into nachweis values ('6 Echte Rekordfahrt 195,2 km / 3123 XP', 'angenommen');
  delete from public.user_drive_sessions where id = v_id;

  -- Die Tutorial-Belohnung (0 km, 125 XP) ebenfalls nicht.
  insert into public.user_drive_sessions(user_id, distance_km, duration_seconds, xp_awarded, completed_at_end, source)
  values (v_uid, 0, 0, 125, false, 'gruen') returning id into v_id;
  insert into nachweis values ('7 Tutorial-Zeile 0 km / 125 XP', 'angenommen');
  delete from public.user_drive_sessions where id = v_id;

  -- Der kuerzere Weg: direkt ins Profil schreiben.
  update public.profiles set total_xp = 900000, level = 100 where id = v_uid;
  select total_xp, level into v_xp, v_lvl from public.profiles where id = v_uid;
  insert into nachweis values ('8 profiles.total_xp direkt auf 900000, level 100',
    'Server rechnet zurueck auf ' || v_xp::text || ' XP, Level ' || v_lvl::text);

  insert into nachweis values ('9 get_fahrt_serie() Anzeige', public.get_fahrt_serie()::text);
  insert into nachweis values ('10 get_fahrt_serie(heute) Gutschrift',
    public.get_fahrt_serie((now() at time zone 'Europe/Vienna')::date)::text);

  perform private.recalculate_profile_drive_totals(v_uid);
end $$;

select * from nachweis order by schritt;

-- ---------------------------------------------------------------------------
-- Schritt 11: Rechte.
-- ---------------------------------------------------------------------------
select grantee, string_agg(privilege_type, ', ' order by privilege_type) as tabellenrechte
from information_schema.role_table_grants
where table_schema='public' and table_name='user_drive_sessions'
  and grantee in ('anon','authenticated')
group by grantee;

select grantee, privilege_type, column_name
from information_schema.column_privileges
where table_schema='public' and table_name='user_drive_sessions'
  and grantee='authenticated' and privilege_type='UPDATE';

-- ---------------------------------------------------------------------------
-- Schritt 12: Ein frisch registriertes Konto bekommt badge_15 sofort.
-- Laeuft in einer Untertransaktion und wird danach zurueckgedreht.
-- ---------------------------------------------------------------------------
create temp table nachweis_neu(schritt text, ergebnis text);

do $$
declare
  v_uid uuid := gen_random_uuid();
  v_badges text := '(nicht erreicht)';
  v_err text;
begin
  begin
    insert into auth.users(id, email, aud, role)
      values (v_uid, 'trigger-probe-' || v_uid || '@example.invalid',
              'authenticated', 'authenticated');
    select badges::text into v_badges from public.profiles where id = v_uid;
    raise exception 'rollback_bitte';
  exception when others then
    get stacked diagnostics v_err = message_text;
    if v_err <> 'rollback_bitte' then v_badges := 'FEHLER: ' || v_err; end if;
  end;
  insert into nachweis_neu values ('12 Frisches Konto, badges direkt nach dem Anlegen', v_badges);
  insert into nachweis_neu values ('12b Probe-Konto danach noch da?',
    (select count(*)::text from auth.users where id = v_uid));
end $$;

select * from nachweis_neu order by schritt;

-- ---------------------------------------------------------------------------
-- Schritt 13: Idempotenz. Der zweite Lauf der Migration darf niemandem etwas
-- doppelt geben und keine laufende Bonuswoche verschieben.
-- ---------------------------------------------------------------------------
create temp table idem(schritt text, zeilen int, bonus text);

do $$
declare n int; b timestamptz; b2 timestamptz;
begin
  select min(starter_bonus_ende) into b from public.profiles;

  update public.profiles
  set badges = coalesce(badges, '[]'::jsonb) || '["badge_15","badge_16"]'::jsonb
  where not (coalesce(badges, '[]'::jsonb) @> '["badge_15","badge_16"]'::jsonb);
  get diagnostics n = row_count;
  insert into idem values ('13a zweiter Lauf Badge-UPDATE', n, null);

  update public.profiles set starter_bonus_ende = now() + interval '7 days'
  where starter_bonus_ende is null;
  get diagnostics n = row_count;
  select min(starter_bonus_ende) into b2 from public.profiles;
  insert into idem values ('13b zweiter Lauf Bonus-UPDATE', n,
    'vorher ' || b::text || ' / nachher ' || b2::text);
end $$;

select * from idem order by schritt;

-- ---------------------------------------------------------------------------
-- Abschluss: nichts darf liegengeblieben sein.
-- ---------------------------------------------------------------------------
select
  (select count(*) from public.user_drive_sessions) as fahrten_gesamt,
  (select count(*) from public.user_drive_sessions
     where source in ('gruen','gegenprobe')) as testzeilen_uebrig,
  (select count(*) from public.profiles p
     where p.total_xp is distinct from
       (select coalesce(sum(xp_awarded),0)::int
          from public.user_drive_sessions s where s.user_id = p.id))
    as profile_mit_abweichender_xp;
