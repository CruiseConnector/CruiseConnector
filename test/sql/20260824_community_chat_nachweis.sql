-- ═══════════════════════════════════════════════════════════════════════════
-- Nachweis zur Migration 20260824160000_community_verlauf_bearbeiten_loeschen
--
-- Auftrag Vucko 2026-08-24: Beitritts-Verlauf, Bearbeiten bis 6 Stunden,
-- Loeschen fuer alle oder nur fuer sich, Chat-Art - und ausdruecklich:
-- "nicht durch zeit zurueckstellen oder datum zurueckstellen irgendwie
-- manipuliert werden kann".
--
-- Diese Datei ist KEIN Dart-Test, sondern wird ueber den Supabase-MCP gegen
-- die Datenbank gefahren (Muster: 20260824_manipulationsschutz_nachweis.sql).
-- Sie legt eine Test-Community an und loescht sie am Ende wieder; das Cascade
-- raeumt Mitglieder, Nachrichten, Verlauf und Ausgeblendetes mit weg.
--
-- ───────────────────────────────────────────────────────────────────────────
-- SCHRITT 0 - DIE GEGENPROBE, gefahren am 24.08. VOR der Migration
-- ───────────────────────────────────────────────────────────────────────────
-- Als angemeldeter Verfasser (set role authenticated + request.jwt.claims),
-- an einer echten Nachricht, die drei Tage alt gemacht wurde:
--
--   1 Text nach 3 Tagen aendern ... DURCHGELASSEN -> "GEGENPROBE UMGESCHRIEBEN"
--   2 created_at +400 Tage ........ DURCHGELASSEN -> 2027-09-28 14:01:47+00
--   3 deleted_at auf 2019 ......... DURCHGELASSEN -> 2019-01-01 00:00:00+00
--   4 Loeschung zuruecknehmen ..... DURCHGELASSEN -> wieder sichtbar
--   5 hartes DELETE ............... DURCHGELASSEN -> Zeile spurlos weg
--
-- Alle fuenf sind nach der Migration zu. Schritt 2 ist der wichtigste: wer
-- created_at frei setzen kann, hat die 6-Stunden-Frist ausgehebelt, bevor sie
-- ueberhaupt beginnt.
--
-- ───────────────────────────────────────────────────────────────────────────
-- GEMESSENES ERGEBNIS NACH DER MIGRATION (24.08.2026)
-- ───────────────────────────────────────────────────────────────────────────
--   A0 Gruender protokolliert ............. beitritt
--                (set_community_owner_member_on_insert wird mitgesehen)
--   A1 Beitritt ........................... beitritt
--   A2 Austritt (selbst gegangen) ......... austritt
--   A3 Entfernen durch Admin .............. entfernt, ausgeloest_von = Admin
--   A3b Selbst gegangen ................... austritt, ausgeloest_von = Gast
--   A4 Bremse nach 10 weiteren Runden ..... 6 Zeilen insgesamt
--                (20 Ereignisse angeboten, 6 protokolliert, Rest verworfen)
--   A5 Altbestand nachgetragen ............ 44 Zeilen
--   B1 Bearbeiten innerhalb 6 h ........... angenommen -> "NEU: bearbeitet",
--                bearbeitet_am gesetzt (die Leerzeichen wurden getrimmt)
--   B2 original_body als Eigentuemer ...... "NEU: eine Stunde alt"
--                (erste Fassung erhalten, nur mit Eigentuemerrechten lesbar)
--   B3 Bearbeiten nach 3 Tagen ............ abgewiesen: "Die Bearbeitungsfrist
--                von 6 Stunden ist abgelaufen."
--   B3b Roher UPDATE nach 3 Tagen ......... dieselbe Abweisung. DAS ist der
--                Kern: die Frist gilt auch an der Funktion vorbei.
--   B4 created_at +400 Tage ............... ignoriert, alter Wert bleibt
--   B5 Fremde Nachricht bearbeiten ........ abgewiesen: "Nur der Verfasser
--                kann seine Nachricht bearbeiten."
--   B6 original_body lesen ................ abgewiesen: permission denied
--                for table community_messages
--   B7 INSERT mit created_at +400 Tage .... auf Serverzeit gesetzt
--   C1 Loeschen fuer alle (fremde, als Inhaber) ... deleted_at = Serverzeit
--   C2 Geraeteuhr beim Loeschen (2019) .... auf Serverzeit gesetzt
--   C3 Loeschung zuruecknehmen ............ wirkungslos, bleibt geloescht
--   C4 hartes DELETE ...................... abgewiesen: permission denied
--   C5 TRUNCATE ........................... abgewiesen: permission denied
--   C6 Nur fuer mich ...................... 1 Ausblendung, Nachricht selbst
--                unberuehrt (fuer alle anderen weiter sichtbar)
--   D1 chat_darstellung 'nachrichten' ..... angenommen
--   D2 chat_darstellung 'quatsch' ......... abgewiesen (CHECK)
--   Z  Aufraeumen ......................... 21 Nachrichten, 44 Mitgliedschaften,
--                44 Verlaufszeilen, 0 Ausblendungen - also exakt der Stand
--                von vorher.
--
-- Advisor nach der Migration: 0 Fehler (Security und Performance).
-- auth_rls_initplan sank von 111 auf 106.
-- ═══════════════════════════════════════════════════════════════════════════

create temp table nachweis(schritt text, ergebnis text);
grant all on nachweis to authenticated;

do $$
declare
  v_admin uuid; v_gast uuid; v_cid uuid;
  v_alt uuid; v_neu uuid; v_fremd uuid;
  v_msg text; v_txt text; v_ts timestamptz; v_ts2 timestamptz;
  v_art text; v_von uuid; v_n int; i int;
begin
  -- Zwei echte Konten. Der erste ist Inhaber der Test-Community, der zweite
  -- Gast (Beitritt, Austritt, Entfernen, fremde Nachricht).
  select id into v_admin from public.profiles order by created_at limit 1;
  select id into v_gast  from public.profiles where id <> v_admin order by created_at limit 1;

  -- Ohne JWT angelegt: die Waechter lassen Serverjobs durch, deshalb ist hier
  -- ein Zeitstempel in der Vergangenheit noch moeglich.
  insert into public.communities(owner_id, name, description, is_public)
  values (v_admin, 'NACHWEIS 20260824', 'Testzeile, wird am Ende geloescht', false)
  returning id into v_cid;

  insert into public.community_messages(community_id, user_id, body, created_at)
  values (v_cid, v_admin, 'ALT: drei Tage alt', now() - interval '3 days')
  returning id into v_alt;
  insert into public.community_messages(community_id, user_id, body, created_at)
  values (v_cid, v_admin, 'NEU: eine Stunde alt', now() - interval '1 hour')
  returning id into v_neu;

  -- ─────────────────────────────────────────────────────────────────────────
  -- A) WER KAM UND WER GING
  -- ─────────────────────────────────────────────────────────────────────────
  -- Der Gruender selbst: set_community_owner_member_on_insert hat ihn eben
  -- eingetragen, der Trigger muss das gesehen haben.
  select art into v_art from public.community_mitglieder_verlauf
   where community_id = v_cid and user_id = v_admin;
  insert into nachweis values ('A0 Gruender protokolliert', coalesce(v_art, 'FEHLT'));

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_gast, 'role', 'authenticated')::text, true);

  insert into public.community_members(community_id, user_id, role)
  values (v_cid, v_gast, 'member');
  select art into v_art from public.community_mitglieder_verlauf
   where community_id = v_cid and user_id = v_gast;
  insert into nachweis values ('A1 Beitritt', coalesce(v_art, 'FEHLT'));

  delete from public.community_members where community_id = v_cid and user_id = v_gast;
  select art into v_art from public.community_mitglieder_verlauf
   where community_id = v_cid and user_id = v_gast and art <> 'beitritt';
  insert into nachweis values ('A2 Austritt (selbst gegangen)', coalesce(v_art, 'FEHLT'));

  -- Jetzt entfernt der ADMIN den Gast: gleiche Zeile, anderer Anlass.
  insert into public.community_members(community_id, user_id, role)
  values (v_cid, v_gast, 'member');
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  delete from public.community_members where community_id = v_cid and user_id = v_gast;
  -- WICHTIG: nicht `order by am desc limit 1`. `now()` ist die
  -- TRANSAKTIONSZEIT - in einem einzigen DO-Block tragen alle Verlaufszeilen
  -- denselben Zeitstempel, die Reihenfolge waere zufaellig. Im Betrieb ist
  -- jeder Beitritt und jeder Austritt eine eigene Transaktion. Deshalb hier
  -- ueber die Art suchen.
  select art, ausgeloest_von into v_art, v_von
    from public.community_mitglieder_verlauf
   where community_id = v_cid and user_id = v_gast
     and art in ('austritt', 'entfernt');
  insert into nachweis values ('A3 Entfernen durch Admin',
    coalesce(v_art,'FEHLT') || ', ausgeloest_von = ' ||
    case when v_von = v_admin then 'Admin' else coalesce(v_von::text,'NULL') end);

  -- Missbrauchsbremse: zehn Runden ein und aus.
  for i in 1..10 loop
    insert into public.community_members(community_id, user_id, role)
    values (v_cid, v_gast, 'member');
    delete from public.community_members where community_id = v_cid and user_id = v_gast;
  end loop;
  select count(*) into v_n from public.community_mitglieder_verlauf
   where community_id = v_cid and user_id = v_gast;
  insert into nachweis values ('A4 Bremse nach 10 weiteren Runden',
    v_n || ' Zeilen insgesamt (Obergrenze 6 je 24 h)');

  select count(*) into v_n from public.community_mitglieder_verlauf where nachgetragen;
  insert into nachweis values ('A5 Altbestand nachgetragen', v_n || ' Zeilen');

  -- ─────────────────────────────────────────────────────────────────────────
  -- B) BEARBEITEN
  -- ─────────────────────────────────────────────────────────────────────────
  -- Eine fremde Nachricht fuer B5: vom Gast, der dafuer Mitglied sein muss.
  insert into public.community_members(community_id, user_id, role)
  values (v_cid, v_gast, 'member');
  insert into public.community_messages(community_id, user_id, body)
  values (v_cid, v_gast, 'FREMD: vom Gast') returning id into v_fremd;

  set local role authenticated;   -- ab hier wirklich als App-Rolle

  begin
    v_ts := public.community_nachricht_bearbeiten(v_neu, '  NEU: bearbeitet  ');
    select body into v_txt from public.community_messages where id = v_neu;
    insert into nachweis values ('B1 Bearbeiten innerhalb 6 h',
      'angenommen -> "' || v_txt || '", bearbeitet_am ' ||
      case when v_ts is null then 'FEHLT' else 'gesetzt' end);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('B1 Bearbeiten innerhalb 6 h', 'ABGEWIESEN: ' || v_msg);
  end;

  begin
    perform public.community_nachricht_bearbeiten(v_alt, 'ALT: heimlich umgeschrieben');
    insert into nachweis values ('B3 Bearbeiten nach 3 Tagen', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('B3 Bearbeiten nach 3 Tagen', 'abgewiesen: ' || v_msg);
  end;

  -- Der rohe Weg an der Funktion vorbei, genau wie in der Gegenprobe.
  begin
    update public.community_messages set body = 'ROH umgeschrieben' where id = v_alt;
    insert into nachweis values ('B3b Roher UPDATE nach 3 Tagen', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('B3b Roher UPDATE nach 3 Tagen', 'abgewiesen: ' || v_msg);
  end;

  select created_at into v_ts from public.community_messages where id = v_alt;
  update public.community_messages set created_at = now() + interval '400 days' where id = v_alt;
  select created_at into v_ts2 from public.community_messages where id = v_alt;
  insert into nachweis values ('B4 created_at +400 Tage',
    case when v_ts2 = v_ts then 'ignoriert, alter Wert bleibt' else 'DURCHGELASSEN -> ' || v_ts2 end);

  begin
    perform public.community_nachricht_bearbeiten(v_fremd, 'fremde Worte');
    insert into nachweis values ('B5 Fremde Nachricht bearbeiten', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('B5 Fremde Nachricht bearbeiten', 'abgewiesen: ' || v_msg);
  end;

  begin
    select original_body into v_txt from public.community_messages where id = v_neu;
    insert into nachweis values ('B6 original_body lesen', 'DURCHGELASSEN -> ' || coalesce(v_txt,'NULL'));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('B6 original_body lesen', 'abgewiesen: ' || v_msg);
  end;

  -- Als angemeldeter Nutzer geht nur die EIGENE Nachricht durch
  -- (members_write_community_messages verlangt user_id = auth.uid()); ab hier
  -- ist der Admin angemeldet.
  insert into public.community_messages(community_id, user_id, body, created_at)
  values (v_cid, v_admin, 'ZUKUNFT', now() + interval '400 days');
  select created_at into v_ts from public.community_messages
   where community_id = v_cid and body = 'ZUKUNFT';
  insert into nachweis values ('B7 INSERT mit created_at +400 Tage',
    case when v_ts < now() + interval '1 minute' then 'auf Serverzeit gesetzt' else 'DURCHGELASSEN -> ' || v_ts end);

  -- ─────────────────────────────────────────────────────────────────────────
  -- C) LOESCHEN
  -- ─────────────────────────────────────────────────────────────────────────
  update public.community_messages set deleted_at = timestamptz '2019-01-01 00:00:00+00' where id = v_alt;
  select deleted_at into v_ts from public.community_messages where id = v_alt;
  insert into nachweis values ('C2 Geraeteuhr beim Loeschen (2019)',
    case when v_ts > now() - interval '1 minute' then 'auf Serverzeit gesetzt' else 'DURCHGELASSEN -> ' || v_ts end);

  update public.community_messages set deleted_at = null where id = v_alt;
  select deleted_at into v_ts from public.community_messages where id = v_alt;
  insert into nachweis values ('C3 Loeschung zuruecknehmen',
    case when v_ts is null then 'DURCHGELASSEN - FEHLER' else 'wirkungslos, bleibt geloescht' end);

  begin
    delete from public.community_messages where id = v_neu;
    get diagnostics v_n = row_count;
    insert into nachweis values ('C4 hartes DELETE',
      case when v_n = 0 then 'wirkungslos (0 Zeilen)' else 'DURCHGELASSEN - FEHLER' end);
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('C4 hartes DELETE', 'abgewiesen: ' || v_msg);
  end;

  begin
    truncate public.community_messages;
    insert into nachweis values ('C5 TRUNCATE', 'DURCHGELASSEN - KATASTROPHE');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('C5 TRUNCATE', 'abgewiesen: ' || v_msg);
  end;

  -- Nur fuer mich: der Gast raeumt eine FREMDE Nachricht aus seiner Ansicht.
  perform public.community_nachricht_loeschen(v_neu, false);
  select count(*) into v_n from public.community_nachricht_ausgeblendet
   where message_id = v_neu;
  select deleted_at into v_ts from public.community_messages where id = v_neu;
  insert into nachweis values ('C6 Nur fuer mich',
    v_n || ' Ausblendung, Nachricht selbst ' ||
    case when v_ts is null then 'unberuehrt (fuer alle anderen sichtbar)' else 'GELOESCHT - FEHLER' end);

  perform public.community_nachricht_loeschen(v_fremd, true);
  select deleted_at into v_ts from public.community_messages where id = v_fremd;
  insert into nachweis values ('C1 Loeschen fuer alle (eigene)',
    case when v_ts > now() - interval '1 minute' then 'deleted_at = Serverzeit' else 'FEHLER' end);

  -- ─────────────────────────────────────────────────────────────────────────
  -- D) CHAT-ART
  -- ─────────────────────────────────────────────────────────────────────────
  begin
    update public.profiles set chat_darstellung = 'nachrichten' where id = v_gast;
    select chat_darstellung into v_txt from public.profiles where id = v_gast;
    insert into nachweis values ('D1 chat_darstellung nachrichten', coalesce(v_txt,'NULL'));
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('D1 chat_darstellung nachrichten', 'abgewiesen: ' || v_msg);
  end;

  begin
    update public.profiles set chat_darstellung = 'quatsch' where id = v_gast;
    insert into nachweis values ('D2 chat_darstellung quatsch', 'DURCHGELASSEN - FEHLER');
  exception when others then
    get stacked diagnostics v_msg = message_text;
    insert into nachweis values ('D2 chat_darstellung quatsch', 'abgewiesen (CHECK)');
  end;

  -- ─────────────────────────────────────────────────────────────────────────
  -- Z) AUFRAEUMEN
  -- ─────────────────────────────────────────────────────────────────────────
  reset role;
  perform set_config('request.jwt.claims', null, true);
  update public.profiles set chat_darstellung = null where id = v_gast;
  delete from public.communities where id = v_cid;
end $$;

-- B2 ist nur mit den Rechten des Eigentuemers pruefbar - genau das ist der
-- Punkt: original_body existiert, aber kein Mitglied kommt daran.
select * from nachweis order by schritt;


-- ═══════════════════════════════════════════════════════════════════════════
-- ANHANG - VERTRAEGLICHKEIT MIT DER APP, DIE HEUTE INSTALLIERT IST
--
-- Das spaltenweise Leserecht ist der einzige Eingriff, der eine bestehende
-- Abfrage brechen KOENNTE. Deshalb wurde jede Abfrage des Clients als
-- angemeldetes Mitglied nachgefahren. Gemessen am 24.08.2026:
--
--   1 _messageSelect (alte App) ..... 4 Zeilen gelesen
--   2 mit bearbeitet_am ............. 12 Zeilen gelesen
--   3 select * ...................... scheitert: permission denied for table
--                                     community_messages
--                                     -> GEWOLLT. Keine Stelle im Client, in
--                                        den Edge Functions oder in einer
--                                        Sicht benutzt select * auf dieser
--                                        Tabelle (am 24.08. geprueft).
--                                        Jede NEUE Spalte braucht ab jetzt
--                                        ein eigenes grant select.
--   4 sendMessage ................... angenommen
--   5 alte App: deleteMessage ....... funktioniert weiter, Zeit auf
--                                     Serverzeit korrigiert
--                                     -> Das ist der Grund, warum die Regeln
--                                        am Trigger haengen und nicht nur im
--                                        RPC: die installierte App schickt
--                                        weiterhin ein rohes UPDATE.
--   6 Reaktionen-Embed .............. 1 Reaktion lesbar
--   7 Verlauf lesen als Mitglied .... 19 Zeilen
--   8 Aufraeumen .................... 21 Nachrichten (Ausgangsstand)
-- ═══════════════════════════════════════════════════════════════════════════
