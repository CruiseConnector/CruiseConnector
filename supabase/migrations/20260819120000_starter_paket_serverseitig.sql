-- 2026-08-19 (vucko): Das Starter-Paket lebte nur auf dem Geraet.
--
-- GEMESSEN am 19.08.: `starter_aufgaben_erledigt_v1`, `starter_bonus_ende_v1`
-- und `starter_paket_vergeben_v1` lagen ausschliesslich in den
-- SharedPreferences. Folgen:
--   * Ein Geraetewechsel loeschte die laufende Bonuswoche ersatzlos.
--   * Derselbe Account konnte auf einem zweiten Geraet eine ZWEITE Bonuswoche
--     bekommen, weil serverseitig nichts blockte.
-- Ausserdem war der Zustand fuer die nachtraegliche Vergabe von `badge_16`
-- ("Startklar", 0 von 152 Profilen) serverseitig gar nicht bekannt.
--
-- Deshalb wandern beide Werte auf `profiles`. Die Spalten sind absichtlich
-- schlank: keine eigene Tabelle, kein Umbau, ein UPDATE pro Abgleich.
alter table public.profiles
  add column if not exists starter_aufgaben jsonb not null default '[]'::jsonb,
  add column if not exists starter_bonus_ende timestamptz;

comment on column public.profiles.starter_aufgaben is
  'Erledigte Starter-Aufgaben als JSON-Liste von IDs (tutorial, route, '
  'favorit, speichern, community, runde, post, gruppenfahrt). Wird mit dem '
  'Geraetestand VEREINIGT, nie ersetzt.';

comment on column public.profiles.starter_bonus_ende is
  'Ende der einmaligen Doppel-XP-Woche. SCHREIB-EINMALIG: siehe Trigger '
  'trg_guard_starter_bonus_ende. Null = noch nie vergeben.';

-- Die Bonuswoche gibt es genau EINMAL pro Account. Ohne diese Sperre koennte
-- ein zweites Geraet (frische Installation, leerer Geraetespeicher) ein neues
-- Ende setzen und sich damit eine zweite Woche Doppel-XP verschaffen.
-- Admins/Serverjobs (auth.uid() is null, service_role) bleiben aussen vor,
-- damit ein Support-Fall noch korrigierbar ist.
-- SECURITY INVOKER mit Absicht: Die Funktion braucht keine fremden Rechte,
-- sie liest nur OLD/NEW und auth.uid(). Als SECURITY DEFINER haette der
-- Supabase-Advisor sie zu Recht als per RPC aufrufbar gemeldet
-- (anon_security_definer_function_executable) — genau das war beim ersten
-- Anlauf am 19.08. der Befund.
create or replace function public.guard_starter_bonus_ende()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $$
begin
  if auth.uid() is not null
     and old.starter_bonus_ende is not null
     and new.starter_bonus_ende is distinct from old.starter_bonus_ende
  then
    new.starter_bonus_ende := old.starter_bonus_ende;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_starter_bonus_ende on public.profiles;
create trigger trg_guard_starter_bonus_ende
  before update on public.profiles
  for each row
  execute function public.guard_starter_bonus_ende();
