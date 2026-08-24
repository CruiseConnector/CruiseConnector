-- Nachweis zu Migration 20260824170000_nur_follower_serverseitig.sql
--
-- Prueft an den ECHTEN Daten, dass "Nur Follower" serverseitig etwas bedeutet.
-- Alles laeuft in einer Untertransaktion, die am Ende zurueckgenommen wird —
-- eingefuegte Blockierungen, Meldungen und Lesestaende bleiben NICHT stehen.
--
-- Ausfuehren ueber den Supabase-MCP (Projekt tlcfaxvvqzobmzwvfnvb).
-- Gruen = laeuft durch und meldet "ALLE PROBEN GRUEN".
-- Rot   = wirft "TEST ROT" und listet die abweichenden Proben.
--
-- GEGENPROBE (ausgefuehrt am 24.08.2026 gegen die unveraenderte Datenbank):
-- ZEHN Proben schlagen fehl — A, B, B3, G, I, J, L, M, E, F. Zwei davon
-- waren vorher nicht auf der Rechnung:
--   * E und F: Blockierungen wirkten auf `posts` serverseitig UEBERHAUPT
--     nicht. Wer blockiert wurde, las die Beitraege trotzdem — gefiltert
--     hat das allein der Client.
--   * M: der Hinweispunkt am Feed-Reiter zaehlte "Nur Follower"-Beitraege
--     von Gefolgten nicht mit.
-- Gruen sind in der Gegenprobe A2, A3, B2, C, D, H, K, N — die Wege also,
-- die weiterlaufen muessen und weiterlaufen.
--
-- ZWEI FALLEN, die dieser Test bewusst umgeht:
--
--   1. Die MCP-Verbindung laeuft als `postgres`, und `postgres` hat
--      BYPASSRLS. Ohne `set local role authenticated` misst der Test nichts.
--
--   2. Vucko (der Anlassgeber) steht in `app_admins`. Der Moderationszweig
--      `is_admin()` in der Leseregel laesst ihn ohnehin alles sehen — jede
--      Probe "Vucko sieht cozy" waere also auch OHNE die Follower-Regel
--      gruen und wuerde nichts messen. Deshalb:
--        * Probe A fragt fuer Vucko `beitrag_lesbar` DIREKT ab. Die Funktion
--          kennt den Admin-Zweig nicht, misst also die Follower-Regel pur.
--        * Alle Proben, in denen etwas NICHT sichtbar sein soll, laufen mit
--          Nicht-Admins (simk, Dacteron, poedy01, cozy).

do $pruefung$
declare
  -- Beteiligte (gemessen am 24.08.2026)
  v_vucko   constant uuid := '1f444750-4407-45cc-8470-1161f866a628'; -- folgt cozy, IST ADMIN
  v_cozy    constant uuid := '33329d30-59fd-458f-a2be-5f0a9456a00c'; -- folgt Vucko NICHT zurueck
  v_simk    constant uuid := '5f570576-6ffb-401c-a49a-cc0600f7fd9f'; -- folgt cozy, kein Admin
  v_fremd   constant uuid := 'dd5f6a66-1b83-4545-9879-5c407e291032'; -- Dacteron, folgt cozy nicht
  v_poedy   constant uuid := '645065af-3999-4e66-90cd-c4718c0b8ddf'; -- kein Admin

  -- Beitraege
  v_post_oeffentlich constant uuid := '013a91df-1ff0-4954-bcfc-baeb5b9476e0'; -- Vucko, public
  v_post_cozy        constant uuid := '39f4bdc1-aa7f-489f-9aee-7fb46b88d030'; -- cozy, followers
  v_post_poedy       constant uuid := '7130cb27-6a1d-422a-b5b7-a45d2562d550'; -- poedy01, followers
  v_kommentar        constant uuid := 'da6e1b22-43c5-43c9-9c90-3b347f2527f1'; -- cozy unter v_post_poedy

  v_protokoll text := '';
  v_fehler    text := '';
  n           bigint;
  b           boolean;
  v_hat_geklappt boolean;
  v_zaehler_vorher  integer;
  v_zaehler_nachher integer;
  v_meldung   uuid;
  v_inhalt    text;
begin
  begin  -- ── Untertransaktion, wird am Ende zurueckgenommen ──────────────

    ---------------------------------------------------------------- A
    -- Der Anlass, ohne Admin-Zweig gemessen: darf Vucko cozys "Nur
    -- Follower"-Beitraege lesen, allein weil er cozy folgt?
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_vucko, 'role', 'authenticated')::text,
                       true);

    -- In den Ausnahmeblock gefasst, damit die GEGENPROBE (Lauf vor der
    -- Migration, wo es die Funktion noch nicht gibt) nicht hier abbricht,
    -- sondern alle uebrigen Proben auch noch misst.
    begin
      select public.beitrag_lesbar(v_cozy, 'followers') into b;
    exception when undefined_function then
      b := null;
    end;
    v_protokoll := v_protokoll || format(
      E'\nA  beitrag_lesbar(cozy,followers) fuer Vucko .... %s (erwartet true)',
      coalesce(b::text, 'FUNKTION FEHLT'));
    if b is not true then
      v_fehler := v_fehler || E'\n  A: Vucko folgt cozy, darf dessen Beitrag aber nicht lesen.';
    end if;

    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nA2 Vucko sieht cozys Beitraege ................. %s (erwartet 2)', n);
    if n <> 2 then v_fehler := v_fehler || E'\n  A2: Vucko sieht cozys Beitraege nicht.'; end if;

    ---------------------------------------------------------------- A3
    -- Dasselbe fuer einen Follower OHNE Adminrechte: simk folgt cozy.
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_simk, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nA3 simk (Follower, kein Admin) sieht cozys ..... %s (erwartet 2)', n);
    if n <> 2 then
      v_fehler := v_fehler || E'\n  A3: Ein einseitiger Follower sieht die Beitraege nicht.';
    end if;

    ---------------------------------------------------------------- D
    select count(*) into n from public.posts where id = v_post_oeffentlich;
    v_protokoll := v_protokoll || format(
      E'\nD  simk sieht den oeffentlichen Beitrag ........ %s (erwartet 1)', n);
    if n <> 1 then v_fehler := v_fehler || E'\n  D: oeffentlicher Beitrag verschwunden.'; end if;

    ---------------------------------------------------------------- K
    -- Zaehlerprobe: fuer jeden sichtbaren Beitrag muss likes_count zu den
    -- sichtbaren Like-Zeilen passen. Sonst zeigt eine Zahl ins Leere.
    select count(*) into n
      from public.posts p
     where p.likes_count is distinct from
           (select count(*) from public.post_likes l where l.post_id = p.id)
        or p.comments_count is distinct from
           (select count(*) from public.comments c where c.post_id = p.id);
    v_protokoll := v_protokoll || format(
      E'\nK  Sichtbare Beitraege mit falscher Zahl ....... %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  K: Ein Zaehler passt nicht zu den sichtbaren Zeilen.'; end if;

    ---------------------------------------------------------------- B
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_fremd, 'role', 'authenticated')::text,
                       true);

    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nB  Unbeteiligter sieht cozys Beitraege .......... %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  B: "Nur Follower" ist wirkungslos — ein Fremder liest mit.'; end if;

    select count(*) into n from public.posts where id = v_post_oeffentlich;
    v_protokoll := v_protokoll || format(
      E'\nB2 Unbeteiligter sieht den oeffentlichen ....... %s (erwartet 1)', n);
    if n <> 1 then v_fehler := v_fehler || E'\n  B2: oeffentliche Beitraege sind fuer Fremde verschwunden.'; end if;

    ---------------------------------------------------------------- B3
    -- Auch die Schlagworte duerfen nicht durchsickern. Es gibt heute keine
    -- einzige Zeile in `post_hashtags`, deshalb legt die Probe eine an
    -- cozys "Nur Follower"-Beitrag an — sie wird mit zurueckgenommen.
    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    insert into public.post_hashtags (post_id, tag)
    values (v_post_cozy, 'probeschlagwort') on conflict do nothing;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_fremd, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.post_hashtags where post_id = v_post_cozy;
    v_protokoll := v_protokoll || format(
      E'\nB3 Unbeteiligter sieht dessen Schlagworte ...... %s (erwartet 0)', n);
    if n <> 0 then
      v_fehler := v_fehler ||
        E'\n  B3: Die Schlagworte eines "Nur Follower"-Beitrags sind fuer Fremde lesbar.';
    end if;

    ---------------------------------------------------------------- G
    -- Kommentar unter einem fremden "Nur Follower"-Beitrag.
    -- Dacteron folgt poedy01 nicht.
    select count(*) into n from public.comments where id = v_kommentar;
    v_protokoll := v_protokoll || format(
      E'\nG  Unbeteiligter sieht den Kommentar darunter ... %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  G: Kommentar unter einem fremden "Nur Follower"-Beitrag lesbar.'; end if;

    ---------------------------------------------------------------- I
    -- Schreibseite: auf einen unsichtbaren Beitrag darf niemand kommentieren.
    v_hat_geklappt := true;
    begin
      insert into public.comments (post_id, user_id, content)
      values (v_post_cozy, v_fremd, 'Probe');
    exception when others then
      v_hat_geklappt := false;
    end;
    v_protokoll := v_protokoll || format(
      E'\nI  Unbeteiligter kommentiert unsichtbaren ...... %s (erwartet abgelehnt)',
      case when v_hat_geklappt then 'DURCHGELASSEN' else 'abgelehnt' end);
    if v_hat_geklappt then
      v_fehler := v_fehler || E'\n  I: Fremder darf einen unsichtbaren Beitrag kommentieren.';
    end if;

    ---------------------------------------------------------------- L
    -- Der Rueckfallweg des Clients: Einfuegen scheitert, aber danach ruft er
    -- `increment_likes`. Die Funktion ist SECURITY DEFINER und wuerde die
    -- Zahl ohne Gegenwehr hochtreiben — die Zahl zeigte dann ins Leere.
    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    select likes_count into v_zaehler_vorher from public.posts where id = v_post_cozy;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_fremd, 'role', 'authenticated')::text,
                       true);
    begin
      perform public.increment_likes(v_post_cozy);
    exception when others then
      null;  -- eine Ablehnung waere auch in Ordnung
    end;

    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    select likes_count into v_zaehler_nachher from public.posts where id = v_post_cozy;

    v_protokoll := v_protokoll || format(
      E'\nL  increment_likes durch Fremden: %s -> %s ....... (erwartet unveraendert)',
      v_zaehler_vorher, v_zaehler_nachher);
    if v_zaehler_vorher is distinct from v_zaehler_nachher then
      v_fehler := v_fehler ||
        E'\n  L: Ein Fremder treibt den Like-Zaehler eines unsichtbaren Beitrags hoch.';
    end if;

    ---------------------------------------------------------------- C
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_cozy, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nC  cozy sieht seine eigenen Beitraege ........... %s (erwartet 2)', n);
    if n <> 2 then v_fehler := v_fehler || E'\n  C: Der Verfasser sieht seine eigenen Beitraege nicht mehr.'; end if;

    ---------------------------------------------------------------- H
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_poedy, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.comments where post_id = v_post_poedy;
    v_protokoll := v_protokoll || format(
      E'\nH  poedy01 sieht die Kommentare am eigenen ...... %s (erwartet 1)', n);
    if n <> 1 then v_fehler := v_fehler || E'\n  H: Der Verfasser sieht die Kommentare am eigenen Beitrag nicht.'; end if;

    ---------------------------------------------------------------- M
    -- Der Hinweispunkt am Feed-Reiter muss dieselbe Regel benutzen wie der
    -- Feed. Lesestand vorher zuruecksetzen, damit die Probe nicht davon
    -- abhaengt, ob Vucko den Feed schon geoeffnet hat.
    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    delete from public.community_lesestand
     where user_id = v_simk and community_id is null;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_simk, 'role', 'authenticated')::text,
                       true);
    select (public.community_hinweispunkte() -> 'reiter' -> 'feed' ->> 'anzahl')::int
      into n;
    v_protokoll := v_protokoll || format(
      E'\nM  Hinweispunkt Feed fuer simk .................. %s (erwartet >= 2)', n);
    if coalesce(n, 0) < 2 then
      v_fehler := v_fehler ||
        E'\n  M: Der Feed-Punkt zaehlt "Nur Follower"-Beitraege von Gefolgten nicht.';
    end if;

    ---------------------------------------------------------------- N
    -- Der Weg, der am leisesten kaputtgehen wuerde: die Meldungs-Ansicht ist
    -- security_invoker und haengt `posts` per LEFT JOIN an. Waere sie fuer
    -- `authenticated` lesbar, stuenden dort ab jetzt NULL-Spalten — der
    -- Moderator saehe eine Meldung ohne Inhalt.
    --
    -- Gemessen: `authenticated` hat auf die View gar kein Leserecht (am
    -- 26.06. entzogen), sie laeuft ueber `service_role`. Genau so wird sie
    -- hier auch geprueft. Die Probe haelt fest, dass die Moderation den
    -- gemeldeten Inhalt weiterhin sieht — und schlaegt an, falls jemand die
    -- View spaeter fuer `authenticated` oeffnet, ohne an die Regel zu denken.
    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    insert into public.content_reports (reporter_id, reported_user_id, post_id, reason)
    values (v_simk, v_cozy, v_post_cozy, 'other')  -- 'reason' hat eine Check-Constraint
    returning id into v_meldung;

    execute 'set local role service_role';
    perform set_config('request.jwt.claims', '', true);
    select post_content into v_inhalt
      from public.v_admin_reports_inbox where id = v_meldung;
    v_protokoll := v_protokoll || format(
      E'\nN  Moderator sieht den gemeldeten Inhalt ........ %s (erwartet gefuellt)',
      case when v_inhalt is null then 'LEER' else 'gefuellt' end);
    if v_inhalt is null then
      v_fehler := v_fehler ||
        E'\n  N: Die Meldungs-Ansicht laeuft leer — Moderation sieht den Beitrag nicht mehr.';
    end if;

    ---------------------------------------------------------------- J
    execute 'set local role anon';
    perform set_config('request.jwt.claims', '', true);
    select count(*) into n from public.posts;
    v_protokoll := v_protokoll || format(
      E'\nJ  Nicht angemeldet sieht Beitraege ............. %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  J: Ohne Anmeldung sind Beitraege lesbar.'; end if;

    ---------------------------------------------------------------- E / F
    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);

    -- E: simk (Follower, kein Admin) blockiert cozy.
    insert into public.user_blocks (blocker_id, blocked_id)
    values (v_simk, v_cozy) on conflict do nothing;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_simk, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nE  simk blockiert cozy -> sieht Beitraege ....... %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  E: Blockierung wirkt nicht (Blockierender liest weiter).'; end if;

    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    delete from public.user_blocks where blocker_id = v_simk and blocked_id = v_cozy;

    -- F: cozy blockiert simk (Gegenrichtung).
    insert into public.user_blocks (blocker_id, blocked_id)
    values (v_cozy, v_simk) on conflict do nothing;

    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_simk, 'role', 'authenticated')::text,
                       true);
    select count(*) into n from public.posts where user_id = v_cozy;
    v_protokoll := v_protokoll || format(
      E'\nF  cozy blockiert simk -> simk sieht ............ %s (erwartet 0)', n);
    if n <> 0 then v_fehler := v_fehler || E'\n  F: Blockierung wirkt nur in eine Richtung.'; end if;

    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);

    -- Alles zurueck. Die Ausnahme nimmt die Untertransaktion zurueck,
    -- die Variablen ueberleben sie.
    raise exception 'RUECKNAHME';

  exception when others then
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
