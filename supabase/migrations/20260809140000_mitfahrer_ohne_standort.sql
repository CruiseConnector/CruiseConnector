-- ═══════════════════════════════════════════════════════════════════════════
-- Mitfahrer sind keine Fahrzeuge — sie senden keinen Standort
--
-- Auftrag Vucko 2026-08-09 (Gruppenfahrt vom 08.08.): „ich habe meine
-- Mitfahrerin in der Gruppe aufgenommen und gesagt sie soll sich als
-- Mitfahrerin registrieren ... das Problem war ich habe dann ihr Profilbild
-- gesehen waehrend der Fahrt ... ich moechte, dass wenn man als Fahrer oder als
-- Mitfahrer gilt, man das wirklich klar differenzieren kann."
--
-- WAS BISHER GALT: Die Spalte ride_role gab es zwar (driver/passenger, in der
-- Lobby auch waehlbar), sie hatte aber KEINE Konsequenz. Jedes Mitglied hat
-- seinen Standort hochgeladen und erschien als eigenes Fahrzeug auf der Karte —
-- auch die Beifahrerin, die im selben Auto sass. Auf der Karte standen dadurch
-- zwei Fahrzeuge an derselben Stelle.
--
-- WARUM DAS IN DIE DATENBANK GEHOERT UND NICHT NUR IN DIE APP:
-- Eine reine Client-Pruefung wuerde von jeder aelteren App-Version umgangen —
-- und alte Versionen bleiben nach einem Store-Release noch wochenlang im
-- Umlauf. Der Trigger raeumt den Standort unabhaengig davon weg, welche App
-- schreibt. Die App bekommt zusaetzlich einen eigenen Riegel (kein unnoetiger
-- Netzverkehr), aber die Datenbank ist die verbindliche Instanz.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.mitfahrer_ohne_standort()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- Nur Fahrer sind Fahrzeuge mit Position. Bei allen anderen wird der
  -- Standort verworfen, egal was geschrieben wurde.
  if coalesce(new.ride_role, 'driver') <> 'driver' then
    new.current_lat := null;
    new.current_lng := null;
    new.last_updated_at := null;
  end if;
  return new;
end;
$function$;

comment on function public.mitfahrer_ohne_standort() is
  'Erzwingt: nur ride_role=driver traegt einen Standort. Mitfahrer erscheinen '
  'nie als eigenes Fahrzeug auf der Karte — auch nicht aus alten App-Versionen.';

drop trigger if exists trg_mitfahrer_ohne_standort on public.group_members;
create trigger trg_mitfahrer_ohne_standort
  before insert or update on public.group_members
  for each row
  execute function public.mitfahrer_ohne_standort();

-- Altbestand aufraeumen: Wer heute als Mitfahrer eingetragen ist, aber noch
-- eine Position aus der Zeit davor mit sich traegt, wird jetzt bereinigt.
update public.group_members
   set current_lat = null,
       current_lng = null,
       last_updated_at = null
 where coalesce(ride_role, 'driver') <> 'driver'
   and (current_lat is not null or current_lng is not null);
