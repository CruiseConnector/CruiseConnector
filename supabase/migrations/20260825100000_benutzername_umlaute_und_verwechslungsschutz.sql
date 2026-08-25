-- ============================================================================
-- Benutzernamen duerfen deutsche Umlaute tragen - ohne dass zwei Leute
-- danach verwechselbar heissen.
--
-- Vucko am 25.08.2026: "schau auch noch das man beim benutzernamen aeoeue
-- verwenden kann das ist bis jetzt nicht gegangen".
--
-- Umlaute zuzulassen waere ein Zweizeiler. Das eigentliche Problem ist ein
-- anderes: sobald "müller" moeglich ist, sieht er neben "mueller" in einer
-- Liste fast gleich aus. Wer eine Nachricht von "@müller" bekommt, glaubt,
-- sie kommt von "@mueller". Deshalb sind hier ZWEI Dinge geregelt, und das
-- zweite ist das wichtigere:
--
--   1. ERLAUBT werden genau die deutschen Sonderzeichen: ä ö ü Ä Ö Ü ß.
--      Sonst NICHTS Neues. Kein Kyrillisch, kein Griechisch, keine Emoji -
--      das kyrillische "а" sieht aus wie das lateinische "a", damit liesse
--      sich jeder Name Zeichen fuer Zeichen nachbauen. Genau deshalb lassen
--      Instagram und X ueberhaupt nur ASCII zu.
--
--   2. Die EINDEUTIGKEIT faltet Umlaute UND Gross-/Kleinschreibung.
--      Ist "mueller" vergeben, ist "müller" nicht mehr frei - und umgekehrt.
--      "Müller" ebenso wenig. ANGEZEIGT wird immer, was der Nutzer getippt
--      hat; gefaltet wird nur fuer den Vergleich.
--
-- Das Muster ist nicht neu erfunden: `public.hashtag_schluessel` aus
-- 20260824102000 macht fuer Hashtags dasselbe (#Kurvenkoenig = #Kurvenkönig).
--
-- BESTAND, gemessen am 25.08.2026 vor dieser Migration:
--   199 Profile, alle mit Namen. 0 davon mit einem Sonderzeichen, 0 mit
--   einem Unterstrich-Regelbruch, 0 ausserhalb 3..20 Zeichen und
--   0 Paare, die nach der Faltung zusammenfallen. Der Riegel kann also
--   scharf gestellt werden, ohne irgendjemandem den Namen zu nehmen.
--
-- Nachweis: test/sql/20260825_benutzername_umlaute.sql
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Die Faltung
-- ----------------------------------------------------------------------------
-- WARUM EINE EIGENE FUNKTION UND NICHT `hashtag_schluessel`?
-- Die Faltung steht gleich in einem UNIQUE-Index. Ein Index ueber einen
-- Funktionsaufruf ist nur so lange gueltig, wie die Funktion dasselbe
-- Ergebnis liefert: wer sie spaeter aendert, macht den Index still und
-- leise falsch, ohne dass irgendetwas meckert. `hashtag_schluessel` gehoert
-- den Hashtags und wird sich mit ihnen weiterentwickeln (Akzente, æ, ø, å -
-- alles Zeichen, die in einem Benutzernamen gar nicht vorkommen duerfen).
-- Deshalb bekommen Benutzernamen ihre EIGENE Faltung, die genau die sieben
-- erlaubten Sonderzeichen kennt und sonst nichts. Wer eine der beiden
-- Funktionen aendert, aendert damit nicht versehentlich die andere.
--
-- WICHTIG: Wer diese Funktion je aendert, muss danach
--   reindex index concurrently public.ux_profiles_username_schluessel;
-- laufen lassen. Sonst haelt der Riegel nicht mehr, was er verspricht.
create or replace function public.benutzername_schluessel(p_name text)
returns text
language sql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $fn$
  select replace(replace(replace(replace(
           lower(p_name),
           'ä', 'ae'), 'ö', 'oe'), 'ü', 'ue'), 'ß', 'ss');
$fn$;

comment on function public.benutzername_schluessel(text) is
  '2026-08-25: Faltet einen Benutzernamen auf seine Vergleichsform - klein '
  'geschrieben, ae/oe/ue/ss ausgeschrieben. "Müller", "MUELLER" und '
  '"mueller" ergeben denselben Schluessel und koennen deshalb nicht '
  'nebeneinander existieren. Vorbild: public.hashtag_schluessel(text). '
  'ACHTUNG: steckt in ux_profiles_username_schluessel - nach jeder Aenderung '
  'den Index neu bauen.';

-- RECHTE - hier steckt eine Falle, die gemessen wurde:
-- `hashtag_schluessel` ist fuer `authenticated` gesperrt. Solange die
-- Funktion nur in Abfragen vorkommt, ist das richtig. Sobald sie aber in
-- einem INDEX steht, wertet Postgres sie bei JEDEM Schreibvorgang auf der
-- Tabelle aus - UND PRUEFT DABEI DAS AUSFUEHRUNGSRECHT. Gemessen am
-- 25.08.2026 an einer Wegwerf-Tabelle mit einem Index ueber
-- hashtag_schluessel: ein INSERT als `authenticated` scheitert mit
--   FEHLER 42501: permission denied for function hashtag_schluessel
-- Ohne das Recht wuerde also irgendwann ein harmloses Speichern im Profil
-- (Avatar, Fahrzeug) mit "Zugriff verweigert" abbrechen - sobald die
-- Zeile nicht mehr am Index vorbei geschrieben werden kann.
-- Deshalb: anon und public bleiben draussen, `authenticated` bekommt das
-- Recht. Aufgerufen werden soll die Funktion vom Client trotzdem nicht -
-- gefragt wird ueber username_available, damit App und Datenbank nicht
-- mit zwei verschiedenen Faltungen arbeiten.
revoke all on function public.benutzername_schluessel(text) from public, anon;
grant execute on function public.benutzername_schluessel(text) to authenticated, service_role;


-- ----------------------------------------------------------------------------
-- 2. Welche Zeichen ueberhaupt erlaubt sind
-- ----------------------------------------------------------------------------
-- DIE FALLE: `username ~ '^[A-Za-z0-9_]+$'` sieht eindeutig aus, ist es aber
-- nicht. Ob ein Bereich wie [A-Za-z] auch Umlaute mitnimmt, haengt in
-- Postgres an der Sortierfolge der Datenbank. Gemessen am 25.08.2026 auf
-- en_US.UTF-8: 'ä' ~ '^[A-Za-z]+$' ist FALSE - hier trifft der Bereich also
-- nur ASCII. Verlassen wollen wir uns darauf nicht: eine wiederhergestellte
-- Datenbank mit anderer Sortierfolge wuerde die Regel klammheimlich
-- aufweichen und ploetzlich jeden Akzentbuchstaben durchlassen.
--
-- Deshalb wird nicht mit Bereichen geprueft, sondern mit `translate`:
-- alle erlaubten Zeichen werden aus dem Namen geloescht. Bleibt danach ein
-- Rest uebrig, stand darin ein Zeichen, das nicht erlaubt ist. Das
-- vergleicht Zeichen fuer Zeichen ueber den Codepunkt und ist von jeder
-- Sortierfolge unabhaengig.
-- Gemessen: das kyrillische 'а' (U+0430) bleibt stehen und wird abgewiesen -
-- das lateinische 'a' nicht.

alter table public.profiles drop constraint if exists profiles_username_format;

alter table public.profiles add constraint profiles_username_format check (
  username is not null
  and char_length(username) >= 3
  and char_length(username) <= 20
  and translate(
        username,
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_äöüÄÖÜß',
        ''
      ) = ''
);

comment on constraint profiles_username_format on public.profiles is
  '2026-08-25: 3 bis 20 Zeichen aus A-Z a-z 0-9 _ und den deutschen '
  'Sonderzeichen ä ö ü Ä Ö Ü ß. Geprueft mit translate statt mit einem '
  'Zeichenbereich, damit die Regel nicht an der Sortierfolge der Datenbank '
  'haengt.';


-- Dieselbe Zeichenregel plus die Unterstrich-Regeln, die schon vorher galten
-- (kein doppelter Unterstrich, keiner am Anfang, keiner am Ende). Diese
-- Funktion ist die Regel, die der Nutzer beim Tippen zu spueren bekommt;
-- der CHECK oben ist der Riegel dahinter.
create or replace function public.is_valid_username_format(p text)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $fn$
  select coalesce(
    p is not null
    and char_length(p) >= 3
    and char_length(p) <= 20
    and translate(
          p,
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_äöüÄÖÜß',
          ''
        ) = ''
    and p !~ '__'
    and p !~ '^_'
    and p !~ '_$',
    false);
$fn$;

comment on function public.is_valid_username_format(text) is
  '2026-08-25: Erlaubt zusaetzlich zu A-Z a-z 0-9 _ die deutschen '
  'Sonderzeichen ä ö ü Ä Ö Ü ß. Kyrillisch, Griechisch und Emoji bleiben '
  'draussen - sie liessen sich zum Nachbauen fremder Namen benutzen.';


-- ----------------------------------------------------------------------------
-- 3. Der Riegel
-- ----------------------------------------------------------------------------
-- Eine Pruefung in set_username allein reicht NICHT: zwischen "ist der Name
-- noch frei?" und "schreib ihn hin" passt eine zweite Sitzung, die genau
-- dasselbe tut. Beide sehen "frei", beide schreiben - und danach stehen zwei
-- verwechselbare Namen in der Tabelle. Nur ein UNIQUE-Index haelt das auf,
-- weil er ueber alle Sitzungen hinweg sperrt. Die Pruefungen in den
-- Funktionen bleiben trotzdem drin: sie liefern die freundliche Meldung,
-- der Index das letzte Wort.
create unique index if not exists ux_profiles_username_schluessel
  on public.profiles (public.benutzername_schluessel(username))
  where username is not null and btrim(username) <> '';

comment on index public.ux_profiles_username_schluessel is
  '2026-08-25: Verhindert zwei Namen, die sich nach der Faltung gleichen - '
  '"mueller", "müller" und "Müller" schliessen einander aus. Das ist der '
  'einzige Schutz, der auch dann haelt, wenn zwei Leute im selben Moment '
  'denselben Namen nehmen.';

-- ux_profiles_username_lower (gross/klein) bleibt bewusst bestehen: der
-- Schluessel-Index deckt ihn zwar mit ab, aber Abfragen der Form
-- `lower(username) = ...` finden ihre Spur nur dort.


-- ----------------------------------------------------------------------------
-- 4. "Ist der Name frei?" muss dieselbe Frage stellen wie der Riegel
-- ----------------------------------------------------------------------------
-- Sonst sagt die App "frei", und das Anlegen scheitert eine Sekunde spaeter.
create or replace function public.username_available(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid       uuid := auth.uid();
  v_clean     text := btrim(coalesce(p_username, ''));
  v_schluessel text;
begin
  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('available', false, 'reason', 'invalid_format');
  end if;

  v_schluessel := public.benutzername_schluessel(v_clean);

  -- Auch gesperrte Namen werden gefaltet verglichen: waere "gruen" gesperrt,
  -- duerfte sich niemand "grün" nennen und so dahinter stellen.
  if exists (
    select 1 from public.reserved_usernames
    where public.benutzername_schluessel(name) = v_schluessel
  ) then
    return jsonb_build_object('available', false, 'reason', 'reserved');
  end if;

  if exists (
    select 1 from public.profiles
    where public.benutzername_schluessel(username) = v_schluessel
      and (v_uid is null or id <> v_uid)
  ) then
    return jsonb_build_object('available', false, 'reason', 'taken');
  end if;

  return jsonb_build_object('available', true, 'reason', 'ok');
end;
$fn$;

comment on function public.username_available(text) is
  '2026-08-25: Prueft gegen dieselbe Faltung wie der UNIQUE-Index. Wer '
  '"mueller" heisst, blockiert damit "müller" und "Müller". Der eigene Name '
  'gilt fuer den Anmeldenden weiter als frei (Umbenennen auf die eigene '
  'Schreibweise).';


-- ----------------------------------------------------------------------------
-- 5. Das Setzen des Namens
-- ----------------------------------------------------------------------------
-- UNVERAENDERT bleibt die 30-Tage-Sperre. Sie ist hier besonders wichtig:
-- "mueller" -> "müller" ist fuer die Datenbank derselbe Schluessel, fuer
-- einen Menschen in der Liste aber ein anderer Name. Wer diese Umbenennung
-- an der Sperre vorbeiliesse ("faellt ja auf denselben Schluessel"), koennte
-- sein Erscheinungsbild beliebig oft wechseln. Genau das ist NICHT erlaubt:
-- jede Namensaenderung, auch eine reine Schreibweisen-Aenderung, kostet das
-- 30-Tage-Fenster.
create or replace function public.set_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid        uuid := auth.uid();
  v_clean      text := btrim(coalesce(p_username, ''));
  v_schluessel text;
  v_last       timestamptz;
  v_next       timestamptz;
  v_days       int;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'not_authenticated');
  end if;

  if not public.is_valid_username_format(v_clean) then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
  end if;

  v_schluessel := public.benutzername_schluessel(v_clean);

  if exists (
    select 1 from public.reserved_usernames
    where public.benutzername_schluessel(name) = v_schluessel
  ) then
    return jsonb_build_object('ok', false, 'error', 'reserved');
  end if;

  -- 30-Tage-Sperre (Server-Zeit; null => Erstvergabe ist frei)
  select username_changed_at into v_last from public.profiles where id = v_uid;
  if v_last is not null then
    v_next := v_last + interval '30 days';
    if now() < v_next then
      v_days := greatest(0, ceil(extract(epoch from (v_next - now())) / 86400.0))::int;
      return jsonb_build_object('ok', false, 'error', 'too_soon',
        'next_change_at', v_next, 'days_remaining', v_days);
    end if;
  end if;

  -- Eindeutigkeit ueber die Faltung, der eigene Name ausgenommen.
  if exists (
    select 1 from public.profiles
    where public.benutzername_schluessel(username) = v_schluessel
      and id <> v_uid
  ) then
    return jsonb_build_object('ok', false, 'error', 'taken');
  end if;

  -- Durchlass fuer den Guard-Trigger, und zwar NUR fuer diesen einen Schritt.
  --
  -- GEFUNDEN BEIM NACHWEIS (Probe H am 25.08.2026): das Flag wurde bisher
  -- gesetzt und nie wieder geloescht. `set_config(..., true)` gilt bis zum
  -- Ende der TRANSAKTION - wer also im selben Vorgang nach set_username noch
  -- ein direktes UPDATE auf profiles.username absetzte, kam am Guard vorbei
  -- und damit an der 30-Tage-Sperre. Ueber PostgREST ist jeder Aufruf eine
  -- eigene Transaktion, gefaehrlich war es also noch nicht - aber die Sperre
  -- soll nicht davon abhaengen, wie der Aufrufer seine Transaktion schneidet.
  perform set_config('app.username_change_ok', '1', true);
  update public.profiles
     set username = v_clean, username_changed_at = now()
   where id = v_uid;
  perform set_config('app.username_change_ok', '', true);

  return jsonb_build_object('ok', true, 'username', v_clean,
    'next_change_at', now() + interval '30 days', 'days_remaining', 30);
exception
  -- Der Riegel hat zugeschlagen: zwei Sitzungen wollten im selben Moment
  -- denselben (gefalteten) Namen. Fuer den Nutzer ist das schlicht "vergeben".
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'taken');
  when check_violation then
    return jsonb_build_object('ok', false, 'error', 'invalid_format');
end;
$fn$;

comment on function public.set_username(text) is
  '2026-08-25: Setzt den Benutzernamen. Erlaubt deutsche Umlaute, prueft '
  'Eindeutigkeit ueber public.benutzername_schluessel und faengt die '
  'gleichzeitige Vergabe ueber unique_violation ab. Die 30-Tage-Sperre gilt '
  'unveraendert - auch fuer eine reine Aenderung der Schreibweise.';


-- ----------------------------------------------------------------------------
-- 6. Die beiden Funktionen, die NICHT mitziehen muessen - und warum
-- ----------------------------------------------------------------------------
-- guard_username_change kennt keine Zeichenregel. Der Trigger nimmt jede
-- Aenderung an username/username_changed_at zurueck, die nicht durch
-- set_username kam (erkennbar am Durchlass-Flag app.username_change_ok).
-- Damit ist er GENAU der Grund, warum die 30-Tage-Sperre durch das
-- Zulassen von Umlauten nicht loecherig wird: ein direktes UPDATE auf
-- profiles.username - egal mit welchen Zeichen - laeuft ins Leere.
-- Geprueft am 25.08.2026, Probe H im Nachweis. Die Probe hat dabei EINE
-- Luecke aufgedeckt, die aber nicht im Trigger sass, sondern in
-- set_username: das Durchlass-Flag blieb bis zum Ende der Transaktion
-- stehen. Geschlossen in Abschnitt 5.
--
-- username_change_status rechnet nur mit username_changed_at und kennt
-- den Namen selbst nicht. Auch hier ist nichts zu aendern.
-- Beide bleiben deshalb unangetastet; ein Neuschreiben waere nur ein
-- zusaetzliches Risiko, dieselbe Logik beim Abtippen zu verlieren.


-- ----------------------------------------------------------------------------
-- 7. Der Weg ueber Google/Apple: Anmeldung darf am Riegel nicht scheitern
-- ----------------------------------------------------------------------------
-- handle_new_user baut aus dem Namen des Anbieters einen Benutzernamen.
-- Zwei Dinge waren daran zu tun:
--
--   a) Aus "Müller" wurde bisher "M_ller". Das war die Regel von damals,
--      jetzt darf der Umlaut bleiben.
--
--   b) WICHTIGER: die Funktion hat NIE geprueft, ob der Name schon vergeben
--      ist. Heisst schon jemand "max", bekommt der naechste "max"-Anmelder
--      eine unique_violation - und weil die ganz unten abgefangen und nur
--      als Warnung geloggt wird, entsteht schlicht KEIN Profil. Der Riegel
--      von oben vergroessert diese Lueche (jetzt kollidiert auch "Müller"
--      mit "mueller"), also wird sie hier zugemacht: bei Zusammenstoss haengt
--      die Funktion eine kurze Kennung an und versucht es erneut.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_roh      text;
  v_basis    text;
  v_kandidat text;
  v_versuch  int;
  v_erlaubt  constant text :=
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_äöüÄÖÜß';
begin
  v_roh := coalesce(
    nullif(trim(new.raw_user_meta_data->>'username'), ''),
    nullif(trim(new.raw_user_meta_data->>'preferred_username'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'cruiser'
  );

  -- Alles Unerlaubte wird zum Unterstrich. Der Zeichenbereich in diesem
  -- Muster haengt an der Sortierfolge (siehe Abschnitt 2) - deshalb wird das
  -- Ergebnis unten NOCH EINMAL mit translate geprueft und bei Zweifel
  -- verworfen. So kann hier nie ein Name entstehen, den der CHECK ablehnt.
  v_basis := regexp_replace(v_roh, '[^A-Za-z0-9_äöüÄÖÜß]', '_', 'g');
  v_basis := regexp_replace(v_basis, '_+', '_', 'g');
  v_basis := trim(both '_' from v_basis);
  v_basis := left(v_basis, 20);
  v_basis := trim(both '_' from v_basis);

  if v_basis is null
     or char_length(v_basis) < 3
     or translate(v_basis, v_erlaubt, '') <> ''
  then
    v_basis := 'cruiser_' || left(replace(new.id::text, '-', ''), 8);
  end if;

  v_kandidat := v_basis;

  -- Bis zu zehn Anlaeufe. Der erste ist der Wunschname; danach wird
  -- gekuerzt und eine Kennung angehaengt.
  for v_versuch in 0..9 loop
    begin
      insert into public.profiles (id, email, username)
      values (new.id, new.email, v_kandidat)
      on conflict (id) do nothing;
      return new;
    exception when unique_violation or check_violation then
      -- Platz fuer "_" plus vier Zeichen Kennung schaffen (20 Zeichen Grenze).
      v_kandidat := trim(both '_' from left(v_basis, 15))
                    || '_' || substr(md5(random()::text || clock_timestamp()::text), 1, 4);
    end;
  end loop;

  -- Zehn Anlaeufe ohne Erfolg: lieber ein technischer Name als kein Profil.
  insert into public.profiles (id, email, username)
  values (new.id, new.email, 'cruiser_' || left(replace(new.id::text, '-', ''), 8))
  on conflict (id) do nothing;
  return new;

exception
  -- Letzte Sicherung: eine Anmeldung darf NIE daran scheitern.
  when others then
    raise warning 'handle_new_user failed for auth user %: %', new.id, sqlerrm;
    return new;
end;
$fn$;

comment on function public.handle_new_user() is
  '2026-08-25: Legt das Profil zu einem neuen auth-Konto an. Behaelt '
  'deutsche Umlaute im Namen und weicht bei einem Zusammenstoss mit einem '
  'vergebenen (gefalteten) Namen auf eine angehaengte Kennung aus, statt '
  'das Profil ausfallen zu lassen.';
