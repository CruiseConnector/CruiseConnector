-- ═══════════════════════════════════════════════════════════════════════════
-- Gegenprobe zur Migration 20260823123000_community_bild_sichtbarkeit_und_code
--
-- Auftrag Vucko 2026-08-23: „Und ganz wichtig, dass man auch im Nachhinein
-- einstellen kann, ob eine Community privat oder oeffentlich ist."
--
-- Diese Datei ist KEIN Dart-Test, sondern wird ueber den Supabase-MCP gegen
-- die Datenbank gefahren. Sie laeuft komplett in einer Transaktion und endet
-- mit ROLLBACK, es bleibt nichts stehen (nachgerechnet: Mitglieder der
-- privaten Community danach wieder 2, Anfragen gesamt 0, avatar_url gesetzt 0).
--
-- Schritt 7 ist die eigentliche Gegenprobe: er stellt den Funktionsrumpf von
-- VOR der Aenderung wieder her und ruft ihn auf. Ohne die Aenderung ist der
-- Beitritt in eine PRIVATE Community sofort eine Mitgliedschaft.
--
-- GEMESSENES ERGEBNIS am 23.08.2026:
--   0  Ausgangslage ............. private Community, Mitglieder=2, Testnutzer kein Mitglied
--   1  v2 mit Code auf privat ... status=request_created
--   2  Wirkung .................. Mitgliedschaft=0, offene Anfrage=1
--   3  zehn weitere Klicks ...... letzter status=request_pending, Anfragezeilen=1
--   4  alter Aufruf (alte App) .. abgewiesen: „Diese Community ist privat. ..."
--   5  Admin nimmt an ........... Mitgliedschaft=1, Anfragestatus=accepted
--   6  Mitglied ruft nochmal .... status=already_member
--   7  GEGENPROBE alter Rumpf ... Mitgliedschaft=1, Anfragen=0  <-- ohne Fix sofort drin
--   8  invite_code direkt lesen . blockiert: permission denied for table communities
--   9  restliche Spalten ........ weiter lesbar
--   10 RPC Code, Nicht-Mitglied . abgewiesen: „Nur Mitglieder sehen den Einladungscode."
--   11 RPC Code, Mitglied ....... geliefert, stimmt mit der Tabelle ueberein
--   12 find_community_by_code ... avatar_url dabei, owner_only_messages dabei
--   13 avatar_url als Admin ..... durfte schreiben
--   14 avatar_url als Fremder ... geaenderte Zeilen=0
--   15 safe_uuid Schutz ......... safe_uuid('kein-ordner')=NULL, kein Fehler
-- ═══════════════════════════════════════════════════════════════════════════

begin;

create temp table zz_ergebnis(nr int, schritt text, befund text) on commit drop;

do $probe$
declare
  v_cid       uuid := 'fb797fc4-2272-45f0-b2a1-538cd2986297';  -- einzige private Community
  v_uid       uuid := '00038bff-00df-46ef-9399-480384c2a4a0';  -- weder Mitglied noch Anfrage
  v_admin     uuid;
  v_code      text;
  v_res       jsonb;
  v_mitglied  int;
  v_anfragen  int;
  v_req       uuid;
  v_befund    text;
  v_txt       text;
  i           int;
begin
  select invite_code into v_code from public.communities where id = v_cid;
  select user_id into v_admin from public.community_members
   where community_id = v_cid and role = 'owner' limit 1;

  select count(*) into v_mitglied from public.community_members where community_id = v_cid;
  insert into zz_ergebnis values (0, 'Ausgangslage',
    'private Community, Mitglieder=' || v_mitglied ||
    ', Testnutzer ist KEIN Mitglied, Code vorhanden=' || (v_code is not null));

  -- ── NEUES VERHALTEN ────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);

  v_res := public.join_community_with_code_v2(v_code);
  insert into zz_ergebnis values (1, 'v2 mit Code auf privat', 'status=' || (v_res->>'status'));

  select count(*) into v_mitglied from public.community_members
   where community_id = v_cid and user_id = v_uid;
  select count(*) into v_anfragen from public.community_join_requests
   where community_id = v_cid and user_id = v_uid and status = 'pending';
  insert into zz_ergebnis values (2, 'Wirkung in der Datenbank',
    'Mitgliedschaft=' || v_mitglied || ' (erwartet 0), offene Anfrage=' || v_anfragen || ' (erwartet 1)');

  -- zehnmal hintereinander tippen
  for i in 1..10 loop
    v_res := public.join_community_with_code_v2(v_code);
  end loop;
  select count(*) into v_anfragen from public.community_join_requests
   where community_id = v_cid and user_id = v_uid;
  insert into zz_ergebnis values (3, 'zehn weitere Klicks',
    'letzter status=' || (v_res->>'status') || ', Anfragezeilen=' || v_anfragen || ' (erwartet 1)');

  -- alter Aufruf darf privat nicht mehr durchlassen
  begin
    perform public.join_community_with_code(v_code);
    v_befund := 'DURCHGELASSEN - Loch waere offen';
  exception when others then
    v_befund := 'abgewiesen: ' || sqlerrm;
  end;
  insert into zz_ergebnis values (4, 'alter Aufruf (alte App)', v_befund);

  -- Admin nimmt die Anfrage an
  select id into v_req from public.community_join_requests
   where community_id = v_cid and user_id = v_uid;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  perform public.accept_community_join_request(v_req);
  select count(*) into v_mitglied from public.community_members
   where community_id = v_cid and user_id = v_uid;
  select status into v_txt from public.community_join_requests where id = v_req;
  insert into zz_ergebnis values (5, 'Admin nimmt an',
    'Mitgliedschaft=' || v_mitglied || ' (erwartet 1), Anfragestatus=' || v_txt);

  -- bestehendes Mitglied kommt weiter rein
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  v_res := public.join_community_with_code_v2(v_code);
  insert into zz_ergebnis values (6, 'Mitglied ruft nochmal auf', 'status=' || (v_res->>'status'));

  -- Zustand fuer die Gegenprobe zuruecksetzen
  delete from public.community_members where community_id = v_cid and user_id = v_uid;
  delete from public.community_join_requests where community_id = v_cid and user_id = v_uid;

  -- ── GEGENPROBE: der Rumpf VOR der Aenderung ────────────────────────────
  execute $alt$
    create or replace function pg_temp.zz_join_alt(p_code text)
    returns uuid language plpgsql security definer set search_path to 'public','pg_temp' as $f$
    declare v_code text; v_community public.communities%rowtype; v_uid uuid;
    begin
      v_uid := auth.uid();
      if v_uid is null then raise exception 'Bitte melde dich an.'; end if;
      v_code := public.normalize_community_invite_code(p_code);
      if v_code is null then raise exception 'Code ungueltig.'; end if;
      select * into v_community from public.communities where upper(invite_code) = upper(v_code);
      if not found then raise exception 'Code ungueltig.'; end if;
      insert into public.community_members (community_id, user_id, role)
      values (v_community.id, v_uid, 'member')
      on conflict (community_id, user_id) do nothing;
      return v_community.id;
    end $f$;
  $alt$;

  perform pg_temp.zz_join_alt(v_code);
  select count(*) into v_mitglied from public.community_members
   where community_id = v_cid and user_id = v_uid;
  select count(*) into v_anfragen from public.community_join_requests
   where community_id = v_cid and user_id = v_uid;
  insert into zz_ergebnis values (7, 'GEGENPROBE alter Rumpf',
    'Mitgliedschaft=' || v_mitglied || ' (also OHNE Fix sofort drin), Anfragen=' || v_anfragen);

  delete from public.community_members where community_id = v_cid and user_id = v_uid;

  -- ── EINLADUNGSCODE: Spaltenrecht ───────────────────────────────────────
  -- Ein fremder angemeldeter Nutzer versucht, den Code einer OEFFENTLICHEN
  -- Community direkt aus der Tabelle zu lesen.
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  execute 'set local role authenticated';
  begin
    execute 'select invite_code from public.communities limit 1' into v_txt;
    v_befund := 'LESBAR (' || coalesce(v_txt, 'null') || ') - Leck offen';
  exception when others then
    v_befund := 'blockiert: ' || sqlerrm;
  end;
  execute 'reset role';
  insert into zz_ergebnis values (8, 'invite_code direkt lesen', v_befund);

  -- Die uebrigen Spalten muessen weiter lesbar sein.
  execute 'set local role authenticated';
  begin
    execute 'select name from public.communities where is_public order by created_at limit 1' into v_txt;
    v_befund := 'weiter lesbar, Beispielname vorhanden=' || (v_txt is not null);
  exception when others then
    v_befund := 'KAPUTT: ' || sqlerrm;
  end;
  execute 'reset role';
  insert into zz_ergebnis values (9, 'restliche Spalten lesen', v_befund);

  -- Nicht-Mitglied fragt den Code ueber die neue RPC
  begin
    v_txt := public.get_community_invite_code(v_cid);
    v_befund := 'HERAUSGEGEBEN - falsch';
  exception when others then
    v_befund := 'abgewiesen: ' || sqlerrm;
  end;
  insert into zz_ergebnis values (10, 'RPC Code, Nicht-Mitglied', v_befund);

  -- Mitglied fragt den Code ueber die neue RPC
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
  v_txt := public.get_community_invite_code(v_cid);
  insert into zz_ergebnis values (11, 'RPC Code, Mitglied',
    'geliefert=' || (v_txt is not null) || ', stimmt mit Tabelle ueberein=' || (v_txt = v_code));

  -- Suche per Code liefert die neuen Felder
  v_res := public.find_community_by_code(v_code);
  insert into zz_ergebnis values (12, 'find_community_by_code',
    'avatar_url dabei=' || (v_res ? 'avatar_url') ||
    ', owner_only_messages dabei=' || (v_res ? 'owner_only_messages'));

  -- Bild schreiben als Admin, ueber die bestehende Update-Regel
  execute 'set local role authenticated';
  begin
    execute 'update public.communities set avatar_url = ''https://example.invalid/x.jpg'' where id = ' || quote_literal(v_cid);
    execute 'select avatar_url from public.communities where id = ' || quote_literal(v_cid) into v_txt;
    v_befund := 'Admin durfte schreiben, Wert=' || coalesce(v_txt, 'null');
  exception when others then
    v_befund := 'FEHLGESCHLAGEN: ' || sqlerrm;
  end;
  execute 'reset role';
  insert into zz_ergebnis values (13, 'avatar_url als Admin setzen', v_befund);

  -- Und als Nicht-Admin darf es niemand
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  execute 'set local role authenticated';
  begin
    execute 'update public.communities set avatar_url = ''https://example.invalid/fremd.jpg'' where id = ' || quote_literal(v_cid);
    get diagnostics i = row_count;
    v_befund := 'geaenderte Zeilen=' || i || ' (erwartet 0)';
  exception when others then
    v_befund := 'abgewiesen: ' || sqlerrm;
  end;
  execute 'reset role';
  insert into zz_ergebnis values (14, 'avatar_url als Fremder setzen', v_befund);

  -- Ordnername ohne UUID darf die Storage-Regel nicht sprengen
  insert into zz_ergebnis values (15, 'safe_uuid Schutz',
    'safe_uuid(''kein-ordner'')=' || coalesce(public.safe_uuid('kein-ordner')::text, 'NULL') ||
    ', is_community_admin(NULL, uid)=' ||
    coalesce(public.is_community_admin(public.safe_uuid('kein-ordner'), v_admin)::text, 'NULL'));
end
$probe$;

select nr, schritt, befund from zz_ergebnis order by nr;

rollback;


-- ═══════════════════════════════════════════════════════════════════════════
-- Teil B: Die Storage-Regel durchgerechnet (ohne Schreibzugriff)
--
-- Warum: „Has.Crew" hat ZWEI Zeilen mit role = 'owner'. Mit dem ueblichen
-- Nutzer-Ordner koennte Admin B das Bild von Admin A nie ersetzen.
--
-- GEMESSEN am 23.08.2026:
--   Admin A (owner_id) ............. darf_schreiben = true
--   Admin B (zweite owner-Zeile) ... darf_schreiben = true
--   Fremder ........................ darf_schreiben = false
--   Ordner ohne UUID ............... darf_schreiben = false, KEIN Fehler 22P02
-- ═══════════════════════════════════════════════════════════════════════════

with faelle as (
  select 'Admin A (owner_id)' as fall, '7cb96a11-6f26-442a-81fd-74b0c255f436/bild.jpg' as objekt,
         (select owner_id from public.communities where id='7cb96a11-6f26-442a-81fd-74b0c255f436') as uid
  union all
  select 'Admin B (zweite owner-Zeile)', '7cb96a11-6f26-442a-81fd-74b0c255f436/bild.jpg',
         (select m.user_id from public.community_members m
           where m.community_id='7cb96a11-6f26-442a-81fd-74b0c255f436' and m.role='owner'
             and m.user_id <> (select owner_id from public.communities where id='7cb96a11-6f26-442a-81fd-74b0c255f436')
           limit 1)
  union all
  select 'Fremder', '7cb96a11-6f26-442a-81fd-74b0c255f436/bild.jpg',
         '00038bff-00df-46ef-9399-480384c2a4a0'::uuid
  union all
  select 'Ordner ohne UUID', 'irgendwas/bild.jpg',
         (select owner_id from public.communities where id='7cb96a11-6f26-442a-81fd-74b0c255f436')
)
select fall, objekt, uid is not null as nutzer_gefunden,
  coalesce(public.is_community_admin(public.safe_uuid((storage.foldername(objekt))[1]), uid), false) as darf_schreiben
from faelle;


-- ═══════════════════════════════════════════════════════════════════════════
-- Teil C: Der Doppel-Trigger ist weg und das Anlegen geht trotzdem
--
-- GEMESSEN am 23.08.2026:
--   After-Insert-Trigger auf communities .. Anzahl=1 (vorher 2)
--   add_community_owner_as_member existiert = false
--   Rolle des Gruenders = owner, Code automatisch vergeben = true
-- ═══════════════════════════════════════════════════════════════════════════

begin;
create temp table zz_t(nr int, schritt text, befund text) on commit drop;
do $p$
declare
  v_uid uuid := '00038bff-00df-46ef-9399-480384c2a4a0';
  v_cid uuid; v_rolle text; v_code text; v_anz int;
begin
  select count(*) into v_anz from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where c.relname='communities' and not t.tgisinternal and t.tgtype = 5;
  insert into zz_t values (1,'After-Insert-Trigger auf communities','Anzahl='||v_anz||' (vorher 2, erwartet 1)');

  insert into zz_t values (2,'alte Funktion weg',
    'add_community_owner_as_member existiert='||
    (to_regprocedure('public.add_community_owner_as_member()') is not null));

  perform set_config('request.jwt.claims', json_build_object('sub', v_uid)::text, true);
  insert into public.communities (owner_id, name, description, is_public, owner_only_messages)
  values (v_uid, 'zz Testgemeinschaft', null, true, false)
  returning id into v_cid;

  select role::text into v_rolle from public.community_members
   where community_id=v_cid and user_id=v_uid;
  select invite_code into v_code from public.communities where id=v_cid;
  insert into zz_t values (3,'Anlegen funktioniert weiter',
    'Rolle des Gruenders='||coalesce(v_rolle,'KEINE')||', Code automatisch vergeben='||(v_code is not null));
end $p$;
select nr, schritt, befund from zz_t order by nr;
rollback;
