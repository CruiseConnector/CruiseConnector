-- Nachweis zu Migration 20260825100000_benutzername_umlaute_und_verwechslungsschutz.sql
--
-- Belegt an der ECHTEN Datenbank:
--   * "müller" laesst sich anlegen (Umlaute sind erlaubt),
--   * danach sind "mueller" und "Müller" BELEGT (nichts Verwechselbares),
--   * ein kyrillisches "а" wird abgewiesen (kein Nachbauen fremder Namen),
--   * die 30-Tage-Sperre haelt weiterhin.
--
-- Alles laeuft in einer Untertransaktion, die am Ende zurueckgenommen wird.
-- Die angelegten Probe-Konten und Probe-Profile bleiben NICHT stehen.
--
-- Ausfuehren ueber den Supabase-MCP (Projekt tlcfaxvvqzobmzwvfnvb).
-- Gruen = laeuft durch und meldet "ALLE PROBEN GRUEN".
-- Rot   = wirft "TEST ROT" und listet die abweichenden Proben.
-- HINWEIS: Ueber den MCP kommen NOTICE-Zeilen nicht zurueck. Wer das
-- Protokoll mitlesen will, macht aus der letzten Zeile
--   raise notice 'ALLE PROBEN GRUEN';
-- ein
--   raise exception E'ALLE PROBEN GRUEN\nPROTOKOLL:%', v_protokoll;
-- (nur zum Anschauen, nicht einchecken).
--
-- GEGENPROBE (ausgefuehrt am 25.08.2026 gegen die unveraenderte Datenbank,
-- also VOR der Migration): SECHZEHN Meldungen, naemlich C, I1, I2, A1, A2,
-- A3, A5, B1, D1, D2, E1 (zweimal), E4, F1, F2, F3.
-- Die drei lehrreichsten:
--   * D1: ohne den Riegel laesst sich "mueller" NEBEN "müller" anlegen -
--     genau die Verwechslung, um die es geht. Protokoll: "DURCHGELASSEN".
--   * F1: set_username("Mueller") lief durch und vergab den Namen, obwohl
--     "müller" schon existierte.
--   * I2: meldet sich jemand ueber Google mit einem Namen an, den es schon
--     gibt, entsteht heute UEBERHAUPT KEIN PROFIL ("<KEIN PROFIL>").
--     handle_new_user faengt die Kollision ganz unten ab und loggt nur eine
--     Warnung.
-- Gruen sind in der Gegenprobe A4, B2, B3, D3, E2, E3, G - die Wege also,
-- die weiterlaufen muessen und weiterlaufen.
--
-- UND EIN BEFUND AUS DEM ERSTEN GRUENEN LAUF: Probe H war auch NACH der
-- Migration zunaechst rot ("Name jetzt Hackernäme"). Nicht wegen des
-- Guard-Triggers, sondern weil set_username das Durchlass-Flag
-- `app.username_change_ok` setzte und nie wieder loeschte - es galt damit
-- bis zum Ende der Transaktion. Wer im selben Vorgang nach set_username
-- noch ein direktes UPDATE absetzte, kam an der 30-Tage-Sperre vorbei.
-- Geschlossen in Abschnitt 5 der Migration.
--
-- ZWEI FALLEN, die dieser Test bewusst umgeht:
--   1. Die MCP-Verbindung laeuft als `postgres` mit BYPASSRLS. Fuer alles,
--      was ein Nutzer selbst tut (set_username, username_available, ein
--      direktes UPDATE), wird deshalb `set local role authenticated` plus
--      `request.jwt.claims` gesetzt.
--   2. Kyrillische und griechische Buchstaben sehen im Editor aus wie
--      lateinische - genau das ist ja das Problem. Sie werden hier deshalb
--      ueber chr() gebaut, damit im Text steht, was gemeint ist.

do $pruefung$
declare
  -- Probe-Konten (werden angelegt und wieder zurueckgenommen)
  v_u1 constant uuid := '00000000-0000-4000-8000-0000aaaa0001';
  v_u2 constant uuid := '00000000-0000-4000-8000-0000aaaa0002';
  v_u3 constant uuid := '00000000-0000-4000-8000-0000aaaa0003';
  v_u4 constant uuid := '00000000-0000-4000-8000-0000aaaa0004';
  v_u5 constant uuid := '00000000-0000-4000-8000-0000aaaa0005';

  -- 'mаller' mit KYRILLISCHEM а (U+0430) an zweiter Stelle
  v_kyrillisch  constant text := 'm' || chr(1072) || 'ller';
  -- 'αlpha_probe' mit GRIECHISCHEM alpha (U+03B1)
  v_griechisch  constant text := chr(945) || 'lpha_probe';

  v_protokoll text := '';
  v_fehler    text := '';
  v_code      text;
  v_name      text;
  v_hat_faltung boolean;
  j           jsonb;
  n           bigint;
begin
  v_hat_faltung := to_regprocedure('public.benutzername_schluessel(text)') is not null;
  if not v_hat_faltung then
    v_fehler := v_fehler || E'\n  C: public.benutzername_schluessel(text) gibt es nicht.';
  end if;

  begin
    ------------------------------------------------------------------ Aufbau
    -- Fuenf Probe-Konten. Der Trigger on_auth_user_created legt zu jedem
    -- ein Profil an (handle_new_user).
    insert into auth.users (id, email, raw_user_meta_data) values
      (v_u1, 'zzprobe1@example.invalid', jsonb_build_object('username', 'zzprobe_eins')),
      (v_u2, 'zzprobe2@example.invalid', jsonb_build_object('username', 'zzprobe_zwei')),
      (v_u3, 'zzprobe3@example.invalid', jsonb_build_object('username', 'zzprobe_drei')),
      (v_u4, 'zzprobe4@example.invalid', jsonb_build_object('name',     'Jörg Müller')),
      (v_u5, 'zzprobe5@example.invalid', jsonb_build_object('username', 'zzprobe_eins'));

    ---------------------------------------------------------------- I  Anmeldung
    -- I1: der Umlaut aus dem Google-/Apple-Namen bleibt stehen.
    select username into v_name from public.profiles where id = v_u4;
    v_protokoll := v_protokoll || format(
      E'\nI1 Anmeldung "Jörg Müller" ergibt ............. %s (erwartet Jörg_Müller)',
      coalesce(v_name, '<kein Profil>'));
    if coalesce(v_name, '') <> 'Jörg_Müller' then
      v_fehler := v_fehler || E'\n  I1: Umlaut aus dem Anbieter-Namen geht beim Anmelden verloren.';
    end if;

    -- I2: schon vergebener Name darf die Anmeldung nicht ausfallen lassen.
    select username into v_name from public.profiles where id = v_u5;
    v_protokoll := v_protokoll || format(
      E'\nI2 Anmeldung mit belegtem Namen ergibt ........ %s (erwartet zzprobe_eins + Kennung)',
      coalesce(v_name, '<KEIN PROFIL>'));
    if v_name is null then
      v_fehler := v_fehler || E'\n  I2: Bei belegtem Namen entsteht gar kein Profil.';
    elsif v_name = 'zzprobe_eins' then
      v_fehler := v_fehler || E'\n  I2: Zwei Profile tragen denselben Namen.';
    elsif v_name not like 'zzprobe_eins%' then
      v_fehler := v_fehler || E'\n  I2: Ausweichname hat nichts mehr mit dem Wunsch zu tun.';
    end if;

    ---------------------------------------------------------------- A  Format
    -- A1/A2/A3: die deutschen Sonderzeichen sind erlaubt.
    if not public.is_valid_username_format('müller') then
      v_fehler := v_fehler || E'\n  A1: "müller" gilt als ungueltig.'; end if;
    if not public.is_valid_username_format('Grüße_12') then
      v_fehler := v_fehler || E'\n  A2: "Grüße_12" gilt als ungueltig.'; end if;
    if not public.is_valid_username_format('KURVENKÖNIG') then
      v_fehler := v_fehler || E'\n  A3: "KURVENKÖNIG" gilt als ungueltig.'; end if;
    v_protokoll := v_protokoll || format(
      E'\nA1 müller / Grüße_12 / KURVENKÖNIG gueltig ..... %s / %s / %s (erwartet 3x t)',
      public.is_valid_username_format('müller'),
      public.is_valid_username_format('Grüße_12'),
      public.is_valid_username_format('KURVENKÖNIG'));

    -- A4: alles andere bleibt draussen. Das ist der Kern des Ganzen:
    -- kyrillisch, griechisch, Akzente, Emoji, Leerzeichen, Punkt, Minus.
    v_protokoll := v_protokoll || format(
      E'\nA4 kyr. / griech. / é / Emoji / Leerz. / Punkt . %s / %s / %s / %s / %s / %s (erwartet 6x f)',
      public.is_valid_username_format(v_kyrillisch),
      public.is_valid_username_format(v_griechisch),
      public.is_valid_username_format('café_fahrer'),
      public.is_valid_username_format('max' || chr(128512)),
      public.is_valid_username_format('max mueller'),
      public.is_valid_username_format('max.mueller'));
    if public.is_valid_username_format(v_kyrillisch)
       or public.is_valid_username_format(v_griechisch)
       or public.is_valid_username_format('café_fahrer')
       or public.is_valid_username_format('max' || chr(128512))
       or public.is_valid_username_format('max mueller')
       or public.is_valid_username_format('max.mueller')
       or public.is_valid_username_format('max-mueller')
    then
      v_fehler := v_fehler || E'\n  A4: Ein nicht-deutsches Sonderzeichen kommt durch.';
    end if;

    -- A5: die alten Regeln gelten unveraendert weiter.
    if public.is_valid_username_format('ab')            -- zu kurz
       or public.is_valid_username_format(repeat('ä', 21))  -- zu lang
       or public.is_valid_username_format('_mueller')   -- Unterstrich vorne
       or public.is_valid_username_format('mueller_')   -- Unterstrich hinten
       or public.is_valid_username_format('mu__ller')   -- doppelter Unterstrich
       or coalesce(public.is_valid_username_format(null), true)
    then
      v_fehler := v_fehler || E'\n  A5: Laenge/Unterstrich/NULL werden nicht mehr geprueft.';
    end if;

    ------------------------------------------------------------- B  CHECK
    -- B1: der CHECK an der Tabelle laesst den Umlaut zu.
    v_code := null;
    begin
      update public.profiles set username = 'müller' where id = v_u1;
    exception when others then v_code := sqlstate;
    end;
    v_protokoll := v_protokoll || format(
      E'\nB1 profiles.username = "müller" .............. %s (erwartet ohne Fehler)',
      coalesce(v_code, 'ok'));
    if v_code is not null then
      v_fehler := v_fehler || format(E'\n  B1: Umlaut am CHECK abgewiesen (%s).', v_code); end if;

    -- B2: das kyrillische а wird abgewiesen. GEMESSEN, nicht angenommen -
    -- ob [A-Za-z] Umlaute trifft, haengt an der Sortierfolge, deshalb
    -- prueft der CHECK mit translate ueber die Codepunkte.
    v_code := null;
    begin
      update public.profiles set username = v_kyrillisch where id = v_u2;
    exception when others then v_code := sqlstate;
    end;
    v_protokoll := v_protokoll || format(
      E'\nB2 profiles.username = kyrillisch ............ %s (erwartet 23514)',
      coalesce(v_code, 'DURCHGELASSEN'));
    if v_code is distinct from '23514' then
      v_fehler := v_fehler || E'\n  B2: Kyrillisch kommt in die Tabelle.'; end if;

    -- B3: Emoji ebenso.
    v_code := null;
    begin
      update public.profiles set username = 'max' || chr(128512) where id = v_u2;
    exception when others then v_code := sqlstate;
    end;
    if v_code is distinct from '23514' then
      v_fehler := v_fehler || E'\n  B3: Emoji kommt in die Tabelle.'; end if;

    -------------------------------------------------------------- C  Faltung
    if v_hat_faltung then
      v_protokoll := v_protokoll || format(
        E'\nC  Faltung Müller / MUELLER / Straße / A_b .... %s / %s / %s / %s',
        public.benutzername_schluessel('Müller'),
        public.benutzername_schluessel('MUELLER'),
        public.benutzername_schluessel('Straße'),
        public.benutzername_schluessel('A_b'));
      if public.benutzername_schluessel('Müller') <> 'mueller'
         or public.benutzername_schluessel('MUELLER') <> 'mueller'
         or public.benutzername_schluessel('Straße') <> 'strasse'
         -- Der Unterstrich muss stehen bleiben. Hashtags kennen ihn nicht,
         -- Benutzernamen schon - deshalb eine eigene Faltung.
         or public.benutzername_schluessel('A_b') <> 'a_b'
      then
        v_fehler := v_fehler || E'\n  C: Die Faltung liefert nicht die erwartete Vergleichsform.';
      end if;
    end if;

    --------------------------------------------------------------- D  Riegel
    -- u1 heisst jetzt "müller" (B1).
    -- D1: "mueller" darf daneben NICHT mehr existieren.
    v_code := null;
    begin
      update public.profiles set username = 'mueller' where id = v_u2;
    exception when others then v_code := sqlstate;
    end;
    v_protokoll := v_protokoll || format(
      E'\nD1 "mueller" neben "müller" .................. %s (erwartet 23505)',
      coalesce(v_code, 'DURCHGELASSEN'));
    if v_code is distinct from '23505' then
      v_fehler := v_fehler || E'\n  D1: "mueller" steht neben "müller" - genau die Verwechslung.';
    end if;

    -- D2: "Müller" (nur andere Gross-/Kleinschreibung) ebenso wenig.
    v_code := null;
    begin
      update public.profiles set username = 'Müller' where id = v_u2;
    exception when others then v_code := sqlstate;
    end;
    v_protokoll := v_protokoll || format(
      E'\nD2 "Müller" neben "müller" ................... %s (erwartet 23505)',
      coalesce(v_code, 'DURCHGELASSEN'));
    if v_code is distinct from '23505' then
      v_fehler := v_fehler || E'\n  D2: "Müller" steht neben "müller".'; end if;

    -- D3: "muller" ist ein ANDERER Name und muss weiter gehen. Der Riegel
    -- darf nicht mehr sperren als noetig.
    v_code := null;
    begin
      update public.profiles set username = 'muller' where id = v_u2;
    exception when others then v_code := sqlstate;
    end;
    v_protokoll := v_protokoll || format(
      E'\nD3 "muller" neben "müller" ................... %s (erwartet ohne Fehler)',
      coalesce(v_code, 'ok'));
    if v_code is not null then
      v_fehler := v_fehler || E'\n  D3: "muller" wird mitgesperrt, obwohl es ein anderer Name ist.';
    end if;
    update public.profiles set username = 'zzprobe_zwei' where id = v_u2;

    ------------------------------------------------------- E  username_available
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_u3, 'role', 'authenticated')::text, true);

    -- E1: "mueller" und "Müller" sind fuer alle anderen belegt.
    j := public.username_available('mueller');
    v_protokoll := v_protokoll || format(
      E'\nE1 username_available("mueller") ............. %s (erwartet taken)', j);
    if (j->>'available')::boolean or j->>'reason' <> 'taken' then
      v_fehler := v_fehler || E'\n  E1: "mueller" gilt als frei, obwohl "müller" existiert.'; end if;

    j := public.username_available('Müller');
    if (j->>'available')::boolean or j->>'reason' <> 'taken' then
      v_fehler := v_fehler || E'\n  E1: "Müller" gilt als frei, obwohl "müller" existiert.'; end if;

    -- E2: kyrillisch wird schon am Format abgewiesen.
    j := public.username_available(v_kyrillisch);
    v_protokoll := v_protokoll || format(
      E'\nE2 username_available(kyrillisch) ............ %s (erwartet invalid_format)', j);
    if (j->>'available')::boolean or j->>'reason' <> 'invalid_format' then
      v_fehler := v_fehler || E'\n  E2: Kyrillisch gilt als moeglicher Name.'; end if;

    -- E3: gesperrte Namen bleiben gesperrt.
    j := public.username_available('Admin');
    if (j->>'available')::boolean or j->>'reason' <> 'reserved' then
      v_fehler := v_fehler || E'\n  E3: Gesperrter Name "Admin" gilt als frei.'; end if;

    -- E4: ein freier Name mit Umlaut ist frei.
    j := public.username_available('Kurvenkönig_zz');
    v_protokoll := v_protokoll || format(
      E'\nE4 username_available("Kurvenkönig_zz") ...... %s (erwartet ok)', j);
    if not (j->>'available')::boolean then
      v_fehler := v_fehler || E'\n  E4: Ein freier Umlaut-Name gilt als nicht verfuegbar.'; end if;

    ------------------------------------------------------------ F  set_username
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_u2, 'role', 'authenticated')::text, true);

    -- F1: der belegte Name wird sauber abgelehnt (nicht mit einer Ausnahme).
    j := public.set_username('Mueller');
    v_protokoll := v_protokoll || format(
      E'\nF1 set_username("Mueller") ................... %s (erwartet taken)', j);
    if (j->>'ok')::boolean or j->>'error' <> 'taken' then
      v_fehler := v_fehler || E'\n  F1: Ein verwechselbarer Name wird vergeben.'; end if;

    -- F2: der eigene Umlaut-Name geht durch UND wird so gespeichert, wie er
    -- getippt wurde. Angezeigt wird die Schreibweise, gefaltet nur der
    -- Vergleich.
    j := public.set_username('Bärenkäfig');
    v_protokoll := v_protokoll || format(
      E'\nF2 set_username("Bärenkäfig") ................ %s (erwartet ok)', j);
    if not (j->>'ok')::boolean then
      v_fehler := v_fehler || E'\n  F2: Ein Name mit Umlauten laesst sich nicht setzen.'; end if;

    -- F3: 30-Tage-Sperre haelt - auch direkt nach der Umbenennung.
    j := public.set_username('Kurvenkönig_zz');
    v_protokoll := v_protokoll || format(
      E'\nF3 zweite Umbenennung sofort danach .......... %s (erwartet too_soon)', j);
    if (j->>'ok')::boolean or j->>'error' <> 'too_soon' then
      v_fehler := v_fehler || E'\n  F3: Die 30-Tage-Sperre ist ausgehebelt.'; end if;

    -- G: username_change_status sagt dasselbe.
    j := public.username_change_status();
    if (j->>'can_change')::boolean then
      v_fehler := v_fehler || E'\n  G: username_change_status meldet "darf aendern" trotz Sperre.'; end if;

    ------------------------------------------------------------------ H  Guard
    -- Ein direktes UPDATE am Profil darf den Namen NICHT aendern - sonst
    -- waere die 30-Tage-Sperre mit einem Zeilenumbruch zu umgehen.
    -- Die Probe misst nebenbei mit, dass das Schreiben an der Tabelle als
    -- `authenticated` ueberhaupt durchgeht (Ausfuehrungsrecht auf die
    -- Faltung im Index, siehe Migration Abschnitt 1).
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_u3, 'role', 'authenticated')::text, true);
    v_code := null;
    begin
      update public.profiles set username = 'Hackernäme' where id = v_u3;
    exception when others then v_code := sqlstate || ': ' || sqlerrm;
    end;

    execute 'set local role postgres';
    perform set_config('request.jwt.claims', '', true);
    select username into v_name from public.profiles where id = v_u3;
    v_protokoll := v_protokoll || format(
      E'\nH  Direktes UPDATE am Namen ................... %s / Name jetzt %s (erwartet zzprobe_drei)',
      coalesce(v_code, 'ohne Fehler'), v_name);
    if v_name <> 'zzprobe_drei' then
      v_fehler := v_fehler || E'\n  H: Der Guard laesst ein direktes UPDATE des Namens durch.'; end if;
    if v_code like '42501%' then
      v_fehler := v_fehler || format(
        E'\n  H: Schreiben am Profil scheitert am Ausfuehrungsrecht (%s).', v_code); end if;

    -------------------------------------------------------------------- J  Recht
    -- Der Index wertet die Faltung bei JEDEM Schreiben aus und prueft dabei
    -- das Ausfuehrungsrecht. Diese Probe misst das an einer Wegwerf-Tabelle,
    -- damit der Befund eindeutig ist und nicht an RLS haengt.
    if v_hat_faltung then
      create temp table zz_probe_recht(t text) on commit drop;
      create unique index zz_probe_recht_ix on zz_probe_recht (public.benutzername_schluessel(t));
      grant insert on zz_probe_recht to authenticated;
      v_code := null;
      begin
        execute 'set local role authenticated';
        insert into zz_probe_recht(t) values ('Müller');
      exception when others then v_code := sqlstate;
      end;
      execute 'set local role postgres';
      v_protokoll := v_protokoll || format(
        E'\nJ  Schreiben in einen Index ueber der Faltung .. %s (erwartet ohne Fehler)',
        coalesce(v_code, 'ok'));
      if v_code is not null then
        v_fehler := v_fehler || format(
          E'\n  J: authenticated darf nicht in eine Tabelle mit diesem Index schreiben (%s).', v_code);
      end if;
    end if;

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
