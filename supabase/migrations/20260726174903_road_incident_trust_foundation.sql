-- ===========================================================================
-- Missbrauchsschutz fuer Verkehrsmeldungen — Teil 1: Fundament
-- 2026-07-26 (vucko "zuverlaessiges System, das nicht ausgenutzt werden kann")
--
-- Ausgangslage: 21 Nutzer. Waze-artiges Mehrheitsvoting funktioniert bei der
-- Dichte NICHT (zwei Fahrer sind praktisch nie gleichzeitig auf derselben
-- Strasse). Der Schutz stuetzt sich deshalb auf serverseitige Plausibilitaet
-- und Konto-Limits; Abstimmung ist nur die Kuer und waechst mit der Nutzerzahl.
-- ===========================================================================

-- Entfernung in Metern (Haversine). Bewusst ohne PostGIS/earthdistance —
-- keine Extension-Abhaengigkeit, fuer unsere Radien (Meter bis km) exakt genug.
create or replace function public.geo_distance_m(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable parallel safe
set search_path to 'public'
as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else 6371000.0 * 2.0 * asin(least(1.0, sqrt(
      power(sin(radians(lat2 - lat1) / 2.0), 2) +
      cos(radians(lat1)) * cos(radians(lat2)) *
      power(sin(radians(lng2 - lng1) / 2.0), 2)
    )))
  end;
$$;

-- Alle Schwellwerte an EINER Stelle und zur Laufzeit aenderbar — ohne diese
-- Tabelle muesste fuer jede Nachjustierung eine Migration deployed werden.
create table if not exists public.road_incident_settings (
  id boolean primary key default true check (id),
  report_min_interval_sec   int     not null default 180,
  report_daily_limit_low    int     not null default 3,
  report_daily_limit_normal int     not null default 8,
  report_daily_limit_high   int     not null default 15,
  proximity_max_m           double precision not null default 500,
  position_max_age_sec      int     not null default 180,
  self_repeat_radius_m      double precision not null default 1000,
  self_repeat_window_sec    int     not null default 1800,
  merge_radius_m            double precision not null default 200,
  max_plausible_kmh         double precision not null default 250,
  ttl_stau_sec              int     not null default 2700,
  ttl_unfall_sec            int     not null default 10800,
  ttl_baustelle_sec         int     not null default 43200,
  ttl_unverified_sec        int     not null default 900,
  ttl_cap_sec               int     not null default 89000,
  vote_daily_limit          int     not null default 20,
  vote_proximity_max_m      double precision not null default 1000,
  trust_shadow_below        numeric not null default 0.5,
  trust_block_below         numeric not null default 0.3,
  min_account_age_sec       int     not null default 86400,
  updated_at                timestamptz not null default now()
);
insert into public.road_incident_settings (id) values (true) on conflict do nothing;

-- Gedaechtnis pro Melder. Ohne das darf jemand, der gestern 200 Falschmeldungen
-- abgesetzt hat, heute unveraendert weitermachen.
create table if not exists public.road_reporter_stats (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  reports_total    int not null default 0,
  reports_upheld   int not null default 0,
  reports_rejected int not null default 0,
  votes_total      int not null default 0,
  trust            numeric not null default 1.0 check (trust >= 0 and trust <= 2),
  -- Stufe 1: stille Sperre. Meldungen werden angenommen und sind fuer den
  -- Melder sichtbar, erreichen aber niemanden sonst.
  shadow_until     timestamptz,
  -- Stufe 2 (Wiederholungsfall): harte, dem Nutzer angesagte Sperre.
  blocked_until    timestamptz,
  blocked_reason   text,
  strikes          int not null default 0,
  updated_at       timestamptz not null default now()
);
alter table public.road_reporter_stats enable row level security;
-- Jeder sieht nur seinen eigenen Stand (fuer eine ehrliche Sperr-Anzeige in der
-- App). Geschrieben wird ausschliesslich aus SECURITY-DEFINER-Funktionen.
drop policy if exists rrs_own_read on public.road_reporter_stats;
create policy rrs_own_read on public.road_reporter_stats
  for select to authenticated using (user_id = auth.uid());
revoke all on public.road_reporter_stats from anon, authenticated;
grant select on public.road_reporter_stats to authenticated;

-- Meldungen: Sichtbarkeit und Positionsnachweis.
alter table public.road_incidents
  add column if not exists visibility text not null default 'public',
  add column if not exists position_verified boolean not null default false,
  add column if not exists retracted_at timestamptz;

do $$ begin
  alter table public.road_incidents
    add constraint road_incidents_visibility_check
    check (visibility in ('public', 'shadow'));
exception when duplicate_object then null; end $$;

-- Der 25h-Deckel aus der ersten Fassung wird jetzt serverseitig gesetzt; die
-- Pruefung bleibt als zweites Netz bestehen.
create index if not exists road_incidents_geo_idx
  on public.road_incidents (type, active, lat, lng) where active;
create index if not exists road_incidents_reporter_time_idx
  on public.road_incidents (reported_by, created_at desc);
create index if not exists road_incident_votes_user_time_idx
  on public.road_incident_votes (user_id, created_at desc);;
