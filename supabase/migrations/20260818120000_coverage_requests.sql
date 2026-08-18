-- 2026-08-18 (Defekt 1c): Warteliste fuer Regionen ausserhalb der Abdeckung.
--
-- Ausgangslage (gemessen am 18.08. in der Produktivdatenbank):
-- 165 Fehlversuche `coverage_out_of_bounds` in 14 Tagen, davon 113 von einem
-- einzigen Nutzer, der eine Minute nach der Registrierung anfing. In
-- `route_generation_events` werden KEINE Koordinaten gespeichert, deshalb war
-- bis heute unbekannt, WO diese Nutzer sitzen. Diese Tabelle beantwortet das.
--
-- Die Edge-Funktion schreibt hier mit dem Service-Role-Key. Der Client
-- schreibt nie selbst; er darf nur seine eigenen Eintraege lesen.
create table if not exists public.coverage_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  -- Auf drei Nachkommastellen gerundet (~110 m). Genau genug fuer die Frage
  -- „welche Region freischalten", zu grob fuer eine Wohnadresse.
  lat double precision not null,
  lng double precision not null,
  country_code text,
  created_at timestamptz not null default now(),
  notified_at timestamptz
);

create index if not exists coverage_requests_created_at_idx
  on public.coverage_requests (created_at desc);
create index if not exists coverage_requests_user_idx
  on public.coverage_requests (user_id) where user_id is not null;

alter table public.coverage_requests enable row level security;

-- Nur Lesen der eigenen Zeilen. Kein INSERT/UPDATE/DELETE fuer Clients:
-- geschrieben wird ausschliesslich serverseitig von der Edge-Funktion.
drop policy if exists "coverage_requests_select_own" on public.coverage_requests;
create policy "coverage_requests_select_own"
  on public.coverage_requests for select
  to authenticated
  using (auth.uid() = user_id);
