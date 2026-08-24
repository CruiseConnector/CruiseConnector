-- 2026-08-24: Die Kachel-Anordnung der Startseite lag NUR auf dem Geraet.
--
-- Vucko hat heute nachgefragt, was „deine Kachel-Anordnung wandert nicht aufs
-- neue Handy" bedeutet. Genau das: `home_dashboard_layout_v1` lebte
-- ausschliesslich in den SharedPreferences. Neues Handy oder Neuinstallation
-- hiess: alles wieder Standard, die eigene Anordnung ersatzlos weg.
--
-- Am 19.08. ist derselbe Fehler beim Starter-Paket aufgetreten und mit
-- schlanken Spalten auf `profiles` behoben worden (20260819120000, woertlich:
-- „keine eigene Tabelle, kein Umbau, ein UPDATE pro Abgleich"). Das passt
-- hier genauso:
--   * Es gibt GENAU EINE Anordnung pro Konto — keine Historie, keine
--     Fremdschluessel, nichts zu verknuepfen. Eine eigene Tabelle haette eine
--     Zeile pro Nutzer und braeuchte eigene RLS-Policies.
--   * Die Startseite liest ohnehin schon aus `profiles`; der Abgleich kostet
--     kein zusaetzliches Netz-Gespraech mehr als noetig.
--   * Ein Schreibvorgang pro Verschieben, ein UPDATE, fertig.
--
-- BEWUSST IN KAUF GENOMMEN: `profiles` ist fuer andere angemeldete Nutzer
-- lesbar (Policy „Profile sind fuer nicht blockierte Nutzer lesbar"). Damit
-- koennte ein anderer Nutzer sehen, welche Kacheln jemand auf seiner
-- Startseite hat. Das ist keine sensible Angabe (kein Ort, kein Kontakt, kein
-- Kennwort) und liegt auf derselben Stufe wie `badge_showcase` und
-- `notification_preferences`, die dort seit jeher offen stehen. KEINE Stelle
-- der App liest `profiles` mit `select('*')` — geprueft am 24.08. —, die
-- Spalten fallen also niemandem ungefragt in die Antwort.
alter table public.profiles
  add column if not exists home_layout jsonb,
  add column if not exists home_layout_stand timestamptz;

comment on column public.profiles.home_layout is
  'Kachel-Anordnung der Startseite als JSON-Liste (dieselben Objekte wie in '
  'den SharedPreferences unter home_dashboard_layout_v1). NULL = das Konto '
  'hat noch nie eine eigene Anordnung hochgeladen; dann gewinnt der '
  'Geraetestand und wird beim naechsten Start hochgeladen.';

comment on column public.profiles.home_layout_stand is
  'Wann die Anordnung in home_layout gemacht wurde (nicht: hochgeladen). '
  'Entscheidet zwischen zwei Geraeten: der juengere Stand gewinnt, siehe '
  'Trigger trg_guard_home_layout_stand.';

-- ZWEI GERAETE GLEICHZEITIG.
--
-- Ohne Sperre gilt „wer zuletzt schreibt", und das ist nicht dasselbe wie
-- „wer zuletzt verschoben hat": Ein Handy, das beim Speichern kein Netz
-- hatte, laedt seinen Stand erst beim naechsten Start hoch — womoeglich
-- Stunden nachdem am anderen Handy bereits neu sortiert wurde. Es wuerde
-- dann eine aeltere Anordnung ueber eine juengere legen.
--
-- Deshalb ist der Stand hier monoton: Ein UPDATE mit aelterem (oder ganz
-- fehlendem) Stand laesst die gespeicherte Anordnung stehen, statt zu
-- gewinnen. Der Client merkt das beim naechsten Abgleich und uebernimmt dann
-- seinerseits den juengeren Serverstand.
--
-- Admins und Serverjobs (auth.uid() is null, service_role) bleiben aussen
-- vor, damit ein Support-Fall korrigierbar bleibt — dieselbe Ausnahme wie bei
-- guard_starter_bonus_ende.
--
-- SECURITY INVOKER mit Absicht: Die Funktion braucht keine fremden Rechte,
-- sie liest nur OLD/NEW und auth.uid(). Als SECURITY DEFINER haette der
-- Advisor sie zu Recht als per RPC aufrufbar gemeldet — genau dieser Befund
-- kam am 19.08. beim ersten Anlauf.
create or replace function public.guard_home_layout_stand()
returns trigger
language plpgsql
security invoker
set search_path to 'public', 'pg_temp'
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  -- Jedes andere Profil-UPDATE (Name, Avatar, Auto, ...) laeuft hier auch
  -- durch. Ruehrt es die beiden Spalten nicht an, ist nichts zu tun.
  if new.home_layout is not distinct from old.home_layout
     and new.home_layout_stand is not distinct from old.home_layout_stand then
    return new;
  end if;

  if old.home_layout_stand is not null
     and (new.home_layout_stand is null
          or new.home_layout_stand < old.home_layout_stand) then
    new.home_layout := old.home_layout;
    new.home_layout_stand := old.home_layout_stand;
  end if;

  return new;
end;
$$;

-- Wiederkehrende Falle: Die Funktion darf nicht als RPC offenstehen. Ein
-- Trigger braucht das EXECUTE-Recht des Aufrufers nicht — Postgres prueft es
-- nur beim Anlegen des Triggers.
revoke execute on function public.guard_home_layout_stand() from public;
revoke execute on function public.guard_home_layout_stand() from anon;

drop trigger if exists trg_guard_home_layout_stand on public.profiles;
create trigger trg_guard_home_layout_stand
  before update on public.profiles
  for each row
  execute function public.guard_home_layout_stand();
