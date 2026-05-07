-- Persistent interactive roundtrip search sessions.
-- Long 75/100 km roundtrips must not finish heavy full-geometry hydration in
-- the user-facing Edge request. This table lets the worker complete them in
-- bounded follow-up invocations.

CREATE TABLE IF NOT EXISTS public.route_search_sessions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '45 minutes'),
  user_id uuid,
  route_type text NOT NULL DEFAULT 'ROUND_TRIP'
    CHECK (route_type IN ('ROUND_TRIP')),
  origin_lng double precision NOT NULL CHECK (origin_lng BETWEEN -180 AND 180),
  origin_lat double precision NOT NULL CHECK (origin_lat BETWEEN -90 AND 90),
  distance_bucket integer NOT NULL CHECK (distance_bucket IN (50, 75, 100)),
  style_key text NOT NULL CHECK (length(trim(style_key)) > 0),
  avoid_highways boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN (
      'queued',
      'running',
      'hydrating',
      'found',
      'no_route',
      'failed',
      'expired'
    )),
  progress_stage text NOT NULL DEFAULT 'queued',
  attempts_count integer NOT NULL DEFAULT 0 CHECK (attempts_count >= 0),
  mapbox_calls_used integer NOT NULL DEFAULT 0 CHECK (mapbox_calls_used >= 0),
  request_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  best_candidate_payload jsonb,
  candidate_queue_payload jsonb NOT NULL DEFAULT '[]'::jsonb,
  best_route_payload jsonb,
  best_route_fingerprint text,
  reject_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  seed_job_id uuid REFERENCES public.route_seed_jobs(id) ON DELETE SET NULL,
  worker_last_seen_at timestamptz,
  locked_until timestamptz,
  last_error text
);

CREATE INDEX IF NOT EXISTS idx_route_search_sessions_status
  ON public.route_search_sessions (status, updated_at ASC)
  WHERE status IN ('queued', 'running', 'hydrating');

CREATE INDEX IF NOT EXISTS idx_route_search_sessions_expires
  ON public.route_search_sessions (expires_at);

CREATE INDEX IF NOT EXISTS idx_route_search_sessions_cell
  ON public.route_search_sessions (
    distance_bucket,
    style_key,
    avoid_highways,
    created_at DESC
  );

ALTER TABLE public.route_search_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Route search sessions are service managed"
  ON public.route_search_sessions;

CREATE POLICY "Route search sessions are service managed"
  ON public.route_search_sessions
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
