-- Productive weekly route-pool curation worker support.
-- The trusted Edge Function `curate-route-pool` performs promotion/demotion.
-- This migration keeps the DB side idempotent, auditable, and non-destructive.

ALTER TABLE public.route_pool_curation_runs
  ADD COLUMN IF NOT EXISTS started_at timestamptz,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS error_message text,
  ADD COLUMN IF NOT EXISTS stats jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_route_pool_curation_runs_weekly
  ON public.route_pool_curation_runs (scheduled_for DESC, status, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_route_ratings_curation_fingerprint
  ON public.route_ratings (route_fingerprint, created_at DESC, rating, completion_percent);

CREATE INDEX IF NOT EXISTS idx_route_pool_candidates_curation
  ON public.route_pool_candidates (
    is_candidate,
    is_verified_pool,
    promoted_to_pool_at,
    demoted_at,
    rating_count DESC,
    average_rating DESC,
    completion_rate DESC
  );

CREATE INDEX IF NOT EXISTS idx_route_pool_curation_active
  ON public.route_pool (
    verified,
    is_active,
    country_code,
    admin1_name,
    city_cluster,
    route_type,
    distance_bucket,
    avoids_highway,
    rating_count DESC,
    average_rating DESC,
    completion_rate DESC
  );

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_net;
EXCEPTION
  WHEN insufficient_privilege OR undefined_file THEN
    RAISE NOTICE 'pg_net is not available; configure Supabase Cron to call curate-route-pool directly.';
END
$$;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION
  WHEN insufficient_privilege OR undefined_file THEN
    RAISE NOTICE 'pg_cron is not available; configure Supabase Cron in the dashboard.';
END
$$;

CREATE OR REPLACE FUNCTION public.invoke_route_pool_curation_edge()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  run_id uuid;
  supabase_url text := nullif(current_setting('app.settings.supabase_url', true), '');
  cron_secret text := nullif(current_setting('app.settings.route_pool_curation_cron_secret', true), '');
BEGIN
  INSERT INTO public.route_pool_curation_runs (
    scheduled_for,
    status,
    notes
  )
  VALUES (
    now(),
    'queued',
    'Queued by weekly cron for trusted Edge Function curate-route-pool.'
  )
  RETURNING id INTO run_id;

  IF supabase_url IS NULL OR cron_secret IS NULL THEN
    UPDATE public.route_pool_curation_runs
    SET
      status = 'failed',
      error_message = 'missing app.settings.supabase_url or app.settings.route_pool_curation_cron_secret',
      completed_at = now(),
      updated_at = now()
    WHERE id = run_id;
    RETURN;
  END IF;

  EXECUTE 'SELECT net.http_post(url := $1, headers := $2, body := $3)'
  USING
    supabase_url || '/functions/v1/curate-route-pool',
    jsonb_build_object(
      'content-type', 'application/json',
      'x-cron-secret', cron_secret
    ),
    jsonb_build_object(
      'run_id', run_id,
      'trigger', 'weekly_cron'
    );
END;
$$;

DO $$
BEGIN
  IF current_setting('app.settings.enable_route_pool_curation_cron', true) = 'true' THEN
    BEGIN
      PERFORM cron.unschedule('weekly-route-pool-curation');
    EXCEPTION
      WHEN undefined_function OR undefined_object THEN
        NULL;
    END;

    PERFORM cron.schedule(
      'weekly-route-pool-curation',
      '59 23 * * 0',
      'select public.invoke_route_pool_curation_edge();'
    );
  END IF;
EXCEPTION
  WHEN undefined_table OR undefined_function THEN
    RAISE NOTICE 'pg_cron is not installed; weekly route-pool curation must be scheduled from Supabase dashboard.';
END
$$;

COMMENT ON FUNCTION public.invoke_route_pool_curation_edge() IS
  'Queues and invokes the trusted curate-route-pool Edge Function. Requires app.settings.supabase_url and app.settings.route_pool_curation_cron_secret.';
