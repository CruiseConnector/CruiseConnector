-- Nachweis zu Migration
-- 20260824190000_community_anpinnen_fahrzeugart_region_filter.sql
--
-- Prueft an den ECHTEN Daten (Projekt tlcfaxvvqzobmzwvfnvb), dass Anpinnen,
-- Fahrzeugart, Region und der Filter tun, was Vucko am 24.08. beauftragt hat.
-- Alles laeuft in einer Untertransaktion, die am Ende zurueckgenommen wird —
-- gesetzte Fahrzeugarten, Regionen, Pins und Blockierungen bleiben NICHT
-- stehen.
--
-- Ausfuehren ueber den Supabase-MCP.
-- Gruen = laeuft durch und meldet "ALLE PROBEN GRUEN".
-- Rot   = wirft "TEST ROT" und listet die abweichenden Proben.
--
-- GEGENPROBE (ausgefuehrt am 24.08.2026 gegen die Datenbank OHNE die
-- Migration). 15 Probenbloecke rot, woertlich gemeldet:
--   B  column "fahrzeugart" does not exist
--   A  relation "public.community_regionen" does not exist
--   C  nur 0 von 2 neuen Spalten lesbar / C2 nur 0 von 2 update-Rechten
--   D  column c.fahrzeugart does not exist
--   Aufbau  column "fahrzeugart" of relation "communities" does not exist
--   H/I/J/K/L  function public.community_pin_setzen(uuid, boolean) does not exist
--   M  relation "public.community_pins" does not exist
--   N O P Q R S U  function public.get_communities_gefiltert(...) does not exist
-- Gruen war E — und genau die MUSS gruen sein: sie schuetzt den bestehenden
-- Abfrageweg (_communitySelect), der durch die neuen Spalten nicht brechen darf.
--
-- EHRLICH DAZUGESAGT: F und G (Freitext-Region bzw. unbekannte Fahrzeugart
-- werden abgewiesen) waren in der Gegenprobe ebenfalls gruen — aber aus dem
-- FALSCHEN Grund: das UPDATE scheiterte daran, dass es die Spalte noch gar
-- nicht gab, nicht am Fremdschluessel oder am CHECK. Nach der Migration
-- messen sie das Richtige.
--
-- WAS DER TEST GEFUNDEN HAT: Im ersten Durchlauf NACH der Migration war
-- genau eine Probe rot — Q1: „Suche opel liefert 0 Treffer." Die Community
-- heisst „Opel-Crew", die Abfrage benutzte `like` statt `ilike`. Ohne diesen
-- Test waere eine Suche ausgeliefert worden, die nur bei exakter
-- Gross-/Kleinschreibung trifft.
--
-- DREI FALLEN, die dieser Test bewusst umgeht:
--
--   1. Die MCP-Verbindung laeuft als `postgres`, und `postgres` hat
--      BYPASSRLS. Ohne `set local role authenticated` misst der Test nichts.
--
--   2. Vucko steht in `app_admins`. Als Messnutzer taugt er deshalb nicht.
--      Alle Sicht-Proben laufen mit mknis07 (kein Admin, Mitglied in Cruise
--      Connector, Legacy und Has.Crew) und Galip (kein Admin, NICHT Mitglied
--      in denselben).
--
--   3. Ein `select *` auf public.communities faellt als `authenticated` mit
--      42501 aus, weil `founder_id` bewusst kein Leserecht hat. Der Test
--      zaehlt Spalten deshalb immer einzeln auf — dieselbe Falle, in die
--      auch die Migration nicht laufen darf.

do $pruefung$
declare
  -- ── Beteiligte, gemessen am 24.08.2026 ────────────────────────────────
  v_mknis   constant uuid := 'bff6952b-f3f3-4586-b2d3-b9384236be4a'; -- kein Admin
  v_galip   constant uuid := '51d18d2d-ea7a-42a1-8fef-339f08ac5b42'; -- kein Admin

  -- ── Communities ───────────────────────────────────────────────────────
  v_cruise  constant uuid := 'd2c50efb-7a60-4f95-a7c2-724422ee9b46'; -- oeffentl., 19 Mitgl., letzte Nachricht 14.08.
  v_legacy  constant uuid := '27c4a859-d238-4189-8ffa-2a049d804136'; -- oeffentl., 14 Mitgl., NIE eine Nachricht
  v_bmw     constant uuid := 'fb797fc4-2272-45f0-b2a1-538cd2986297'; -- PRIVAT
  v_has     constant uuid := '7cb96a11-6f26-442a-81fd-74b0c255f436'; -- oeffentl., 5 Mitgl., 19.08.
  v_moped   constant uuid := 'fe63a152-eef4-4a50-91a2-2e842d0ab17b'; -- oeffentl., 4 Mitgl., 22.08.
  v_opel    constant uuid := 'ddf1c819-ec2a-4565-80c1-77db028b8244'; -- oeffentl., 4 Mitgl., 24.08.
  v_opel_besitzer constant uuid := 'f7ac81ef-987a-4e01-82e5-4b329143040d';

  v_protokoll text := '';
  v_fehler    text := '';

  n           bigint;
  b           boolean;
  t           text;
  v_json      jsonb;
  v_ids       uuid[];
  v_geklappt  boolean;
  v_marke     integer;
  v_acl       text;
begin
  begin  -- ═══ Untertransaktion, wird am Ende zurueckgenommen ═══

  -- ─────────────────────────────────────────────────────────────────────
  -- B: BESTANDSDATEN. Vor jedem Eingriff. Die sechs vorhandenen
  --    Communities duerfen durch das neue Feld aus KEINEM Filter fallen.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    select count(*) into n from public.communities
     where fahrzeugart <> 'both' or region_code is not null;
    if n <> 0 then
      v_fehler := v_fehler || E'\n  B: ' || n ||
        ' Bestands-Community/-ies haben nicht den Standard both/ueberregional.';
    else
      v_protokoll := v_protokoll || E'\n  B gruen: alle Bestands-Communities '
        || 'stehen auf both + ueberregional, fallen also aus keinem Filter.';
    end if;
  exception when others then
    v_fehler := v_fehler || E'\n  B: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- A: Die Regionsliste ist geschlossen und vollstaendig.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    select count(*) into n from public.community_regionen;
    if n <> 54 then
      v_fehler := v_fehler || E'\n  A: community_regionen hat ' || n
        || ' Zeilen, erwartet 54 (3 Laender + 9 AT + 26 CH + 16 DE).';
    end if;

    select count(*) into n from public.community_regionen where ist_land;
    if n <> 3 then
      v_fehler := v_fehler || E'\n  A2: ' || n || ' Landeszeilen, erwartet 3.';
    end if;

    select count(*) into n from public.community_regionen
     where land_code = 'AT' and not ist_land;
    if n <> 9 then
      v_fehler := v_fehler || E'\n  A3: ' || n || ' AT-Bundeslaender, erwartet 9.';
    end if;

    select count(*) into n from public.community_regionen
     where land_code = 'CH' and not ist_land;
    if n <> 26 then
      v_fehler := v_fehler || E'\n  A4: ' || n || ' CH-Kantone, erwartet 26.';
    end if;

    select count(*) into n from public.community_regionen
     where land_code = 'DE' and not ist_land;
    if n <> 16 then
      v_fehler := v_fehler || E'\n  A5: ' || n || ' DE-Bundeslaender, erwartet 16.';
    end if;

    select name into t from public.community_regionen where code = 'AT-8';
    if t is distinct from 'Vorarlberg' then
      v_fehler := v_fehler || E'\n  A6: AT-8 heisst "' || coalesce(t, '<nichts>')
        || '", erwartet Vorarlberg.';
    end if;

    v_protokoll := v_protokoll || E'\n  A geprueft: Regionsliste.';
  exception when others then
    v_fehler := v_fehler || E'\n  A: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- C: SPALTENWEISES LESERECHT. Die Falle aus CLAUDE.md.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    select count(*) into n from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'communities'
       and grantee = 'authenticated' and privilege_type = 'SELECT'
       and column_name in ('fahrzeugart', 'region_code');
    if n <> 2 then
      v_fehler := v_fehler || E'\n  C: nur ' || n
        || ' von 2 neuen Spalten sind fuer authenticated lesbar. Die App '
        || 'waere fuer das Feld blind.';
    else
      v_protokoll := v_protokoll || E'\n  C gruen: grant select auf beide neuen Spalten.';
    end if;

    select count(*) into n from information_schema.column_privileges
     where table_schema = 'public' and table_name = 'communities'
       and grantee = 'authenticated' and privilege_type = 'UPDATE'
       and column_name in ('fahrzeugart', 'region_code');
    if n <> 2 then
      v_fehler := v_fehler || E'\n  C2: Admins koennen die neuen Felder nicht '
        || 'schreiben (nur ' || n || ' von 2 update-Rechten).';
    end if;
  exception when others then
    v_fehler := v_fehler || E'\n  C: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- D+E: Als angemeldeter Nutzer lesen. D = die neuen Spalten,
  --      E = die BESTEHENDE Spaltenliste aus _communitySelect. E darf
  --      unter keinen Umstaenden rot werden.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    select count(*) into n from (
      select c.id, c.fahrzeugart, c.region_code from public.communities c
    ) x;
    v_protokoll := v_protokoll || E'\n  D gruen: neue Spalten als authenticated '
      || 'lesbar (' || n || ' Zeilen, kein 42501).';

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  D: ' || sqlerrm;
  end;

  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    -- Zeichengleich die Spalten aus community_chat_service._communitySelect.
    select count(*) into n from (
      select c.id, c.owner_id, c.name, c.description, c.is_public,
             c.created_at, c.updated_at, c.owner_only_messages, c.avatar_url
      from public.communities c
    ) x;
    if n < 1 then
      v_fehler := v_fehler || E'\n  E: der bisherige Abfrageweg liefert nichts mehr.';
    else
      v_protokoll := v_protokoll || E'\n  E gruen: _communitySelect liefert '
        || n || ' Zeilen — der bestehende Weg ist unberuehrt.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  E: der bisherige Abfrageweg ist GEBROCHEN: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- F+G: Kein Freitext. Genau das, was beim Markenfeld schiefging.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    v_geklappt := true;
    begin
      update public.communities set region_code = 'Vorarlberg' where id = v_opel;
    exception when others then
      v_geklappt := false;
    end;
    if v_geklappt then
      v_fehler := v_fehler || E'\n  F: eine frei getippte Region wurde '
        || 'angenommen — der Fremdschluessel fehlt.';
    else
      v_protokoll := v_protokoll || E'\n  F gruen: frei getippte Region abgewiesen.';
    end if;
  exception when others then
    v_fehler := v_fehler || E'\n  F: ' || sqlerrm;
  end;

  begin
    v_geklappt := true;
    begin
      update public.communities set fahrzeugart = 'auto' where id = v_opel;
    exception when others then
      v_geklappt := false;
    end;
    if v_geklappt then
      v_fehler := v_fehler || E'\n  G: fahrzeugart "auto" wurde angenommen — '
        || 'der CHECK fehlt.';
    else
      v_protokoll := v_protokoll || E'\n  G gruen: unbekannte Fahrzeugart abgewiesen.';
    end if;
  exception when others then
    v_fehler := v_fehler || E'\n  G: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- AUFBAU fuer die Filterproben (als postgres, wird zurueckgenommen)
  --   Opel-Crew  : Auto,      Vorarlberg (AT-8)
  --   Motorrad   : Motorrad,  ganz Oesterreich (AT)
  --   Has.Crew   : beides,    Wien (AT-9)
  --   Cruise/Legacy/Bmw: unveraendert both + ueberregional
  -- ─────────────────────────────────────────────────────────────────────
  begin
    update public.communities set fahrzeugart = 'car',        region_code = 'AT-8' where id = v_opel;
    update public.communities set fahrzeugart = 'motorcycle', region_code = 'AT'   where id = v_moped;
    update public.communities set fahrzeugart = 'both',       region_code = 'AT-9' where id = v_has;
    v_protokoll := v_protokoll || E'\n  Aufbau gesetzt.';
  exception when others then
    v_fehler := v_fehler || E'\n  Aufbau: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- H+I+J+K+L: Anpinnen
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    perform public.community_pin_setzen(v_cruise, true);
    perform public.community_pin_setzen(v_legacy, true);
    perform public.community_pin_setzen(v_has,    true);

    select array_agg(community_id order by position) into v_ids
    from public.community_pins where user_id = v_mknis;

    if v_ids is distinct from array[v_cruise, v_legacy, v_has] then
      v_fehler := v_fehler || E'\n  H: Pin-Reihenfolge stimmt nicht.';
    else
      v_protokoll := v_protokoll || E'\n  H gruen: drei Pins auf Platz 1,2,3.';
    end if;

    -- I: derselbe Pin ein zweites Mal legt keine zweite Zeile an.
    v_json := public.community_pin_setzen(v_cruise, true);
    select count(*) into n from public.community_pins where user_id = v_mknis;
    if n <> 3 or (v_json ->> 'position')::int <> 1 then
      v_fehler := v_fehler || E'\n  I: zweiter Pin auf dieselbe Community '
        || 'ergab ' || n || ' Zeilen / Platz ' || coalesce(v_json ->> 'position', '?') || '.';
    else
      v_protokoll := v_protokoll || E'\n  I gruen: doppeltes Anpinnen bleibt eine Zeile.';
    end if;

    -- J: die MITTLERE loesen — die Luecke muss sich schliessen.
    perform public.community_pin_setzen(v_legacy, false);
    select array_agg(community_id order by position) into v_ids
    from public.community_pins where user_id = v_mknis;
    select count(*) into n from public.community_pins
     where user_id = v_mknis and position not in (1, 2);
    if n <> 0 or v_ids is distinct from array[v_cruise, v_has] then
      v_fehler := v_fehler || E'\n  J: nach dem Loesen in der Mitte sind die '
        || 'Plaetze nicht mehr luckenlos 1..2.';
    else
      v_protokoll := v_protokoll || E'\n  J gruen: Luecke geschlossen, Plaetze 1..2.';
    end if;

    -- K: Obergrenze. Es gibt nur 6 Communities, also ueber das Ordnen.
    v_geklappt := true;
    begin
      perform public.community_pins_ordnen(array[
        v_cruise, v_legacy, v_bmw, v_has, v_moped, v_opel,
        v_cruise, v_legacy, v_bmw, v_has, v_moped]::uuid[]);
    exception when others then
      v_geklappt := false;
    end;
    -- Doppelte werden entfernt, also bleiben 6 -> das MUSS klappen.
    if not v_geklappt then
      v_fehler := v_fehler || E'\n  K: doppelte Kennungen wurden nicht '
        || 'zusammengefasst.';
    else
      select count(*) into n from public.community_pins where user_id = v_mknis;
      if n <> 6 then
        v_fehler := v_fehler || E'\n  K2: nach dem Ordnen ' || n
          || ' Pins, erwartet 6.';
      else
        v_protokoll := v_protokoll || E'\n  K gruen: Ordnen fasst Doppelte zusammen (6 Pins).';
      end if;
    end if;

    -- K3: Platz 11 direkt einfuegen scheitert am CHECK.
    v_geklappt := true;
    begin
      insert into public.community_pins (user_id, community_id, position)
      values (v_mknis, v_opel, 11);
    exception when others then
      v_geklappt := false;
    end;
    if v_geklappt then
      v_fehler := v_fehler || E'\n  K3: Platz 11 wurde angenommen.';
    else
      v_protokoll := v_protokoll || E'\n  K3 gruen: Platz 11 abgewiesen.';
    end if;

    -- L: Pin auf eine Community, die es nicht gibt.
    v_geklappt := true;
    begin
      insert into public.community_pins (user_id, community_id, position)
      values (v_mknis, '00000000-0000-0000-0000-000000000000'::uuid, 9);
    exception when others then
      v_geklappt := false;
    end;
    if v_geklappt then
      v_fehler := v_fehler || E'\n  L: Pin auf eine nicht vorhandene Community '
        || 'wurde angenommen — der Fremdschluessel fehlt.';
    else
      v_protokoll := v_protokoll || E'\n  L gruen: toter Pin unmoeglich.';
    end if;

    -- Fuer die Sortierproben: nur Legacy angepinnt lassen.
    perform public.community_pins_ordnen(array[v_legacy]::uuid[]);

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  H/I/J/K/L: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- M: Pins sind PRIVAT. Galip darf mknis07s Pins nicht sehen.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_galip)::text, true);
    execute 'set local role authenticated';

    select count(*) into n from public.community_pins;
    if n <> 0 then
      v_fehler := v_fehler || E'\n  M: Galip sieht ' || n || ' fremde Pins.';
    else
      v_protokoll := v_protokoll || E'\n  M gruen: fremde Pins unsichtbar.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  M: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- N: FAHRZEUGART-FILTER. „Auto" muss die gemischten mitnehmen.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    v_json := public.get_communities_gefiltert('entdecken', 'car', null, null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_opel))) then
      v_fehler := v_fehler || E'\n  N1: Filter Auto findet die Auto-Community nicht.';
    end if;
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_moped)) then
      v_fehler := v_fehler || E'\n  N2: Filter Auto zeigt die Motorrad-Community.';
    end if;

    v_json := public.get_communities_gefiltert('entdecken', 'motorcycle', null, null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_moped))) then
      v_fehler := v_fehler || E'\n  N3: Filter Motorrad findet die Motorrad-Community nicht.';
    end if;
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_opel)) then
      v_fehler := v_fehler || E'\n  N4: Filter Motorrad zeigt die Auto-Community.';
    end if;

    -- Der Kern: eine gemischte Community muss in BEIDEN Filtern auftauchen.
    v_json := public.get_communities_gefiltert('meine', 'car', null, null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_has))) then
      v_fehler := v_fehler || E'\n  N5: „offen fuer alle" faellt aus dem Auto-Filter.';
    end if;
    v_json := public.get_communities_gefiltert('meine', 'motorcycle', null, null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_has))) then
      v_fehler := v_fehler || E'\n  N6: „offen fuer alle" faellt aus dem Motorrad-Filter.';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  N gruen: Fahrzeugart-Filter inkl. „beides".';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  N: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- O: REGIONSFILTER samt Hierarchie und „ueberregional faellt nie raus".
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    -- Vorarlberg: Opel-Crew (AT-8) und Motorrad (ganz Oesterreich) passen.
    v_json := public.get_communities_gefiltert('entdecken', null, 'AT-8', null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_opel))) then
      v_fehler := v_fehler || E'\n  O1: Filter Vorarlberg findet die '
        || 'Vorarlberg-Community nicht.';
    end if;
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_moped))) then
      v_fehler := v_fehler || E'\n  O2: Filter Vorarlberg findet die '
        || 'oesterreichweite Community nicht (Hierarchie Land -> Region).';
    end if;

    -- Wien: Opel-Crew (Vorarlberg) darf NICHT dabei sein.
    v_json := public.get_communities_gefiltert('entdecken', null, 'AT-9', null, 'neu', 50, 0);
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_opel)) then
      v_fehler := v_fehler || E'\n  O3: Filter Wien zeigt eine Vorarlberger Community.';
    end if;

    -- Ueberregionale fallen NIE heraus — auch nicht bei einem fremden Land.
    v_json := public.get_communities_gefiltert('meine', null, 'DE-BY', null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_cruise))) then
      v_fehler := v_fehler || E'\n  O4: eine ueberregionale Community faellt '
        || 'aus dem Regionsfilter — genau das darf nicht passieren.';
    end if;
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_has)) then
      v_fehler := v_fehler || E'\n  O5: Filter Bayern zeigt eine Wiener Community.';
    end if;

    -- Ganzes Land als Filter findet die Regionen darin.
    v_json := public.get_communities_gefiltert('meine', null, 'AT', null, 'neu', 50, 0);
    if not (v_json @> jsonb_build_array(jsonb_build_object('id', v_has))) then
      v_fehler := v_fehler || E'\n  O6: Filter „ganz Oesterreich" findet die '
        || 'Wiener Community nicht (Hierarchie Region -> Land).';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  O gruen: Regionsfilter mit Hierarchie.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  O: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- P: ANGEPINNTES OBEN — unabhaengig von der gewaehlten Sortierung.
  --    Legacy ist angepinnt und waere sonst LETZTE (nie eine Nachricht).
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    v_json := public.get_communities_gefiltert('meine', null, null, null, 'aktiv', 50, 0);
    if (v_json -> 0 ->> 'id')::uuid is distinct from v_legacy then
      v_fehler := v_fehler || E'\n  P1: bei „aktiv" steht das Angepinnte nicht oben (oben: '
        || coalesce(v_json -> 0 ->> 'name', '<leer>') || ').';
    end if;
    if (v_json -> 0 ->> 'angepinnt') <> 'true' or (v_json -> 0 ->> 'pin_position') <> '1' then
      v_fehler := v_fehler || E'\n  P2: das Feld angepinnt/pin_position fehlt oder stimmt nicht.';
    end if;

    v_json := public.get_communities_gefiltert('meine', null, null, null, 'gross', 50, 0);
    if (v_json -> 0 ->> 'id')::uuid is distinct from v_legacy then
      v_fehler := v_fehler || E'\n  P3: bei „gross" steht das Angepinnte nicht oben.';
    end if;

    -- Und ohne Pin gilt wieder die Sortierung: Has.Crew (19.08.) vor
    -- Cruise Connector (14.08.).
    if (v_json -> 1 ->> 'id')::uuid is distinct from v_cruise then
      v_fehler := v_fehler || E'\n  P4: bei „gross" steht nach dem Pin nicht die '
        || 'mitgliederstaerkste Community (' || coalesce(v_json -> 1 ->> 'name', '<leer>') || ').';
    end if;

    v_json := public.get_communities_gefiltert('meine', null, null, null, 'aktiv', 50, 0);
    if (v_json -> 1 ->> 'id')::uuid is distinct from v_has then
      v_fehler := v_fehler || E'\n  P5: bei „aktiv" steht nach dem Pin nicht die '
        || 'zuletzt bespielte Community (' || coalesce(v_json -> 1 ->> 'name', '<leer>') || ').';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  P gruen: Angepinntes oben, darunter die Sortierung.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  P: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- Q: SUCHE, samt Maskierung der LIKE-Sonderzeichen.
  --    Q1 hat den einzigen echten Fehler dieser Migration gefunden: die
  --    Abfrage suchte mit `like` und fand „Opel-Crew" bei Eingabe „opel"
  --    nicht. Jetzt `ilike`.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    v_json := public.get_communities_gefiltert('entdecken', null, null, 'opel', 'neu', 50, 0);
    if jsonb_array_length(v_json) <> 1
       or (v_json -> 0 ->> 'id')::uuid is distinct from v_opel then
      v_fehler := v_fehler || E'\n  Q1: Suche „opel" liefert '
        || jsonb_array_length(v_json) || ' Treffer statt genau Opel-Crew.';
    end if;

    v_json := public.get_communities_gefiltert('entdecken', null, null, '%', 'neu', 50, 0);
    if jsonb_array_length(v_json) <> 0 then
      v_fehler := v_fehler || E'\n  Q2: die Suche nach „%" liefert '
        || jsonb_array_length(v_json) || ' Treffer — das Prozentzeichen wird '
        || 'nicht maskiert.';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  Q gruen: Suche inkl. Maskierung.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  Q: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- R: BEREICH. „Entdecken" zeigt weder Privates noch eigene
  --    Mitgliedschaften; „meine" zeigt genau die Mitgliedschaften.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    v_json := public.get_communities_gefiltert('entdecken', null, null, null, 'neu', 50, 0);
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_bmw)) then
      v_fehler := v_fehler || E'\n  R1: Entdecken zeigt eine PRIVATE Community.';
    end if;
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_cruise)) then
      v_fehler := v_fehler || E'\n  R2: Entdecken zeigt eine Community, in der '
        || 'der Nutzer schon Mitglied ist.';
    end if;
    if jsonb_array_length(v_json) <> 2 then
      v_fehler := v_fehler || E'\n  R3: Entdecken liefert '
        || jsonb_array_length(v_json) || ' statt 2 (Opel-Crew, Motorrad/moped).';
    end if;

    v_json := public.get_communities_gefiltert('meine', null, null, null, 'neu', 50, 0);
    if jsonb_array_length(v_json) <> 3 then
      v_fehler := v_fehler || E'\n  R4: „meine" liefert '
        || jsonb_array_length(v_json) || ' statt 3 Mitgliedschaften.';
    end if;
    if (v_json -> 0 ->> 'ist_mitglied') <> 'true'
       or (v_json -> 0 ->> 'meine_rolle') is null then
      v_fehler := v_fehler || E'\n  R5: ist_mitglied/meine_rolle fehlen in der Antwort.';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  R gruen: Bereiche sauber getrennt.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  R: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- S: BLOCKIERUNG wirkt serverseitig. Bisher hat NUR der Client gefiltert.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    insert into public.user_blocks (blocker_id, blocked_id)
    values (v_mknis, v_opel_besitzer)
    on conflict do nothing;

    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_json := public.get_communities_gefiltert('entdecken', null, null, null, 'neu', 50, 0);
    if v_json @> jsonb_build_array(jsonb_build_object('id', v_opel)) then
      v_fehler := v_fehler || E'\n  S: Entdecken zeigt die Community eines '
        || 'blockierten Besitzers.';
    else
      v_protokoll := v_protokoll || E'\n  S gruen: blockierter Besitzer serverseitig weg.';
    end if;

    execute 'reset role';
    delete from public.user_blocks
     where blocker_id = v_mknis and blocked_id = v_opel_besitzer;
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  S: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- T: UNGUELTIGE PARAMETER laufen in einen klaren Fehler, nicht in eine
  --    stillschweigend leere Liste.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_mknis)::text, true);
    execute 'set local role authenticated';

    v_marke := length(v_fehler);
    v_geklappt := true;
    begin perform public.get_communities_gefiltert('irgendwas');
    exception when others then v_geklappt := false; end;
    if v_geklappt then v_fehler := v_fehler || E'\n  T1: unbekannter Bereich wurde geschluckt.'; end if;

    v_geklappt := true;
    begin perform public.get_communities_gefiltert('meine', 'traktor');
    exception when others then v_geklappt := false; end;
    if v_geklappt then v_fehler := v_fehler || E'\n  T2: unbekannte Fahrzeugart wurde geschluckt.'; end if;

    v_geklappt := true;
    begin perform public.get_communities_gefiltert('meine', null, 'Ländle');
    exception when others then v_geklappt := false; end;
    if v_geklappt then v_fehler := v_fehler || E'\n  T3: unbekannte Region wurde geschluckt.'; end if;

    v_geklappt := true;
    begin perform public.get_communities_gefiltert('meine', null, null, null, 'egal');
    exception when others then v_geklappt := false; end;
    if v_geklappt then v_fehler := v_fehler || E'\n  T4: unbekannte Sortierung wurde geschluckt.'; end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  T gruen: falsche Parameter melden sich.';
    end if;

    execute 'reset role';
  exception when others then
    execute 'reset role';
    v_fehler := v_fehler || E'\n  T: ' || sqlerrm;
  end;

  -- ─────────────────────────────────────────────────────────────────────
  -- U: EXECUTE-RECHTE. Die wiederkehrende Falle in diesem Projekt.
  -- ─────────────────────────────────────────────────────────────────────
  begin
    v_marke := length(v_fehler);
    foreach t in array array[
      'public.get_communities_gefiltert(text,text,text,text,text,integer,integer)',
      'public.community_pin_setzen(uuid,boolean)',
      'public.community_pins_ordnen(uuid[])'
    ] loop
      if has_function_privilege('anon', t, 'execute') then
        v_fehler := v_fehler || E'\n  U: anon darf ' || t || ' aufrufen.';
      end if;
      -- PUBLIC laesst sich nicht ueber has_function_privilege abfragen
      -- ('role "public" does not exist'). Die Rechteliste selbst sagt es:
      -- ein Eintrag ohne Empfaenger (=X/...) ist das PUBLIC-Recht, und ein
      -- LEERES proacl heisst „Standard" — und der Standard fuer Funktionen
      -- IST execute fuer PUBLIC. Beides muss weg sein.
      select coalesce(proacl::text, '<leer>') into v_acl
      from pg_proc where oid = t::regprocedure;
      if v_acl = '<leer>' or v_acl like '{=X/%' or v_acl like '%,=X/%' then
        v_fehler := v_fehler || E'\n  U: PUBLIC darf ' || t
          || ' aufrufen (proacl ' || v_acl || ').';
      end if;
      if not has_function_privilege('authenticated', t, 'execute') then
        v_fehler := v_fehler || E'\n  U: authenticated darf ' || t || ' NICHT aufrufen.';
      end if;
    end loop;

    -- Und der search_path steht auf public, pg_temp.
    select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
      and p.proname in ('get_communities_gefiltert', 'community_pin_setzen',
                        'community_pins_ordnen')
      and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%';
    if n <> 3 then
      v_fehler := v_fehler || E'\n  U2: nur ' || n
        || ' von 3 Funktionen haben search_path=public, pg_temp.';
    end if;

    if length(v_fehler) = v_marke then
      v_protokoll := v_protokoll || E'\n  U gruen: Rechte und search_path.';
    end if;
  exception when others then
    v_fehler := v_fehler || E'\n  U: ' || sqlerrm;
  end;

  -- Alles zurueck. Die Ausnahme nimmt die Untertransaktion zurueck,
  -- die Variablen ueberleben sie.
  raise exception 'RUECKNAHME';

  exception when others then
    begin execute 'reset role'; exception when others then null; end;
    if sqlerrm <> 'RUECKNAHME' then
      raise notice 'Protokoll bis zum Abbruch:%', v_protokoll;
      raise;
    end if;
  end;

  raise notice '%', v_protokoll;

  if v_fehler <> '' then
    raise exception E'TEST ROT:%', v_fehler;
  end if;

  raise notice 'ALLE PROBEN GRUEN';
end
$pruefung$;
