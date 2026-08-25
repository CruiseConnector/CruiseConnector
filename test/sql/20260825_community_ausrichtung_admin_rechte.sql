-- Nachweis zum Auftrag vom 25.08.2026: „der admin soll es bestimmen"
-- (Fahrzeugart und Region einer BESTEHENDEN Community aendern).
--
-- ES GIBT ZU DIESEM AUFTRAG KEINE MIGRATION, und genau das belegt diese
-- Datei. Auf `public.communities` gilt seit dem 23.08.2026 ein SPALTENWEISES
-- Schreibrecht — ein fehlender Grant haette hier stillschweigend zugeschlagen
-- und die App haette eine Aenderung angezeigt, die nie gespeichert wurde.
-- Deshalb ist das Recht gemessen und nicht angenommen.
--
-- Belegt an der ECHTEN Datenbank:
--   A  `authenticated` hat `update` UND `select` auf `fahrzeugart` und
--      `region_code`.
--   B  Als Besitzer geht das Aendern durch (eine Zeile zurueck).
--   C  Als Mitglied ohne Admin-Rolle kommen NULL Zeilen zurueck, OHNE Fehler.
--      Das ist die Falle: ohne `.select('id')` im Dienst saehe das aus wie ein
--      Erfolg. Ursache ist die Zeilenregel `leaders_update_communities`, die
--      `is_community_admin` verlangt — und das ist ausschliesslich `owner`,
--      nicht `moderator` (`is_community_owner` waere hier zu weit).
--   D  Eine erfundene Region wird vom Fremdschluessel abgewiesen (23503).
--   E  Eine erfundene Fahrzeugart wird von der CHECK-Regel abgewiesen (23514).
--   F  Nach der Aenderung liefert `get_communities_gefiltert` die NEUEN Werte
--      samt `region_name` — die Kachel in der Uebersicht zeigt also nach dem
--      Neuladen nicht mehr den alten Wert.
--
-- Alles laeuft in einer Untertransaktion, die am Ende zurueckgenommen wird.
-- Keine Community bleibt veraendert stehen.
--
-- Ausfuehren ueber den Supabase-MCP (Projekt tlcfaxvvqzobmzwvfnvb).
-- Gruen = laeuft durch ohne Meldung. Rot = wirft „TEST ROT" mit der Liste.
--
-- FALLE, die dieser Test umgeht: die MCP-Verbindung laeuft als `postgres` mit
-- BYPASSRLS. Fuer alles, was ein Nutzer selbst tut, wird deshalb
-- `set local role authenticated` plus `request.jwt.claims` gesetzt.

do $pruefung$
declare
  v_community   uuid;
  v_owner       uuid;
  v_mitglied    uuid;
  v_region      text;
  v_zeilen      integer;
  v_code        text;
  v_liste       jsonb;
  v_zeile       jsonb;
  v_fehler      text := '';
begin
  -- Eine Community mit Besitzer UND einem einfachen Mitglied.
  select c.id, c.owner_id, m.user_id
    into v_community, v_owner, v_mitglied
  from public.communities c
  join public.community_members m
    on m.community_id = c.id and m.role = 'member'
  order by c.created_at
  limit 1;

  if v_community is null then
    raise exception 'TEST ROT: keine Community mit einfachem Mitglied gefunden.';
  end if;

  -- Irgendein Bundesland, damit der Fremdschluessel haelt.
  select code into v_region
  from public.community_regionen
  where ist_land = false
  order by code
  limit 1;

  ------------------------------------------------------------------------ A
  if not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'communities'
      and grantee = 'authenticated' and privilege_type = 'UPDATE'
      and column_name = 'fahrzeugart'
  ) then
    v_fehler := v_fehler || E'\n  A1: kein update-Recht auf fahrzeugart.';
  end if;
  if not exists (
    select 1 from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'communities'
      and grantee = 'authenticated' and privilege_type = 'UPDATE'
      and column_name = 'region_code'
  ) then
    v_fehler := v_fehler || E'\n  A2: kein update-Recht auf region_code.';
  end if;
  if (
    select count(*) from information_schema.column_privileges
    where table_schema = 'public' and table_name = 'communities'
      and grantee = 'authenticated' and privilege_type = 'SELECT'
      and column_name in ('fahrzeugart', 'region_code')
  ) <> 2 then
    v_fehler := v_fehler ||
      E'\n  A3: kein Leserecht auf fahrzeugart/region_code — die '
      'Einstellungs-Seite koennte die Werte gar nicht anzeigen.';
  end if;

  begin
    ---------------------------------------------------------------------- B
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', v_owner, 'role', 'authenticated')::text,
      true);
    set local role authenticated;

    update public.communities
       set fahrzeugart = 'motorcycle', region_code = v_region
     where id = v_community;
    get diagnostics v_zeilen = row_count;
    if v_zeilen <> 1 then
      v_fehler := v_fehler || format(
        E'\n  B: der Besitzer kam nicht durch (%s Zeilen).', v_zeilen);
    end if;

    ---------------------------------------------------------------------- D
    v_code := '';
    begin
      update public.communities set region_code = 'ZZ-99' where id = v_community;
    exception when others then v_code := sqlstate;
    end;
    if v_code <> '23503' then
      v_fehler := v_fehler || format(
        E'\n  D: erfundene Region wurde nicht abgewiesen (%s).', v_code);
    end if;

    ---------------------------------------------------------------------- E
    v_code := '';
    begin
      update public.communities set fahrzeugart = 'auto' where id = v_community;
    exception when others then v_code := sqlstate;
    end;
    if v_code <> '23514' then
      v_fehler := v_fehler || format(
        E'\n  E: erfundene Fahrzeugart wurde nicht abgewiesen (%s).', v_code);
    end if;

    ---------------------------------------------------------------------- F
    v_liste := public.get_communities_gefiltert('meine', null, null, null,
                                                'aktiv', 100, 0);
    select w into v_zeile
    from jsonb_array_elements(v_liste) w
    where (w ->> 'id')::uuid = v_community;

    if v_zeile is null then
      v_fehler := v_fehler ||
        E'\n  F1: die geaenderte Community steht nicht in der eigenen Liste.';
    else
      if v_zeile ->> 'fahrzeugart' <> 'motorcycle' then
        v_fehler := v_fehler || format(
          E'\n  F2: die Liste zeigt weiter die alte Fahrzeugart (%s).',
          v_zeile ->> 'fahrzeugart');
      end if;
      if v_zeile ->> 'region_code' is distinct from v_region then
        v_fehler := v_fehler || format(
          E'\n  F3: die Liste zeigt weiter die alte Region (%s).',
          coalesce(v_zeile ->> 'region_code', '<leer>'));
      end if;
      if coalesce(v_zeile ->> 'region_name', '') = '' then
        v_fehler := v_fehler ||
          E'\n  F4: region_name fehlt — die Kachel haette keinen Namen.';
      end if;
    end if;

    ---------------------------------------------------------------------- C
    reset role;
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', v_mitglied, 'role', 'authenticated')::text,
      true);
    set local role authenticated;

    v_code := '';
    begin
      update public.communities set fahrzeugart = 'car' where id = v_community;
      get diagnostics v_zeilen = row_count;
    exception when others then
      v_code := sqlstate;
      v_zeilen := -1;
    end;
    if v_code <> '' then
      v_fehler := v_fehler || format(
        E'\n  C1: das Mitglied bekam einen Fehler (%s) statt null Zeilen. '
        'Dann greift der Rueckfall im Dienst nicht.', v_code);
    elsif v_zeilen <> 0 then
      v_fehler := v_fehler || format(
        E'\n  C2: ein einfaches Mitglied durfte aendern (%s Zeilen).',
        v_zeilen);
    end if;

    reset role;

    -- Alles zurueck. Die Ausnahme nimmt die Untertransaktion zurueck,
    -- die Variablen ueberleben sie.
    raise exception 'RUECKNAHME';

  exception when others then
    if sqlerrm <> 'RUECKNAHME' then
      raise;
    end if;
  end;

  if v_fehler <> '' then
    raise exception E'TEST ROT:%', v_fehler;
  end if;
end
$pruefung$;
