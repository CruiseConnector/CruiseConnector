-- 2026-08-24 - Aufgabe 4.1 (Abzeichen und Boost fuer alle) und
--              Aufgabe 4.3 (Manipulationsschutz der Fahrtdaten).
--
-- Vucko woertlich zu 4.1: "ab dem naechsten Update moechte ich ja, dass halt
-- jeder ein Badge bekommt [...] und ich moechte, dass jeder diesen bekommt ab
-- dem naechsten Update, wirklich jede Person, mit mir eingeschlossen."
--
-- GEMESSEN am 24.08. in der Produktivdatenbank:
--   profiles gesamt                      183
--   davon mit badge_15 Gruendungszeit    151   (30 haben GAR KEIN Abzeichen)
--   davon mit badge_16 Startklar           0
--   davon mit starter_bonus_ende           0   (NIEMAND hat je den Boost)
--   Fahrten mit group_id                   0   (in der ganzen Historie)
--   Nutzer mit je einer abgeschlossenen Fahrt  15 von 183
--
-- Der Boost verlangt heute ALLE ACHT Starter-Aufgaben, und die achte ist
-- "Eine Gruppenfahrt abschliessen". Weil es null Fahrten mit group_id gibt,
-- ist der Boost seit seiner Einfuehrung fuer JEDEN unerreichbar. Diese
-- Migration holt das per Amnestie nach; die Bedingung selbst ist ein
-- Produktproblem und wird im Client gelockert (siehe Bericht).


-- =====================================================================
-- TEIL 1 (4.1) - Einmalige Amnestie: badge_15, badge_16 und eine
--                Doppel-XP-Woche fuer alle 183 Bestandsprofile.
-- =====================================================================
--
-- IDEMPOTENZ: Beide UPDATEs haben eine WHERE-Klausel, die beim zweiten Lauf
-- null Zeilen trifft. Insbesondere wird `starter_bonus_ende` NUR gesetzt,
-- wenn es NULL ist. Ein zweiter Lauf verkuerzt oder verlaengert damit keine
-- laufende Bonuswoche, und er vergibt auch keine zweite Woche an jemanden,
-- dessen Woche bereits abgelaufen ist.
--
-- WAECHTER trg_guard_starter_bonus_ende: Er dreht ein UPDATE nur dann
-- zurueck, wenn `auth.uid() is not null` UND `old.starter_bonus_ende` bereits
-- gesetzt war. Beim Migrationslauf ist auth.uid() NULL (kein JWT), und der
-- alte Wert ist per WHERE-Klausel ohnehin NULL. Der Waechter behindert diese
-- Migration also nicht und muss NICHT abgeschaltet werden - genau so war er
-- gedacht ("Admins/Serverjobs bleiben aussen vor, damit ein Support-Fall noch
-- korrigierbar ist"). Er bleibt in voller Staerke stehen.

update public.profiles
set badges = coalesce(badges, '[]'::jsonb) || '["badge_15","badge_16"]'::jsonb
where not (coalesce(badges, '[]'::jsonb) @> '["badge_15","badge_16"]'::jsonb);

update public.profiles
set starter_bonus_ende = now() + interval '7 days'
where starter_bonus_ende is null;

-- BEWUSST NICHT ANGEFASST: `starter_aufgaben`. Die Checkliste bleibt ehrlich
-- offen. Sichtbar wird das nicht: `starter_paket_karte.dart` zeigt, solange
-- `doppelXpAktiv` gilt, ausschliesslich den Countdown und danach gar nichts
-- mehr. Und eine zweite Bonuswoche kann daraus nicht entstehen, weil der
-- Client beim Abgleich `paketVergeben` aus dem vorhandenen Server-Ende setzt
-- (starter_aufgaben_service.dart, synchronisiereMitProfil).


-- =====================================================================
-- TEIL 2 (4.1) - Damit die NAECHSTEN Konten nicht wieder durchfallen:
--                badge_15 direkt beim Anlegen des Profils.
-- =====================================================================
--
-- Die 30 Profile ohne jedes Abzeichen sind alle nach dem 19.08. entstanden.
-- Sie haetten badge_15 beim ersten Sync bekommen sollen - haben aber nie
-- einen ausgeloest (nie die Startseite lange genug offen, nie eine Fahrt).
-- Ein Trigger beim INSERT haengt das Abzeichen an, bevor der Client
-- ueberhaupt etwas tun muss.
--
-- BEWUSSTE ENTSCHEIDUNG: Der BOOST kommt hier NICHT automatisch mit.
--   * Der Boost ist eine Uhr, die sofort laeuft. Gemessen: nur 15 von 183
--     Profilen haben je eine Fahrt abgeschlossen. Bei einer Vergabe zur
--     Registrierung waere die Doppel-XP-Woche bei der grossen Mehrheit
--     abgelaufen, BEVOR sie das erste Mal fahren - der Bonus verpufft, statt
--     zu ziehen.
--   * Der Boost ist der einzige Hebel, der Leute durch das Onboarding zieht.
--     Verschenkt man ihn bei der Anmeldung, ist die Aufgabenliste wertlos.
--   * Das Abzeichen dagegen kostet nichts und ist genau das, was Vucko fuer
--     jede Person will.
-- Der Boost bleibt also am Onboarding - aber die Bedingung muss erreichbar
-- werden (siehe Bericht, Abschnitt fuer den Client-Agenten).

create or replace function public.setze_gruendungsabzeichen()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $$
begin
  -- 2026-08-24: badge_15 "Gruendungszeit" bekommt JEDE Person, ohne
  -- Bedingung. Der nachgelagerte Trigger trg_preserve_profile_badges
  -- normalisiert und sortiert das Ergebnis (er heisst absichtlich
  -- alphabetisch spaeter und laeuft deshalb danach).
  new.badges := coalesce(new.badges, '[]'::jsonb) || '["badge_15"]'::jsonb;
  return new;
end;
$$;

comment on function public.setze_gruendungsabzeichen() is
  '2026-08-24: Haengt badge_15 an jedes neu angelegte Profil. Grund: 30 von '
  '183 Profilen (alle nach dem 19.08. angelegt) hatten gar kein Abzeichen, '
  'weil die Vergabe allein am Client-Sync hing.';

drop trigger if exists trg_gruendungsabzeichen on public.profiles;
create trigger trg_gruendungsabzeichen
  before insert on public.profiles
  for each row
  execute function public.setze_gruendungsabzeichen();


-- =====================================================================
-- TEIL 3 (4.3) - Rechte entziehen: TRUNCATE, DELETE und der komplette
--                Schreibzugriff von anon.
-- =====================================================================
--
-- GEMESSEN am 24.08.:
--   authenticated: SELECT, INSERT, DELETE, TRUNCATE, REFERENCES, TRIGGER
--   anon:          dasselbe PLUS volles UPDATE auf allen 16 Spalten
--
-- TRUNCATE umgeht Row Level Security VOLLSTAENDIG. Ein einziger eingeloggter
-- Nutzer haette damit saemtliche Fahrten aller Nutzer loeschen koennen - also
-- die gesamte Grundlage von XP, Ranglisten, Badges und Monitoring.
--
-- VORHER GEPRUEFT, ob die App wirklich loescht:
--   grep -rn "from('user_drive_sessions')" lib/ -A4 | grep -i delete
--   -> KEIN einziger Treffer. Kein Client-Pfad loescht eine Fahrt.
-- Der einzige Loeschpfad ist `public.delete_current_user()` (Kontoloeschung),
-- und die Funktion ist SECURITY DEFINER: sie laeuft mit den Rechten ihres
-- Eigentuemers, nicht mit denen von authenticated. Der Entzug bricht die
-- Kontoloeschung also nicht.
--
-- Vorbild im Haus: 20260726172132_road_incidents_revoke_truncate_delete.sql.
revoke truncate, delete, references, trigger
  on public.user_drive_sessions from anon, authenticated;

-- anon hatte INSERT und UPDATE auf allen Spalten. Faktisch blockte RLS das
-- (die Policies verlangen auth.uid() = user_id, und das ist fuer anon NULL),
-- aber die Absicherung haengt dann allein an RLS statt zusaetzlich am Recht.
-- Defense in Depth: weg damit.
revoke insert, update on public.user_drive_sessions from anon;

-- authenticated behaelt SELECT, INSERT und das absichtlich auf photo_url
-- beschraenkte UPDATE (20260625120000). Diese drei bleiben unangetastet -
-- ohne sie kann die App keine Fahrt mehr verbuchen.


-- =====================================================================
-- TEIL 4 (4.3) - Plausibilitaet: XP, Strecke, Dauer, Hoechstgeschwindigkeit
--                und die Uhr des Geraets.
-- =====================================================================
--
-- Der Client rechnet xp_awarded selbst aus und schickt die fertige Zahl
-- (gamification_service.dart, buildDriveSessionInsert). Wer die App
-- auseinandernimmt, traegt beliebige Werte ein. Der Server nimmt die Zahl
-- weiterhin entgegen, weist aber Unsinn ab.
--
-- WOHER DIE GRENZEN KOMMEN (alles am 24.08. gemessen, 147 echte Fahrten):
--
--   Strecke     Rekord 195,2 km, Median 12,5 km, p95 50,9 km.
--               Grenze 2.000 km = das Zehnfache des Rekords. Eine einzelne
--               Fahrt ueber 2.000 km gibt es nicht (Wien nach Lissabon sind
--               rund 2.900 km).
--
--   Dauer       Rekord 32.487 s = 9,0 h (und darin steckten laut Notiz vom
--               28.07. noch Pausen). Grenze 86.400 s = 24 h. Eine Fahrt, die
--               laenger als einen Tag dauert, ist keine Fahrt mehr, sondern
--               eine haengengebliebene Aufzeichnung.
--
--   Tempo       Rekord top_speed 176,1 km/h. Grenze 300 km/h. Das ist weit
--               ueber allem, was auf oeffentlicher Strasse vorkommt, und
--               laesst GPS-Ausreissern trotzdem Luft. Die Gruppen-Rangliste
--               zeigt diese Zahl, deshalb darf sie nicht frei waehlbar sein.
--
--   Leerlauf    Ab 100 km verlangen wir eine Mindestdauer, die zu 400 km/h
--               Schnitt passt (195 km braucht damit 1.757 s; die echte
--               Rekordfahrt brauchte 7.739 s). Damit faellt "3.000 km in 5
--               Sekunden" durch, ohne echte Fahrten zu treffen. Die Schwelle
--               liegt bei 100 km, weil es aus dem Mai 2026 eine echte Zeile
--               mit 50,5 km in 20 s gibt: ein Client-Fehler vom ersten Tag.
--               Solche kurzen Ausreisser sollen nicht die Fahrt kosten.
--
--   XP          Rekord 3.123 XP, Schnitt 254, p99 1.511.
--               Eine feste Obergrenze waere falsch: die Formel lautet
--                 xp = runde(km * 10 * (Basis + Serie * 0,1))
--               mit Basis 2,0 waehrend der Doppel-XP-Woche, sonst 1,0, und
--               die Serie hat KEINEN Deckel. Der zulaessige Wert waechst also
--               mit der Zeit - eine Zahl, die heute grosszuegig ist, bricht in
--               einem Jahr echte Fahrten.
--               Deshalb wird die Grenze aus einer Groesse abgeleitet, die der
--               Server selbst kennt: dem KONTOALTER. Laenger als das Konto
--               kann keine Serie sein.
--                 Obergrenze = 250 + aufrunden(km * 10 * (2,0 + 0,1 * (Alter in Tagen + 2)))
--               Die 250 decken die Tutorial-Zeile ab (0 km, 125 XP, echte
--               Zeile, gemessen zweimal vorhanden) und geben Rundungen Luft.
--               Die +2 Tage fangen ein Geraet ab, dessen Uhr vorgeht.
--               Nachgerechnet an der echten Rekordfahrt: 195,2 km auf einem
--               106 Tage alten Konto ergibt eine Grenze von rund 25.300 XP -
--               das Achtfache dessen, was tatsaechlich gutgeschrieben wurde.
--               Nachgerechnet am hoechsten echten Verhaeltnis (17,7 km,
--               602 XP, also 34 XP/km): passt mit grossem Abstand.
--               Nachgerechnet am engsten Fall, einem taggleich angelegten
--               Konto: 2,0 + 0,2 = 2,2 als Faktor gegenueber 2,1, den die
--               Formel dort hoechstens erzeugen kann. Passt.
--
--   Die Uhr     created_at kommt beim Nachbuchen einer unterbrochenen Fahrt
--               vom Geraet (unterbrochene_fahrt_verbuchung.dart uebergibt
--               savedAt). Der Schnappschuss lebt hoechstens 48 h
--               (ActiveRideSnapshotService.maxAge). Alles ausserhalb von
--               [jetzt minus 7 Tage, jetzt] ist deshalb keine verspaetete
--               Nachbuchung, sondern eine verstellte Uhr - und wird auf die
--               Serverzeit gesetzt. Sieben Tage statt zwei, damit ein Geraet
--               ohne Netz die Fahrt noch nachreichen kann.
--               Hier wird GESETZT statt abgewiesen: Die Fahrt ist echt, nur
--               ihr Zeitstempel nicht. Eine Fahrt wegen einer falschen Uhr zu
--               verwerfen waere Datenverlust beim Falschen.

create or replace function public.pruefe_fahrt_plausibilitaet()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_kontoalter_tage numeric;
  v_xp_obergrenze   numeric;
  v_mindestdauer    numeric;
begin
  -- Serverjobs, Migrationen und Support-Korrekturen (auth.uid() is null)
  -- bleiben aussen vor - gleiche Linie wie guard_starter_bonus_ende.
  if auth.uid() is null then
    return new;
  end if;

  -- --- Die Uhr: Serverzeit ist die Wahrheit, der Client-Wert wird geprueft.
  if new.created_at is null
     or new.created_at > now()
     or new.created_at < now() - interval '7 days' then
    new.created_at := now();
  end if;

  -- --- Strecke
  if new.distance_km > 2000 then
    raise exception
      'Strecke unplausibel: % km. Hoechstens 2000 km je Fahrt.', new.distance_km
      using errcode = '23514';
  end if;

  -- --- Dauer
  if new.duration_seconds > 86400 then
    raise exception
      'Fahrtdauer unplausibel: % s. Hoechstens 24 Stunden je Fahrt.',
      new.duration_seconds
      using errcode = '23514';
  end if;

  -- --- Hoechstgeschwindigkeit
  if new.top_speed_kmh is not null
     and (new.top_speed_kmh < 0 or new.top_speed_kmh > 300) then
    raise exception
      'Hoechstgeschwindigkeit unplausibel: % km/h.', new.top_speed_kmh
      using errcode = '23514';
  end if;

  -- --- Lange Strecke ohne Zeit
  if new.distance_km > 100 then
    v_mindestdauer := new.distance_km / 400.0 * 3600.0;
    if new.duration_seconds < v_mindestdauer then
      raise exception
        'Strecke und Dauer passen nicht zusammen: % km in % s.',
        new.distance_km, new.duration_seconds
        using errcode = '23514';
    end if;
  end if;

  -- --- XP gegen das Kontoalter
  select greatest(0, extract(epoch from (now() - p.created_at)) / 86400.0)
    into v_kontoalter_tage
  from public.profiles p
  where p.id = new.user_id;

  -- Kein Profil gefunden (sollte die Fremdschluesselkette verhindern):
  -- grosszuegig weiterrechnen statt eine echte Fahrt zu verlieren.
  if v_kontoalter_tage is null then
    v_kontoalter_tage := 500;
  end if;

  v_xp_obergrenze :=
    250 + ceil(new.distance_km * 10.0 * (2.0 + 0.1 * (v_kontoalter_tage + 2)));

  if new.xp_awarded > v_xp_obergrenze then
    raise exception
      'XP unplausibel: % XP fuer % km. Hoechstens % XP.',
      new.xp_awarded, new.distance_km, v_xp_obergrenze
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.pruefe_fahrt_plausibilitaet() is
  '2026-08-24 (Aufgabe 4.3): Serverseitige Plausibilitaet fuer Fahrten. '
  'Der Client darf xp_awarded, distance_km, duration_seconds und den '
  'Zeitstempel weiter schicken, aber Unsinn kommt nicht mehr durch. Die '
  'XP-Obergrenze waechst mit dem Kontoalter, weil der Streak-Multiplikator '
  'keinen Deckel hat.';

-- EXECUTE entziehen: Trigger-Funktionen brauchen es nicht (Postgres prueft
-- beim Ausloesen kein EXECUTE), und ohne den Entzug meldet der Advisor eine
-- SECURITY-DEFINER-Funktion, die ueber PostgREST erreichbar aussieht. Das ist
-- in diesem Projekt eine wiederkehrende Falle.
revoke execute on function public.pruefe_fahrt_plausibilitaet() from public, anon, authenticated;

-- Der Name beginnt mit "aa_", damit die Pruefung VOR den beiden
-- AFTER-INSERT-Triggern greift und - wichtiger - vor jedem kuenftigen
-- BEFORE-Trigger, der sich auf geprueften Werten verlassen will.
drop trigger if exists aa_trg_fahrt_plausibilitaet on public.user_drive_sessions;
create trigger aa_trg_fahrt_plausibilitaet
  before insert on public.user_drive_sessions
  for each row
  execute function public.pruefe_fahrt_plausibilitaet();

-- Zweite Verteidigungslinie als echte Constraints, so weit der Bestand sie
-- traegt. Geprueft: keine der 147 Zeilen verletzt eine davon.
alter table public.user_drive_sessions
  drop constraint if exists user_drive_sessions_distanz_plausibel;
alter table public.user_drive_sessions
  add constraint user_drive_sessions_distanz_plausibel
  check (distance_km <= 2000);

alter table public.user_drive_sessions
  drop constraint if exists user_drive_sessions_dauer_plausibel;
alter table public.user_drive_sessions
  add constraint user_drive_sessions_dauer_plausibel
  check (duration_seconds <= 86400);

alter table public.user_drive_sessions
  drop constraint if exists user_drive_sessions_topspeed_plausibel;
alter table public.user_drive_sessions
  add constraint user_drive_sessions_topspeed_plausibel
  check (top_speed_kmh is null or (top_speed_kmh >= 0 and top_speed_kmh <= 300));


-- =====================================================================
-- TEIL 5 (4.3) - Das zweite Loch: profiles.total_xp direkt beschreiben.
-- =====================================================================
--
-- Selbst mit dichter Fahrtentabelle bliebe der kuerzere Weg offen: die Policy
-- "User aktualisiert eigenes Profil" erlaubt ein UPDATE auf JEDE Spalte des
-- eigenen Profils - auch auf total_xp, level, total_km und total_routes. Wer
-- xp_awarded nicht faelschen kann, schreibt eben direkt 900.000 XP ins Profil
-- und steht auf Level 100.
--
-- GEPRUEFT, ob die App diese Spalten braucht: ja, sie schreibt sie
-- (gamification_service.dart, calculateAndSync). ABER sie schreibt dort
-- ausschliesslich, was `summarizeDriveSessions(sessions)` aus genau denselben
-- Fahrten aufsummiert hat. Der Server rechnet dasselbe bereits selbst
-- (private.recalculate_profile_drive_totals, seit 20260507095347).
--
-- Deshalb wird NICHT das Recht entzogen (das braeche den Client), sondern der
-- Wert ueberschrieben: Schickt ein angemeldeter Nutzer diese vier Spalten,
-- setzt der Server sie auf das Ergebnis aus user_drive_sessions. Ein
-- ehrlicher Client merkt davon nichts, weil er ohnehin dieselbe Zahl schickt.
-- Ein Faelscher schreibt ins Leere.
create or replace function public.guard_profile_fahrt_summen()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  s record;
begin
  if auth.uid() is null then
    return new;
  end if;

  -- Nur rechnen, wenn wirklich eine der vier Spalten angefasst wird.
  if new.total_xp     is not distinct from old.total_xp
     and new.total_km  is not distinct from old.total_km
     and new.total_routes is not distinct from old.total_routes
     and new.level     is not distinct from old.level then
    return new;
  end if;

  select
    coalesce(sum(distance_km), 0)::double precision as km,
    coalesce(sum(xp_awarded), 0)::int               as xp,
    count(*)::int                                   as routen
  into s
  from public.user_drive_sessions
  where user_id = old.id;   -- die Zeile, die gerade geaendert wird

  new.total_km     := s.km;
  new.total_xp     := s.xp;
  new.total_routes := s.routen;
  new.level        := private.level_for_xp(s.xp);
  return new;
end;
$$;

comment on function public.guard_profile_fahrt_summen() is
  '2026-08-24 (Aufgabe 4.3): total_xp, total_km, total_routes und level '
  'stammen ausschliesslich aus user_drive_sessions. Ein Client-UPDATE auf '
  'diese Spalten wird durch die Serverrechnung ersetzt, statt das Recht zu '
  'entziehen - der ehrliche Client schickt ohnehin dieselben Zahlen.';

revoke execute on function public.guard_profile_fahrt_summen() from public, anon, authenticated;

drop trigger if exists trg_guard_profile_fahrt_summen on public.profiles;
create trigger trg_guard_profile_fahrt_summen
  before update on public.profiles
  for each row
  execute function public.guard_profile_fahrt_summen();


-- =====================================================================
-- TEIL 6 (4.3) - Die Serie serverseitig rechnen.
-- =====================================================================
--
-- Heute rechnet der Client die Serie aus `DateTime.now()`
-- (gamification_service.dart:381 und :394). Zwei Folgen:
--   * Wer die Geraeteuhr vorstellt, erzeugt sich beliebig lange Serien und
--     damit einen beliebig hohen XP-Multiplikator.
--   * Zwei Geraete desselben Kontos in verschiedenen Zeitzonen zeigen
--     verschiedene Zahlen.
--
-- Diese Funktion rechnet dieselbe Regel auf der Serverzeit. Sie ist
-- ZEICHENGLEICH zur Dart-Fassung uebersetzt, inklusive Schonfrist:
--   * Fahrtage sind Tage mit mindestens einer Fahrt ueber 0 km.
--   * Fehltage zaehlen nicht mit, sie unterbrechen nur.
--   * EIN Fehltag reisst die Serie nicht. Ein ZWEITER Fehltag innerhalb von
--     sieben Tagen nach dem ersten beendet sie
--     (GamificationService.schonfristTage = 7).
--   * Ohne Argument gilt der ANZEIGE-Modus: ist heute noch nicht gefahren,
--     zaehlt es nicht als Fehltag, sondern die Zaehlung beginnt bei gestern.
--   * Mit p_fahrt_datum gilt der GUTSCHRIFT-Modus: der Fahrttag zaehlt mit,
--     das Ergebnis ist also mindestens 1.
--
-- ZEITZONE: fest Europe/Vienna. Der Client rechnet in der Geraetezeitzone -
-- genau das soll aufhoeren, sonst sehen zwei Geraete verschiedene Zahlen.
-- Eine feste Bezugszone ist der ganze Zweck der Verlagerung. Die Abdeckung
-- der App ist DACH, dort ist es dieselbe Zone.
create or replace function public.get_fahrt_serie(p_fahrt_datum date default null)
returns integer
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid    uuid := auth.uid();
  v_heute  date := (now() at time zone 'Europe/Vienna')::date;
  v_tage   date[];
  v_start  date;
  v_tag    date;
  v_aeltester date;
  v_serie  int := 0;
  v_offener_fehltag date;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select coalesce(
           array_agg(distinct ((created_at at time zone 'Europe/Vienna')::date)),
           '{}'::date[]
         )
    into v_tage
  from public.user_drive_sessions
  where user_id = v_uid
    and distance_km > 0;

  if p_fahrt_datum is null then
    -- Anzeige-Modus
    if cardinality(v_tage) = 0 then
      return 0;
    end if;
    v_start := case when v_heute = any (v_tage) then v_heute else v_heute - 1 end;
  else
    -- Gutschrift-Modus. Das Datum kommt vom Geraet, also in dasselbe Fenster
    -- klemmen wie created_at in pruefe_fahrt_plausibilitaet.
    v_start := least(greatest(p_fahrt_datum, v_heute - 7), v_heute);
    v_tage  := v_tage || v_start;
  end if;

  select min(t) into v_aeltester from unnest(v_tage) as t;

  v_tag := v_start;
  for i in 1..4000 loop
    if v_tag = any (v_tage) then
      v_serie := v_serie + 1;
    elsif v_offener_fehltag is not null
          and (v_offener_fehltag - v_tag) <= 7 then
      exit;
    else
      v_offener_fehltag := v_tag;
    end if;
    v_tag := v_tag - 1;
    -- Vor dem ersten Fahrtag gibt es nichts mehr zu holen; die Schonfrist
    -- braucht danach hoechstens noch acht Tage Nachlauf.
    exit when v_tag < v_aeltester - 8;
  end loop;

  return v_serie;
end;
$$;

comment on function public.get_fahrt_serie(date) is
  '2026-08-24 (Aufgabe 4.3, Punkt 7): Fahrt-Serie auf der SERVERZEIT statt '
  'auf DateTime.now() des Geraets. Ohne Argument der Anzeigewert, mit '
  'p_fahrt_datum der Gutschriftwert fuer genau diese Fahrt. Bezugszone '
  'Europe/Vienna, damit alle Geraete dieselbe Zahl sehen.';

revoke execute on function public.get_fahrt_serie(date) from public, anon;
grant  execute on function public.get_fahrt_serie(date) to authenticated;
