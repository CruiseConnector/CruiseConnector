-- ═══════════════════════════════════════════════════════════════════════════
-- Entscheidung und Nachweis: „jeder soll die aufgaben alle nochmal machen"
--
-- Auftrag Vucko 2026-08-25 (Starter-Karte auf der Startseite):
--   „[...] und jeder soll die aufgaben alle nochmal machen [...]"
--
-- ERGEBNIS: Es wurde KEINE Migration geschrieben. Die Ruecksetzung gehoert
-- NICHT in die Datenbank, sie gehoert in den Client. Diese Datei belegt,
-- warum - mit Zahlen, und mit einem Vorfall aus der Produktivdatenbank, der
-- genau diesen Fehler vor 48 Stunden schon einmal gezeigt hat.
--
-- Diese Datei ist KEIN Dart-Test, sondern wird ueber den Supabase-MCP gegen
-- die Datenbank gefahren. Sie schreibt NICHTS, sie liest nur. Sie bricht mit
-- einer Ausnahme ab, wenn die Lage sich so aendert, dass die Entscheidung neu
-- zu treffen waere - das ist ihr Zweck als Waechter.
--
--
-- GEMESSEN am 25.08.2026, 14:12 UTC
-- ---------------------------------
--   profiles gesamt ............................... 202
--   davon starter_aufgaben LEER ................... 200   (nichts zurueckzusetzen)
--   davon mit Haken ...............................   2   (Vucko, LucWqz1)
--   Profile mit laufendem Boost ...................   0
--   Profile mit starter_bonus_ende ueberhaupt .....   1   (Vucko, abgelaufen 22.08.)
--   badge_16 „Startklar" ..........................  183
--   badge_58 „Durchgespielt" ......................    1
--
--   Vucko    10 von 12: abzeichen, community, favorit, garage, km50, post,
--                       route, runde, speichern, tutorial
--            Serverzustand: 79 beendete Fahrten, 945,4 km, 2 Beitraege,
--            1 Fahrzeug, 10 Routen, 30 Abzeichen ohne badge_16
--            -> 6 Haken kaemen beim naechsten Abgleich SOFORT zurueck
--               (abzeichen, garage, km50, post, runde, speichern)
--            -> 4 blieben offen (community, favorit, route, tutorial)
--
--   LucWqz1   6 von 12: community, favorit, route, runde, speichern, tutorial
--            Serverzustand: 11 beendete Fahrten, 204,1 km, 0 Beitraege,
--            1 Fahrzeug, 5 Routen, 8 Abzeichen ohne badge_16
--            -> 2 der 6 Haken kaemen sofort zurueck (runde, speichern)
--            -> 4 blieben offen (community, favorit, route, tutorial)
--            -> und er BEKAEME zusaetzlich 3 neue (abzeichen, garage, km50),
--               ganz ohne unser Zutun
--
-- Eine Ruecksetzung in der Datenbank kann also hoechstens ACHT Haken auf ZWEI
-- Profilen bewegen, und beide Profile sind Tester. Fuer die anderen 200 ist
-- die Liste ohnehin vollstaendig offen.
--
--
-- DER EIGENTLICHE GRUND: DER SERVER HAT HIER KEINE HOHEIT
-- ------------------------------------------------------
-- `starter_aufgaben` auf `profiles` ist ein SPIEGEL des Geraetespeichers,
-- keine fuehrende Quelle. In `synchronisiereMitProfil`
-- (lib/data/services/starter_aufgaben_service.dart) stehen die beiden
-- entscheidenden Stellen - Zeilennummern gemessen an fd9a310, sie wandern,
-- die Namen nicht:
--
--   ~549   _erledigt.addAll(serverErledigt);              <- VEREINIGUNG
--   ~584   if (!_gleicheMenge(serverErledigt, _erledigt)) {
--   ~585     hoch[spalteAufgaben] = (_erledigt.toList()..sort());
--
-- Der Client zieht den Serverstand mit seinem lokalen Stand ZUSAMMEN und
-- schreibt das Ergebnis zurueck. Er entfernt nie etwas. Ein UPDATE, das die
-- Liste serverseitig leert, ist damit beim naechsten App-Start wieder da -
-- geschrieben vom Geraet, das die Haken noch hat.
--
--
-- DAS IST KEINE THEORIE - ES IST AM 24.08. PASSIERT
-- -------------------------------------------------
-- Migration 20260823233705 „boost_erst_nach_dem_onboarding" hat
-- `starter_bonus_ende` fuer ALLE Profile auf NULL gesetzt und danach selbst
-- geprueft:
--
--     if v_bonus <> 0 then
--       raise exception 'Es laeuft noch bei % Profilen eine Bonuswoche.', v_bonus;
--
-- Die Migration ist durchgelaufen, also standen danach nachweislich NULL
-- Bonuswochen in der Tabelle. Heute, 25.08., steht dort wieder eine:
--
--     Vucko   starter_bonus_ende = 2026-08-22 15:24:01.522508+00
--
-- Dieser Zeitpunkt liegt VOR der Migration vom 23./24.08. Er kann also nicht
-- neu vergeben worden sein - haette der Client eine frische Woche gestartet,
-- stuende dort `jetzt + 7 Tage`, also der 31.08. Es ist der ALTE Wert aus den
-- SharedPreferences, den das Geraet nach der Ruecksetzung wieder hochgeladen
-- hat. Schritt 3 unten prueft genau das nach.
--
-- Eine serverseitige Ruecksetzung des Starter-Zustands wurde in dieser App
-- also schon einmal versucht und innerhalb von zwei Tagen vom Client
-- ueberschrieben. Sie ein zweites Mal zu schreiben, waere derselbe Fehler mit
-- einer anderen Spalte.
--
--
-- DAZU KOMMT DIE ZEITFALLE
-- ------------------------
-- Selbst wenn der Client die Ruecksetzung spaeter mittraegt: Eine Migration
-- laeuft HEUTE, der neue Build erreicht die Telefone SPAETER. Zwischen beiden
-- Zeitpunkten oeffnet Vucko die App mit dem alten Build - und laedt seine
-- zehn Haken wieder hoch. Die Migration waere abgelaufen, bevor sie
-- irgendetwas bewirken kann. Ein Ereignis, das zum richtigen Zeitpunkt
-- passieren muss, gehoert dorthin, wo dieser Zeitpunkt bekannt ist: in den
-- Client, beim ersten Start des neuen Builds.
--
--
-- WAS STATTDESSEN ZU TUN IST (lib/, nicht meine Datei)
-- ----------------------------------------------------
-- Das Haus hat das Muster schon: `AppTutorialService.ruecksetzGeneration`
-- (lib/data/services/app_tutorial_service.dart:99) loescht den Geraete-Merker
-- GENAU EINMAL. Dieselbe Konstruktion fuer die Starter-Liste:
--
--   1. `starterRuecksetzGeneration` in starter_aufgaben_service.dart.
--   2. Beim Laden einmalig die vier EREIGNIS-Aufgaben aus `_erledigt`
--      entfernen: tutorial, route, favorit, community.
--      NUR diese vier. Die anderen acht haengen am Serverzustand und waeren
--      nach einem Wimpernschlag wieder da - sie zu loeschen ist ein Flackern
--      ohne Wirkung.
--   3. Wichtig: Die Bereinigung muss NACH der Vereinigung in
--      `synchronisiereMitProfil` greifen (also nach `_erledigt.addAll(
--      serverErledigt)`), sonst holt der Server die Haken sofort zurueck.
--      Danach schreibt der vorhandene `hoch[spalteAufgaben]`-Zweig den
--      bereinigten Stand von selbst hoch - der Client korrigiert den Server,
--      und zwar genau in dem Moment, in dem der neue Build zum ersten Mal
--      laeuft. Damit braucht es hier ueberhaupt keine Migration.
--   4. `_paketVergeben` und `_bonusEnde` NICHT anfassen. Sonst startet eine
--      zweite Doppel-XP-Woche. (Der Waechter trg_guard_starter_bonus_ende
--      faengt das serverseitig zwar ab, aber der Client zeigte dann sieben
--      Tage lang einen Countdown, den es nicht gibt.)
--   5. Die Abzeichen bleiben ohnehin: profiles.badges ist seit dem 06.05.
--      append-only (2026050605_profile_badges_append_only).
--
-- NEBENFUND, nicht Teil dieses Auftrags: Die drei Geraeteschluessel
-- `starter_aufgaben_erledigt_v1`, `starter_bonus_ende_v1` und
-- `starter_paket_vergeben_v1` (starter_aufgaben_service.dart:43-45) sind
-- NICHT kontogebunden - anders als beim Tutorial, das
-- `NutzerPrefsSchluessel.fuer(...)` benutzt. Zwei Konten auf demselben Handy
-- teilen sich damit Haken und Bonuswoche.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare
  v_gesamt          int;
  v_leer            int;
  v_mit_haken       int;
  v_boost_laeuft    int;
  v_boost_gesetzt   int;
  v_ereignis_profile int;
  v_unwiederbringlich int;
  v_zeile           record;
  -- Zeitpunkt der Migration 20260823233705 (boost_erst_nach_dem_onboarding),
  -- die starter_bonus_ende fuer alle auf NULL gesetzt und 0 nachgewiesen hat.
  c_ruecksetzung constant timestamptz := timestamptz '2026-08-23 22:37:05+00';
  -- Die vier Aufgaben, die an einem reinen Oberflaechen-EREIGNIS haengen und
  -- sich NICHT aus dem Serverzustand neu ableiten lassen.
  c_ereignis constant text[] := array['tutorial','route','favorit','community'];
begin

  -- ───────────────────────────────────────────────────────────────────────
  -- Schritt 1: Wie gross ist die Menge ueberhaupt, die man zuruecksetzen
  --            koennte? Ist sie klein, lohnt keine Migration.
  -- ───────────────────────────────────────────────────────────────────────
  select count(*),
         count(*) filter (where coalesce(starter_aufgaben,'[]'::jsonb) = '[]'::jsonb),
         count(*) filter (where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) > 0),
         count(*) filter (where starter_bonus_ende > now()),
         count(starter_bonus_ende)
    into v_gesamt, v_leer, v_mit_haken, v_boost_laeuft, v_boost_gesetzt
    from public.profiles;

  raise notice '1  Profile % | leere Liste % | mit Haken % | Boost laeuft % | Boost gesetzt %',
    v_gesamt, v_leer, v_mit_haken, v_boost_laeuft, v_boost_gesetzt;

  if v_mit_haken > 10 then
    raise exception
      'Die Lage hat sich geaendert: % Profile tragen Haken (am 25.08. waren es 2). '
      'Die Entscheidung „keine Migration" war auf zwei Testprofile gestuetzt und '
      'ist neu zu treffen.', v_mit_haken;
  end if;

  -- ───────────────────────────────────────────────────────────────────────
  -- Schritt 2: Je Profil - welcher Haken kaeme nach einer Ruecksetzung beim
  --            naechsten Abgleich SOFORT zurueck, welcher bliebe offen?
  --
  --            Die Ableitungsregeln stehen 1:1 in
  --            starter_aufgaben_service.dart, synchronisiereAusKennzahlen.
  --            Ein Haken, der sich NICHT ableiten laesst und KEIN
  --            Ereignis-Haken ist, waere unwiederbringlich - eine
  --            Ruecksetzung naehme dann echte Leistung weg. Das darf nicht
  --            vorkommen, deshalb bricht die Datei dann ab.
  -- ───────────────────────────────────────────────────────────────────────
  v_ereignis_profile := 0;
  v_unwiederbringlich := 0;

  for v_zeile in
    with betroffen as (
      select id, username, starter_aufgaben
        from public.profiles
       where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) > 0
    ),
    zustand as (
      select b.id, b.username, b.starter_aufgaben,
        (select count(*) from public.user_drive_sessions s
          where s.user_id = b.id and s.completed_at_end is not null) as fahrten,
        (select coalesce(sum(s.distance_km),0) from public.user_drive_sessions s
          where s.user_id = b.id) as km,
        (select count(*) from public.posts p where p.user_id = b.id) as posts,
        (select count(*) from public.post_hashtags h
           join public.posts p on p.id = h.post_id
          where p.user_id = b.id) as hashtags,
        (select count(*) from public.profile_vehicles v where v.user_id = b.id) as autos,
        (select count(*) from public.routes r where r.user_id = b.id)
          + (select count(*) from public.route_bookmarks x where x.user_id = b.id) as routen,
        (select count(*) from public.groups g where g.created_by = b.id) as gruppen,
        (select count(*) from public.user_drive_sessions s
          where s.user_id = b.id and s.group_id is not null
            and s.completed_at_end is not null) as gruppenfahrten,
        -- badge_16 zaehlt bewusst NICHT mit: es ist die Belohnung dieser
        -- Liste, siehe synchronisiereAusKennzahlen, Absatz [abzeichen].
        (select jsonb_array_length(coalesce(pr.badges,'[]'::jsonb))
                - (case when pr.badges @> '["badge_16"]'::jsonb then 1 else 0 end)
           from public.profiles pr where pr.id = b.id) as badges_ohne_16
      from betroffen b
    ),
    ableitung as (
      select z.*,
        coalesce((
          select jsonb_agg(t order by t) from unnest(array[
            case when z.posts > 0 then 'post' end,
            case when z.hashtags > 0 then 'hashtag' end,
            case when z.fahrten > 0 then 'runde' end,
            case when z.gruppen > 0 or z.gruppenfahrten > 0 then 'gruppenfahrt' end,
            case when z.autos > 0 then 'garage' end,
            case when z.routen > 0 then 'speichern' end,
            case when z.badges_ohne_16 >= 3 then 'abzeichen' end,
            case when z.km >= 50 then 'km50' end
          ]) as t where t is not null
        ), '[]'::jsonb) as kaeme_zurueck
      from zustand z
    )
    select username,
           starter_aufgaben,
           kaeme_zurueck,
           coalesce((
             select jsonb_agg(x order by x)
               from jsonb_array_elements_text(starter_aufgaben) x
              where not kaeme_zurueck ? x
           ), '[]'::jsonb) as bliebe_offen,
           coalesce((
             select jsonb_agg(x order by x)
               from jsonb_array_elements_text(starter_aufgaben) x
              where not kaeme_zurueck ? x and not (x = any(c_ereignis))
           ), '[]'::jsonb) as unwiederbringlich,
           round(km::numeric, 1) as km, fahrten, posts, autos, routen, badges_ohne_16
      from ableitung
     order by username
  loop
    v_ereignis_profile := v_ereignis_profile + 1;
    raise notice '2  % | heute % | kaeme zurueck % | bliebe offen %',
      v_zeile.username, v_zeile.starter_aufgaben, v_zeile.kaeme_zurueck,
      v_zeile.bliebe_offen;
    raise notice '     Zustand: % km, % Fahrten, % Beitraege, % Fahrzeuge, % Routen, % Abzeichen ohne badge_16',
      v_zeile.km, v_zeile.fahrten, v_zeile.posts, v_zeile.autos,
      v_zeile.routen, v_zeile.badges_ohne_16;

    if jsonb_array_length(v_zeile.unwiederbringlich) > 0 then
      v_unwiederbringlich := v_unwiederbringlich + 1;
      raise warning '     UNWIEDERBRINGLICH: %', v_zeile.unwiederbringlich;
    end if;
  end loop;

  if v_unwiederbringlich > 0 then
    raise exception
      'Bei % Profil(en) gibt es Haken, die weder Ereignis-Haken sind noch sich '
      'aus dem Serverzustand ableiten. Eine Ruecksetzung wuerde dort echte '
      'Leistung wegnehmen. Vuckos Vorgabe („der Boost und die Abzeichen '
      'duerfen NICHT mitgerissen werden") gilt sinngemaess auch hier.',
      v_unwiederbringlich;
  end if;

  -- ───────────────────────────────────────────────────────────────────────
  -- Schritt 3: Der Beweis, dass der Client eine serverseitige Ruecksetzung
  --            ueberschreibt. Migration 20260823233705 hat starter_bonus_ende
  --            fuer ALLE auf NULL gesetzt und 0 nachgewiesen. Steht heute
  --            wieder ein Wert da, der VOR dieser Migration liegt, kann er nur
  --            vom Geraet zurueckgeschrieben worden sein - eine frisch
  --            vergebene Woche haette jetzt + 7 Tage ergeben.
  -- ───────────────────────────────────────────────────────────────────────
  select count(*) into v_boost_gesetzt
    from public.profiles
   where starter_bonus_ende is not null
     and starter_bonus_ende < c_ruecksetzung;

  if v_boost_gesetzt > 0 then
    raise notice '3  BELEGT: % Profil(e) tragen wieder ein starter_bonus_ende, das VOR der '
                 'Ruecksetzung vom 23./24.08. liegt. Der Client hat den Wert aus dem '
                 'Geraetespeicher zurueckgeschrieben. Eine serverseitige Ruecksetzung '
                 'des Starter-Zustands haelt nicht.', v_boost_gesetzt;
  else
    raise notice '3  Der Beleg von 2026-08-25 (Vucko, Ende 2026-08-22 15:24 UTC) ist nicht '
                 'mehr reproduzierbar - der Wert wurde inzwischen ueberschrieben. Die '
                 'Beweisfuehrung steht im Kopf dieser Datei.';
  end if;

  -- ───────────────────────────────────────────────────────────────────────
  -- Schritt 4: Was eine Ruecksetzung NICHT mitreissen darf, ist heute
  --            ohnehin unantastbar. Nur zur Sicherheit nachgewiesen.
  -- ───────────────────────────────────────────────────────────────────────
  raise notice '4  Boost laeuft bei % Profil(en) - es gibt also nichts, was eine '
               'Ruecksetzung abwuergen koennte. badge_16 % Profile, badge_58 % Profile, '
               'beide append-only (2026050605).',
    v_boost_laeuft,
    (select count(*) from public.profiles where badges @> '["badge_16"]'::jsonb),
    (select count(*) from public.profiles where badges @> '["badge_58"]'::jsonb);

  raise notice 'ERGEBNIS: keine Migration. Die Ruecksetzung gehoert in '
               'starter_aufgaben_service.dart (siehe Kopf dieser Datei, Punkt 1-5).';
end $$;


-- ═══════════════════════════════════════════════════════════════════════════
-- GEGENPROBE
--
-- Der Block oben laeuft heute ohne Alarm durch. Das allein beweist nichts -
-- ein Waechter, der nie anschlaegt, koennte auch blind sein. Der Block hier
-- faelscht die Lage absichtlich und prueft, ob beide Waechter dann WIRKLICH
-- anschlagen.
--
-- Er schreibt in `profiles` und rollt alles wieder zurueck: jede Manipulation
-- steckt in einer eigenen Unter-Transaktion (`begin ... exception ... end`),
-- die per Ausnahme beendet wird, und der aeussere Block bricht am Ende
-- ebenfalls mit einer Ausnahme ab. Nach dem Lauf steht kein einziger Wert
-- anders da.
--
-- GEMESSENES ERGEBNIS am 25.08.2026:
--   A  15 zusaetzliche Profile mit Haken  -> „Waechter 1 schlug an:
--                                            17 Profile tragen Haken"
--   B  'hashtag' bei Vucko, der 0 Hashtag-Beitraege hat
--                                         -> „Waechter 2 schlug an:
--                                            1 Profil(e) mit unwiederbringlichem Haken"
--   NACH ROLLBACK  Profile mit Haken: 2
--                  Vucko-Aufgaben: ["abzeichen","community","favorit","garage",
--                                   "km50","post","route","runde","speichern","tutorial"]
--   Unabhaengig nachgezaehlt: 202 Profile, 2 mit Haken, 1 starter_bonus_ende,
--   badge_16 183, badge_58 1 - alles unveraendert.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
declare
  v_a text; v_b text; v_c text;
  v_mit_haken int; v_unwiederbringlich int;
  c_ereignis constant text[] := array['tutorial','route','favorit','community'];
begin
  -- ===== GEGENPROBE A: viele Profile mit Haken -> Waechter 1 muss anschlagen
  begin
    update public.profiles set starter_aufgaben = '["community"]'::jsonb
     where id in (select id from public.profiles
                   where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) = 0
                   order by created_at limit 15);
    select count(*) filter (where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) > 0)
      into v_mit_haken from public.profiles;
    if v_mit_haken > 10 then
      raise exception 'Waechter 1 schlug an: % Profile tragen Haken', v_mit_haken;
    end if;
    raise exception 'GEGENPROBE A OHNE ALARM bei % Profilen - Waechter 1 ist blind', v_mit_haken;
  exception when others then
    v_a := sqlerrm;
  end;

  -- ===== GEGENPROBE B: ein Haken, der sich NICHT ableiten laesst und kein
  -- Ereignis-Haken ist ('hashtag' bei jemandem ohne Hashtag-Beitrag)
  begin
    update public.profiles
       set starter_aufgaben = coalesce(starter_aufgaben,'[]'::jsonb) || '["hashtag"]'::jsonb
     where username = 'Vucko';

    with betroffen as (
      select id, username, starter_aufgaben from public.profiles
       where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) > 0
    ), zustand as (
      select b.id, b.username, b.starter_aufgaben,
        (select count(*) from public.user_drive_sessions s where s.user_id=b.id and s.completed_at_end is not null) as fahrten,
        (select coalesce(sum(s.distance_km),0) from public.user_drive_sessions s where s.user_id=b.id) as km,
        (select count(*) from public.posts p where p.user_id=b.id) as posts,
        (select count(*) from public.post_hashtags h join public.posts p on p.id=h.post_id where p.user_id=b.id) as hashtags,
        (select count(*) from public.profile_vehicles v where v.user_id=b.id) as autos,
        (select count(*) from public.routes r where r.user_id=b.id)
          + (select count(*) from public.route_bookmarks x where x.user_id=b.id) as routen,
        (select count(*) from public.groups g where g.created_by=b.id) as gruppen,
        (select count(*) from public.user_drive_sessions s where s.user_id=b.id and s.group_id is not null and s.completed_at_end is not null) as gruppenfahrten,
        (select jsonb_array_length(coalesce(pr.badges,'[]'::jsonb))
                - (case when pr.badges @> '["badge_16"]'::jsonb then 1 else 0 end)
           from public.profiles pr where pr.id=b.id) as badges_ohne_16
      from betroffen b
    ), ableitung as (
      select z.*, coalesce((select jsonb_agg(t order by t) from unnest(array[
            case when z.posts>0 then 'post' end,
            case when z.hashtags>0 then 'hashtag' end,
            case when z.fahrten>0 then 'runde' end,
            case when z.gruppen>0 or z.gruppenfahrten>0 then 'gruppenfahrt' end,
            case when z.autos>0 then 'garage' end,
            case when z.routen>0 then 'speichern' end,
            case when z.badges_ohne_16>=3 then 'abzeichen' end,
            case when z.km>=50 then 'km50' end
          ]) as t where t is not null), '[]'::jsonb) as kaeme_zurueck
      from zustand z
    )
    select count(*) into v_unwiederbringlich from ableitung
     where exists (select 1 from jsonb_array_elements_text(starter_aufgaben) x
                    where not kaeme_zurueck ? x and not (x = any(c_ereignis)));

    if v_unwiederbringlich > 0 then
      raise exception 'Waechter 2 schlug an: % Profil(e) mit unwiederbringlichem Haken', v_unwiederbringlich;
    end if;
    raise exception 'GEGENPROBE B OHNE ALARM - Waechter 2 ist blind';
  exception when others then
    v_b := sqlerrm;
  end;

  -- ===== Kontrolle: nach dem Rollback der Unter-Transaktionen muss alles stehen
  select format('Profile mit Haken: %s | Vucko-Aufgaben: %s',
    (select count(*) from public.profiles where jsonb_array_length(coalesce(starter_aufgaben,'[]'::jsonb)) > 0),
    (select starter_aufgaben::text from public.profiles where username='Vucko'))
    into v_c;

  raise exception 'ABSICHTLICHER ABBRUCH ZUM ZURUECKROLLEN | A: % | B: % | NACHHER: %', v_a, v_b, v_c;
end $$;
