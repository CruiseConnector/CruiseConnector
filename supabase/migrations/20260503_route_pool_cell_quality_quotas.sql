-- Per-cell route-pool quality quota bookkeeping.
-- Coverage cells are keyed by region + route_type + distance_bucket +
-- style_key + avoid_highways; these counters keep health decisions scoped to
-- that exact combination instead of the city as a whole.

ALTER TABLE public.route_pool_coverage
  DROP CONSTRAINT IF EXISTS route_pool_coverage_coverage_status_check;

ALTER TABLE public.route_pool_coverage
  ADD CONSTRAINT route_pool_coverage_coverage_status_check CHECK (
    coverage_status IN (
      'healthy',
      'target_met',
      'overfull',
      'quality_thin',
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
  ADD COLUMN IF NOT EXISTS candidate_buffer_limit integer NOT NULL DEFAULT 30
    CHECK (candidate_buffer_limit BETWEEN 0 AND 200),
  ADD COLUMN IF NOT EXISTS acceptable_reserve_limit_percent integer NOT NULL DEFAULT 25
    CHECK (acceptable_reserve_limit_percent BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS ideal_count integer NOT NULL DEFAULT 0
    CHECK (ideal_count >= 0),
  ADD COLUMN IF NOT EXISTS good_count integer NOT NULL DEFAULT 0
    CHECK (good_count >= 0),
  ADD COLUMN IF NOT EXISTS acceptable_count integer NOT NULL DEFAULT 0
    CHECK (acceptable_count >= 0),
  ADD COLUMN IF NOT EXISTS rejected_count integer NOT NULL DEFAULT 0
    CHECK (rejected_count >= 0),
  ADD COLUMN IF NOT EXISTS distinct_fingerprint_count integer NOT NULL DEFAULT 0
    CHECK (distinct_fingerprint_count >= 0);

UPDATE public.route_pool_coverage
SET
  min_verified_count = 3,
  target_pool_size = 8,
  max_pool_size = GREATEST(max_pool_size, 20),
  healthy_threshold = 3,
  candidate_buffer_limit = 30,
  acceptable_reserve_limit_percent = 25
WHERE min_verified_count IS DISTINCT FROM 3
   OR target_pool_size IS DISTINCT FROM 8
   OR max_pool_size < 20
   OR healthy_threshold IS DISTINCT FROM 3
   OR candidate_buffer_limit IS DISTINCT FROM 30
   OR acceptable_reserve_limit_percent IS DISTINCT FROM 25;
