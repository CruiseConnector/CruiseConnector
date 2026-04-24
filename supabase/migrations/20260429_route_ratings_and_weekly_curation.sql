-- Route ratings and weekly curation preparation.
-- No cron is enabled here; this only prepares the data model and queue surface.

ALTER TABLE public.routes
  ADD COLUMN IF NOT EXISTS route_source text,
  ADD COLUMN IF NOT EXISTS route_fingerprint text,
  ADD COLUMN IF NOT EXISTS quality_tier text,
  ADD COLUMN IF NOT EXISTS route_meta jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_routes_route_fingerprint
  ON public.routes (route_fingerprint)
  WHERE route_fingerprint IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.route_ratings (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  route_id text,
  route_fingerprint text NOT NULL,
  route_source text NOT NULL DEFAULT 'unknown'
    CHECK (route_source IN ('mapbox', 'pool', 'cache', 'bootstrap_pool', 'saved', 'unknown')),
  rating integer CHECK (rating BETWEEN 1 AND 5),
  tags text[] NOT NULL DEFAULT '{}',
  completion_percent double precision CHECK (
    completion_percent IS NULL OR
    (completion_percent >= 0 AND completion_percent <= 100)
  ),
  distance_km double precision CHECK (distance_km IS NULL OR distance_km >= 0),
  duration_seconds integer CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  quality_tier text CHECK (
    quality_tier IS NULL OR
    quality_tier IN ('ideal', 'good', 'acceptable', 'rejected')
  ),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_ratings_user_fingerprint
  ON public.route_ratings (user_id, route_fingerprint);

CREATE INDEX IF NOT EXISTS idx_route_ratings_route_lookup
  ON public.route_ratings (route_fingerprint, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_route_ratings_pool_feedback
  ON public.route_ratings (route_id, rating, completion_percent)
  WHERE route_id IS NOT NULL;

ALTER TABLE public.route_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Route ratings own select" ON public.route_ratings;
CREATE POLICY "Route ratings own select"
  ON public.route_ratings FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Route ratings own insert" ON public.route_ratings;
CREATE POLICY "Route ratings own insert"
  ON public.route_ratings FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Route ratings own update" ON public.route_ratings;
CREATE POLICY "Route ratings own update"
  ON public.route_ratings FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.route_pool_curation_config (
  id boolean PRIMARY KEY DEFAULT true,
  timezone text NOT NULL DEFAULT 'Europe/Vienna',
  run_weekday integer NOT NULL DEFAULT 0 CHECK (run_weekday BETWEEN 0 AND 6),
  run_time time NOT NULL DEFAULT '23:59',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.route_pool_curation_config (id, timezone, run_weekday, run_time, is_active)
VALUES (true, 'Europe/Vienna', 0, '23:59', true)
ON CONFLICT (id) DO UPDATE SET
  timezone = EXCLUDED.timezone,
  run_weekday = EXCLUDED.run_weekday,
  run_time = EXCLUDED.run_time,
  is_active = EXCLUDED.is_active,
  updated_at = now();

CREATE TABLE IF NOT EXISTS public.route_pool_curation_runs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  requested_at timestamptz NOT NULL DEFAULT now(),
  scheduled_for timestamptz,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'completed', 'failed')),
  promoted_count integer NOT NULL DEFAULT 0 CHECK (promoted_count >= 0),
  demoted_count integer NOT NULL DEFAULT 0 CHECK (demoted_count >= 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_route_pool_curation_runs_status
  ON public.route_pool_curation_runs (status, requested_at DESC);

CREATE OR REPLACE FUNCTION public.queue_weekly_route_pool_curation(
  scheduled_for_param timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  run_id uuid;
BEGIN
  INSERT INTO public.route_pool_curation_runs (scheduled_for, status, notes)
  VALUES (
    scheduled_for_param,
    'queued',
    'Prepared weekly route-pool curation. Promote/demote logic must be executed by the trusted backend job; no hard delete.'
  )
  RETURNING id INTO run_id;

  RETURN run_id;
END;
$$;

COMMENT ON TABLE public.route_pool_curation_config IS
  'Weekly route-pool curation schedule. Target: Sunday 23:59 Europe/Vienna. Activate through Supabase scheduler/cron only in a trusted backend context.';

COMMENT ON FUNCTION public.queue_weekly_route_pool_curation(timestamptz) IS
  'Queues a curation run placeholder. The actual trusted job must promote candidates and demote old/low-rated verified routes without deleting them.';
