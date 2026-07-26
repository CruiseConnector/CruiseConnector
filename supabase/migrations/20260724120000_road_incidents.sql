-- 2026-07-24 (vucko "+-Button: Unfall/Baustelle/Stau melden"): Waze-artige
-- Crowd-Meldungen während der Fahrt. Andere Fahrer sehen die Meldungen live
-- auf der Karte (Realtime) und stimmen beim Vorbeifahren ab ("Noch da?").
-- Lebensdauer = TTL pro Typ (clientseitig beim Insert gesetzt) UND
-- Dismiss-Votes (>=3 "weg" → inaktiv, via RPC unten).
--
-- Muster nach 20260722120000_community_chat_reactions.sql (RLS + Realtime)
-- und dem bestehenden construction_reports/construction_votes-System.

create table if not exists public.road_incidents (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('unfall', 'baustelle', 'stau')),
  lat double precision not null,
  lng double precision not null,
  reported_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  -- Reporter zählt als erste Bestätigung (wie bei construction_reports).
  confirmed_count int not null default 1,
  dismissed_count int not null default 0,
  last_confirmed_at timestamptz not null default now(),
  active boolean not null default true,
  -- Nur für type='stau': Stau-Ausdehnung. Der Melder trackt nach dem Report
  -- weiter, bis wieder flüssig gefahren wird, und schreibt dann das Stau-Ende.
  jam_end_lat double precision,
  jam_end_lng double precision
);

create index if not exists road_incidents_active_idx
  on public.road_incidents (active, expires_at);
create index if not exists road_incidents_geo_idx
  on public.road_incidents (lat, lng);

alter table public.road_incidents enable row level security;

-- Jeder eingeloggte Nutzer sieht nur aktive, nicht abgelaufene Meldungen.
create policy ri_select on public.road_incidents
  for select using (active and expires_at > now());

create policy ri_insert on public.road_incidents
  for insert with check (reported_by = auth.uid());

-- Nur der Melder darf seine eigene Meldung updaten (Stau-Ausdehnung).
create policy ri_update_own on public.road_incidents
  for update using (reported_by = auth.uid())
  with check (reported_by = auth.uid());

-- Ein Vote pro (Meldung, Nutzer); erneutes Voten überschreibt (upsert im RPC).
create table if not exists public.road_incident_votes (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.road_incidents(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  vote text not null check (vote in ('confirm', 'dismiss')),
  created_at timestamptz not null default now(),
  unique (incident_id, user_id)
);

alter table public.road_incident_votes enable row level security;

create policy riv_own on public.road_incident_votes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- SECURITY DEFINER hält Counter + active konsistent und verhindert, dass
-- Clients die Zähler direkt manipulieren (kein UPDATE-Grant auf Counter
-- nötig — die ri_update_own-Policy oben ist nur für die Stau-Ausdehnung
-- des Melders selbst).
create or replace function public.vote_road_incident(
  p_incident_id uuid,
  p_vote text
) returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_vote not in ('confirm', 'dismiss') then
    raise exception 'invalid vote';
  end if;

  insert into road_incident_votes (incident_id, user_id, vote)
  values (p_incident_id, auth.uid(), p_vote)
  on conflict (incident_id, user_id) do update set vote = excluded.vote;

  update road_incidents set
    confirmed_count = 1 + (
      select count(*) from road_incident_votes
      where incident_id = p_incident_id and vote = 'confirm'
        and user_id is distinct from road_incidents.reported_by
    ),
    dismissed_count = (
      select count(*) from road_incident_votes
      where incident_id = p_incident_id and vote = 'dismiss'
    ),
    last_confirmed_at = case
      when p_vote = 'confirm' then now() else last_confirmed_at end,
    active = case
      when (
        select count(*) from road_incident_votes
        where incident_id = p_incident_id and vote = 'dismiss'
      ) >= 3 then false
      else active end
  where id = p_incident_id;
end;
$$;

-- Realtime für Live-Sync auf anderen Geräten (idempotent, Muster
-- 20260722120000_community_chat_reactions.sql).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'road_incidents'
  ) then
    alter publication supabase_realtime add table public.road_incidents;
  end if;
end $$;
