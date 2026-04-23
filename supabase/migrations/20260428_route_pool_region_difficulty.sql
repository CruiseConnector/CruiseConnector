-- Region difficulty and seedability policies for controlled pool seeding.
-- This extends the existing coverage/bootstrap model without changing cluster creation.

ALTER TABLE public.route_regions
  ADD COLUMN IF NOT EXISTS difficulty_level text NOT NULL DEFAULT 'normal'
    CHECK (difficulty_level IN ('easy', 'normal', 'hard')),
  ADD COLUMN IF NOT EXISTS hard_region_status text NOT NULL DEFAULT 'normal'
    CHECK (hard_region_status IN ('normal', 'curated_needed', 'bootstrap_limited')),
  ADD COLUMN IF NOT EXISTS curated_seed_preferred boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS default_target_pool_size integer NOT NULL DEFAULT 15
    CHECK (default_target_pool_size BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS default_max_pool_size integer NOT NULL DEFAULT 20
    CHECK (default_max_pool_size BETWEEN 1 AND 100),
  ADD COLUMN IF NOT EXISTS healthy_threshold integer NOT NULL DEFAULT 15
    CHECK (healthy_threshold BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS thin_threshold integer NOT NULL DEFAULT 1
    CHECK (thin_threshold BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS seed_budget_units integer NOT NULL DEFAULT 1
    CHECK (seed_budget_units BETWEEN 0 AND 20),
  ADD COLUMN IF NOT EXISTS seed_cooldown_minutes integer NOT NULL DEFAULT 20
    CHECK (seed_cooldown_minutes BETWEEN 1 AND 1440);

ALTER TABLE public.route_pool_coverage
  DROP CONSTRAINT IF EXISTS route_pool_coverage_coverage_status_check;

ALTER TABLE public.route_pool_coverage
  ADD CONSTRAINT route_pool_coverage_coverage_status_check CHECK (
    coverage_status IN (
      'healthy',
      'thin',
      'empty',
      'warming_up',
      'cooldown',
      'hard_region_thin',
      'hard_region_curated_needed',
      'bootstrap_limited'
    )
  );

ALTER TABLE public.route_pool_coverage
  ADD COLUMN IF NOT EXISTS difficulty_level text NOT NULL DEFAULT 'normal'
    CHECK (difficulty_level IN ('easy', 'normal', 'hard')),
  ADD COLUMN IF NOT EXISTS hard_region_status text NOT NULL DEFAULT 'normal'
    CHECK (hard_region_status IN ('normal', 'curated_needed', 'bootstrap_limited')),
  ADD COLUMN IF NOT EXISTS bootstrap_enabled boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS curated_seed_preferred boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS healthy_threshold integer NOT NULL DEFAULT 15
    CHECK (healthy_threshold BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS thin_threshold integer NOT NULL DEFAULT 1
    CHECK (thin_threshold BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS seed_budget_units integer NOT NULL DEFAULT 1
    CHECK (seed_budget_units BETWEEN 0 AND 20),
  ADD COLUMN IF NOT EXISTS seed_cooldown_minutes integer NOT NULL DEFAULT 20
    CHECK (seed_cooldown_minutes BETWEEN 1 AND 1440);

ALTER TABLE public.route_seed_jobs
  ADD COLUMN IF NOT EXISTS failure_count integer NOT NULL DEFAULT 0
    CHECK (failure_count >= 0),
  ADD COLUMN IF NOT EXISTS last_failure_reason text;

ALTER TABLE public.route_pool_candidates
  ADD COLUMN IF NOT EXISTS candidate_region_difficulty text NOT NULL DEFAULT 'normal'
    CHECK (candidate_region_difficulty IN ('easy', 'normal', 'hard')),
  ADD COLUMN IF NOT EXISTS candidate_locality_score double precision
    CHECK (
      candidate_locality_score IS NULL OR
      (candidate_locality_score >= 0 AND candidate_locality_score <= 100)
    ),
  ADD COLUMN IF NOT EXISTS repeated_success_count integer NOT NULL DEFAULT 0
    CHECK (repeated_success_count >= 0);

UPDATE public.route_regions
SET
  difficulty_level = 'easy',
  hard_region_status = 'normal',
  curated_seed_preferred = false,
  default_target_pool_size = 18,
  default_max_pool_size = 20,
  healthy_threshold = 12,
  thin_threshold = 4,
  seed_budget_units = 2,
  seed_cooldown_minutes = 20,
  updated_at = now()
WHERE country_code = 'AT'
  AND admin1_name = 'Vorarlberg'
  AND city_cluster = 'Dornbirn';

UPDATE public.route_regions
SET
  difficulty_level = 'normal',
  hard_region_status = 'normal',
  curated_seed_preferred = false,
  default_target_pool_size = 15,
  default_max_pool_size = 18,
  healthy_threshold = 10,
  thin_threshold = 3,
  seed_budget_units = 2,
  seed_cooldown_minutes = 30,
  updated_at = now()
WHERE country_code = 'AT'
  AND admin1_name = 'Vorarlberg'
  AND city_cluster IN ('Bregenz', 'Feldkirch');

UPDATE public.route_regions
SET
  difficulty_level = 'normal',
  hard_region_status = 'normal',
  curated_seed_preferred = false,
  default_target_pool_size = 12,
  default_max_pool_size = 16,
  healthy_threshold = 8,
  thin_threshold = 3,
  seed_budget_units = 1,
  seed_cooldown_minutes = 30,
  updated_at = now()
WHERE country_code = 'AT'
  AND admin1_name = 'Vorarlberg'
  AND city_cluster = 'Rheintal-Sued';

UPDATE public.route_regions
SET
  difficulty_level = 'hard',
  hard_region_status = 'curated_needed',
  bootstrap_enabled = false,
  curated_seed_preferred = true,
  default_target_pool_size = 8,
  default_max_pool_size = 10,
  healthy_threshold = 4,
  thin_threshold = 1,
  seed_budget_units = 0,
  seed_cooldown_minutes = 180,
  updated_at = now()
WHERE country_code = 'AT'
  AND admin1_name = 'Vorarlberg'
  AND city_cluster = 'Bludenz';

UPDATE public.route_regions
SET
  cluster_kind = 'metro_cluster',
  difficulty_level = 'normal',
  hard_region_status = 'normal',
  curated_seed_preferred = false,
  default_target_pool_size = 15,
  default_max_pool_size = 18,
  healthy_threshold = 10,
  thin_threshold = 3,
  seed_budget_units = 1,
  seed_cooldown_minutes = 30,
  updated_at = now()
WHERE (country_code = 'DE' AND admin1_name = 'Bayern' AND city_cluster = 'München')
   OR (country_code = 'DE' AND admin1_name = 'Baden-Württemberg' AND city_cluster = 'Stuttgart')
   OR (country_code = 'CH' AND admin1_name = 'Zürich' AND city_cluster = 'Zürich');

UPDATE public.route_pool_coverage AS rpc
SET
  difficulty_level = rr.difficulty_level,
  hard_region_status = rr.hard_region_status,
  bootstrap_enabled = rr.bootstrap_enabled,
  curated_seed_preferred = rr.curated_seed_preferred,
  target_pool_size = rr.default_target_pool_size,
  max_pool_size = rr.default_max_pool_size,
  healthy_threshold = rr.healthy_threshold,
  thin_threshold = rr.thin_threshold,
  seed_budget_units = rr.seed_budget_units,
  seed_cooldown_minutes = rr.seed_cooldown_minutes,
  updated_at = now()
FROM public.route_regions AS rr
WHERE rpc.country_code = rr.country_code
  AND rpc.admin1_name = rr.admin1_name
  AND COALESCE(rpc.admin2_name, '') = COALESCE(rr.admin2_name, '')
  AND rpc.city_cluster = rr.city_cluster;
