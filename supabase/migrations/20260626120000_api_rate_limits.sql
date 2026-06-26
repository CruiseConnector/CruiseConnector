-- 2026-06-26 (vucko): Request-Level Rate-Limiting für kritische APIs.
--
-- Schützt DB + GraphHopper (via Edge generate-cruise-route-v2) gegen Spam/Abuse,
-- OHNE normale Nutzer (oder die live-testende Suite) zu beeinträchtigen:
--  * großzügige Limits (ein normaler User erreicht sie nie),
--  * HART fail-open — jeder DB-/Funktionsfehler => Request darf durch
--    (Routing geht NIEMALS wegen des Limiters kaputt),
--  * generischer atomarer Fixed-Window-Zähler, von mehreren Edge-Functions
--    mit eigenen `action`-Strings wiederverwendbar.
--
-- Stil gespiegelt von 20260623_group_leaderboard.sql (SECURITY DEFINER +
-- set search_path = public + explizites grant execute).

-- Schmaler Fixed-Window-Counter: eine Zeile je (key, action, window_start).
create table if not exists public.api_rate_limits (
  rl_key       text        not null,   -- "uid:<auth.uid>" | "ip:<addr>" | "anon:shared"
  action       text        not null,   -- "route_generate" | "route_reroute" | ...
  window_start timestamptz not null,   -- auf Fensterbreite gefloort
  count        integer     not null default 0,
  primary key (rl_key, action, window_start)
);

create index if not exists api_rate_limits_window_idx
  on public.api_rate_limits (window_start);

-- KEINE RLS-Policies: nur über die SECURITY-DEFINER-Funktion bzw. service_role
-- erreichbar — kein direkter anon/authenticated-Zugriff.
alter table public.api_rate_limits enable row level security;

-- Atomarer Fixed-Window-Check. Ein einziger Upsert hält den Row-Lock => bei
-- Nebenläufigkeit serialisieren konkurrierende Calls sauber (kein Lost-Update).
create or replace function public.check_rate_limit(
  p_key            text,
  p_action         text,
  p_max            integer,
  p_window_seconds integer
)
returns table (allowed boolean, retry_after integer, current_count integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_start timestamptz;
  v_count        integer;
begin
  -- Defensive: unsinnige Parameter => fail-open (erlauben), nie blockieren.
  if p_key is null or p_action is null
     or coalesce(p_max, 0) <= 0
     or coalesce(p_window_seconds, 0) <= 0 then
    return query select true, 0, 0;
    return;
  end if;

  -- Fenster-Bucket: aktuellen Zeitpunkt auf Fensterbreite floor()en.
  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  -- ATOMAR hochzählen (oder Zeile anlegen).
  insert into public.api_rate_limits as r (rl_key, action, window_start, count)
  values (p_key, p_action, v_window_start, 1)
  on conflict (rl_key, action, window_start)
  do update set count = r.count + 1
  returning r.count into v_count;

  if v_count <= p_max then
    return query select true, 0, v_count;
  else
    return query select
      false,
      greatest(
        1,
        ceil(extract(epoch from
          (v_window_start + make_interval(secs => p_window_seconds)) - now()
        ))::int
      ),
      v_count;
  end if;
exception
  when others then
    -- HARTE FAIL-OPEN-GARANTIE: jeder Fehler => Request darf durch.
    return query select true, 0, 0;
end;
$$;

revoke all on function public.check_rate_limit(text, text, integer, integer) from public;
grant execute on function public.check_rate_limit(text, text, integer, integer) to service_role;
