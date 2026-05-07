-- Persist the minimum verified density per route-pool coverage cell.
-- Target/max already cap desired pool size; min_verified_count makes the
-- healing trigger explicit instead of relying only on legacy thresholds.

ALTER TABLE public.route_regions
  ADD COLUMN IF NOT EXISTS default_min_verified_count integer NOT NULL DEFAULT 3
    CHECK (default_min_verified_count BETWEEN 0 AND 50);

ALTER TABLE public.route_pool_coverage
  ADD COLUMN IF NOT EXISTS min_verified_count integer NOT NULL DEFAULT 3
    CHECK (min_verified_count BETWEEN 0 AND 50);

UPDATE public.route_pool_coverage
SET min_verified_count = LEAST(
  GREATEST(min_verified_count, 3),
  GREATEST(target_pool_size, 3)
)
WHERE min_verified_count IS DISTINCT FROM LEAST(
  GREATEST(min_verified_count, 3),
  GREATEST(target_pool_size, 3)
);

UPDATE public.route_pool_coverage
SET
  target_pool_size = GREATEST(target_pool_size, min_verified_count),
  max_pool_size = GREATEST(max_pool_size, target_pool_size, min_verified_count)
WHERE target_pool_size < min_verified_count
   OR max_pool_size < target_pool_size
   OR max_pool_size < min_verified_count;

DO $$
BEGIN
  ALTER TABLE public.route_pool_coverage
    ADD CONSTRAINT route_pool_coverage_size_policy_check
    CHECK (
      min_verified_count >= 0 AND
      min_verified_count <= target_pool_size AND
      target_pool_size <= max_pool_size
    );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
