-- 2026-08-24 - Das Onboarding gehoert ans KONTO, nicht ans Geraet.
--
-- Vucko woertlich am 24.08.:
--   "aber nicht das wenn man die app loescht und sie nochmal holt das man
--    wieder das tutorial spielen kann das tutorial bzw. das onboarding soll
--    einmal pro account absolviert werden und man soll dafuer auch ein badge
--    bekommen wenn man es abgeschlossen hat wie startklar"
-- und im selben Satz davor:
--   "lass jeden account mit der neuen version vorerst das tutorial
--    durchspielen ich muss es testen"
--
-- Beides zusammen heisst: EINMAL fuer alle zuruecksetzen, danach nie wieder.
--
--
-- WARUM EINE NEUE SPALTE UND NICHT starter_aufgaben
-- --------------------------------------------------
-- Die naheliegende Abkuerzung waere `starter_aufgaben ? 'tutorial'` gewesen.
-- GEMESSEN am 24.08. in der Produktivdatenbank, bevor diese Migration lief:
--
--   profiles gesamt                                183
--   davon mit 'tutorial' in starter_aufgaben         1
--   davon mit irgendeiner Starter-Aufgabe            1
--
-- Zwei Gruende sprechen dagegen, und der zweite ist der wichtigere:
--
--  1. Die Starter-Aufgabe wird NUR beim echten Abschluss gesetzt
--     (app_tutorial_overlay.dart, _complete). Wer das Tutorial UEBERSPRINGT,
--     hinterlaesst dort nichts - und saehe es nach jeder Neuinstallation
--     wieder. Genau das hat Vucko ausgeschlossen.
--  2. Die Aufgabenliste ist eine BELOHNUNGS-Liste. Sie an- und abzuschalten,
--     um damit das Onboarding zu steuern, haette das einmalige Zuruecksetzen
--     (siehe unten) unweigerlich durch die Boost-Rechnung gezogen - und Vucko
--     hat ausdruecklich gesagt, der Boost und die uebrigen erledigten
--     Aufgaben duerfen dabei NICHT mitgerissen werden.
--
-- `profiles.onboarding_completed` (existiert seit 20260627140000) ist ebenfalls
-- NICHT gemeint: das ist der Namens-Assistent nach der Anmeldung (PostAuthGate),
-- nicht die Tutorial-Tour. GEMESSEN: 168 von 183 stehen dort auf true, waehrend
-- das Tutorial nachweislich fast niemand abgeschlossen hat. Wer die beiden
-- verwechselt, sperrt 168 Leuten das Onboarding aus.
--
--
-- DAS EINMALIGE ZURUECKSETZEN
-- ---------------------------
-- Es steht NICHT als UPDATE in dieser Datei - es braucht keines. Die Spalte
-- ist neu und damit fuer alle 183 Profile NULL, also gilt fuer jeden "noch
-- nicht absolviert". Das ist das Zuruecksetzen, und es kann sich per
-- Konstruktion nicht wiederholen: eine Spalte wird nur einmal angelegt.
-- Die Geraeteseite (SharedPreferences sagt "schon gesehen") raeumt der Client
-- ueber AppTutorialService.ruecksetzGeneration ab - ebenfalls genau einmal.
--
-- NICHT ANGEFASST, mit Absicht: badges, starter_aufgaben, starter_bonus_ende.
-- Wer den Boost hat, behaelt ihn.

alter table public.profiles
  add column if not exists tutorial_abgeschlossen_am timestamptz;

comment on column public.profiles.tutorial_abgeschlossen_am is
  '2026-08-24: Wann das App-Tutorial (Onboarding-Tour) auf diesem KONTO '
  'beendet wurde - abgeschlossen ODER uebersprungen, beides beendet die Tour. '
  'NULL heisst: laeuft noch. Loest den Geraete-Merker '
  'app_tutorial_v2_completed ab, der eine Neuinstallation nicht ueberlebt hat. '
  'Nicht zu verwechseln mit onboarding_completed - das ist der Namens-'
  'Assistent nach der Anmeldung.';


-- ---------------------------------------------------------------------------
-- Waechter: einmal gesetzt, bleibt gesetzt
-- ---------------------------------------------------------------------------
--
-- Gebaut wie trg_guard_starter_bonus_ende (20260819120000), aus demselben
-- Grund: Ein zweites Geraet, eine aeltere App-Version oder ein manipulierter
-- Aufruf darf den Abschluss nicht zurueckdrehen - sonst waere die Runde
-- "App loeschen, neu holen, Tutorial nochmal" ueber den Umweg des Clients
-- wieder offen.
--
-- Zusaetzlich wird der Zeitpunkt beim ERSTEN Setzen auf now() gezogen. Der
-- Client schickt zwar now(), aber der Wert ist eine Urkunde ("seit wann ist
-- dieses Konto durch"); frei waehlbare Zeitstempel gehoeren nicht dazu.
--
-- auth.uid() is not null grenzt Clients von Serverjobs ab: ein Support-Fall
-- bleibt ueber den Service-Key korrigierbar, genau wie beim Bonus-Ende.
create or replace function public.guard_tutorial_abschluss()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    return new;
  end if;

  if old.tutorial_abgeschlossen_am is not null then
    -- Schon durch: der alte Wert gilt, egal was ankommt (auch NULL).
    new.tutorial_abgeschlossen_am := old.tutorial_abgeschlossen_am;
  elsif new.tutorial_abgeschlossen_am is not null then
    -- Erstes Setzen: der Zeitpunkt kommt von der Datenbank, nicht vom Handy.
    new.tutorial_abgeschlossen_am := now();
  end if;

  return new;
end;
$$;

comment on function public.guard_tutorial_abschluss() is
  '2026-08-24: Macht profiles.tutorial_abgeschlossen_am fuer Clients '
  'schreib-einmalig und setzt den Zeitpunkt selbst. Serverjobs (auth.uid() '
  'is null) bleiben aussen vor.';

drop trigger if exists trg_guard_tutorial_abschluss on public.profiles;
create trigger trg_guard_tutorial_abschluss
  before update on public.profiles
  for each row
  execute function public.guard_tutorial_abschluss();


-- ---------------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------------
--
-- GEMESSEN: UPDATE auf public.profiles ist SPALTENWEISE vergeben (52 Spalten
-- fuer authenticated). Eine neue Spalte ist dort NICHT automatisch dabei -
-- ohne diese Zeile scheitert jeder Schreibversuch des Clients mit 42501 und
-- das Tutorial waere fuer immer "noch nicht abgeschlossen".
grant update (tutorial_abgeschlossen_am) on public.profiles to authenticated;

-- SELECT liegt auf Tabellenebene; die Zeile steht nur da, damit ein spaeterer
-- Umbau auf spaltenweise Leserechte diese Spalte nicht vergisst.
grant select (tutorial_abgeschlossen_am) on public.profiles to authenticated;

-- anon bekommt bewusst NICHTS. Die alten anon-UPDATE-Rechte auf profiles sind
-- Altbestand (siehe 20260824100000, Teil 3, dieselbe Beobachtung fuer
-- user_drive_sessions); diese Spalte vergroessert ihn nicht.
