-- Align route_seed_jobs with the Dart RouteSeedJob model used by the
-- controlled pool bootstrap path. These columns are metadata only; the
-- unique request key remains unchanged.

ALTER TABLE public.route_seed_jobs
  ADD COLUMN IF NOT EXISTS difficulty_level text NOT NULL DEFAULT 'normal'
    CHECK (difficulty_level IN ('easy', 'normal', 'hard')),
  ADD COLUMN IF NOT EXISTS hard_region_status text NOT NULL DEFAULT 'normal'
    CHECK (hard_region_status IN ('normal', 'curated_needed', 'bootstrap_limited')),
  ADD COLUMN IF NOT EXISTS seed_budget_units integer NOT NULL DEFAULT 1
    CHECK (seed_budget_units BETWEEN 0 AND 20),
  ADD COLUMN IF NOT EXISTS seed_cooldown_minutes integer NOT NULL DEFAULT 20
    CHECK (seed_cooldown_minutes BETWEEN 1 AND 1440);

