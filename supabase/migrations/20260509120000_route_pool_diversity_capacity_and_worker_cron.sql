-- Increase route-pool diversity capacity and make background workers more active.
-- Secrets stay in Supabase Vault and are read at runtime by pg_cron/pg_net.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;

ALTER TABLE public.route_seed_jobs
  DROP CONSTRAINT IF EXISTS route_seed_jobs_job_kind_check,
  DROP CONSTRAINT IF EXISTS route_seed_jobs_max_mapbox_calls_check,
  DROP CONSTRAINT IF EXISTS route_seed_jobs_daily_attempt_budget_check,
  DROP CONSTRAINT IF EXISTS route_seed_jobs_monthly_attempt_budget_check,
  DROP CONSTRAINT IF EXISTS route_seed_jobs_daily_mapbox_budget_check,
  DROP CONSTRAINT IF EXISTS route_seed_jobs_monthly_mapbox_budget_check;

ALTER TABLE public.route_seed_jobs
  ADD CONSTRAINT route_seed_jobs_job_kind_check
    CHECK (
      job_kind IN (
        'seed_healing',
        'manual_seed',
        'coverage_report',
        'user_demand_learning'
      )
    ),
  ADD CONSTRAINT route_seed_jobs_max_mapbox_calls_check
    CHECK (max_mapbox_calls BETWEEN 0 AND 80),
  ADD CONSTRAINT route_seed_jobs_daily_attempt_budget_check
    CHECK (daily_attempt_budget BETWEEN 0 AND 500),
  ADD CONSTRAINT route_seed_jobs_monthly_attempt_budget_check
    CHECK (monthly_attempt_budget BETWEEN 0 AND 5000),
  ADD CONSTRAINT route_seed_jobs_daily_mapbox_budget_check
    CHECK (daily_mapbox_budget BETWEEN 0 AND 500),
  ADD CONSTRAINT route_seed_jobs_monthly_mapbox_budget_check
    CHECK (monthly_mapbox_budget BETWEEN 0 AND 5000);

ALTER TABLE public.route_seed_jobs
  ALTER COLUMN max_mapbox_calls SET DEFAULT 36,
  ALTER COLUMN daily_attempt_budget SET DEFAULT 240,
  ALTER COLUMN monthly_attempt_budget SET DEFAULT 4000,
  ALTER COLUMN daily_mapbox_budget SET DEFAULT 300,
  ALTER COLUMN monthly_mapbox_budget SET DEFAULT 4000;

UPDATE public.route_regions
SET
  default_target_pool_size = GREATEST(default_target_pool_size, 12),
  default_max_pool_size = GREATEST(default_max_pool_size, 32),
  healthy_threshold = GREATEST(healthy_threshold, 12),
  updated_at = now()
WHERE is_active
  AND NOT (
    difficulty_level = 'hard'
    AND curated_seed_preferred IS TRUE
  );

WITH desired AS (
  SELECT
    rpc.id,
    GREATEST(
      rpc.target_pool_size,
      rr.default_target_pool_size,
      12
    ) AS target_size,
    GREATEST(
      rpc.max_pool_size,
      rr.default_max_pool_size,
      32
    ) AS base_max_size
  FROM public.route_pool_coverage AS rpc
  JOIN public.route_regions AS rr
    ON rr.country_code = rpc.country_code
   AND rr.admin1_name = rpc.admin1_name
   AND COALESCE(rr.admin2_name, '') = COALESCE(rpc.admin2_name, '')
   AND rr.city_cluster = rpc.city_cluster
  WHERE rr.is_active
    AND NOT (
      rr.difficulty_level = 'hard'
      AND rr.curated_seed_preferred IS TRUE
    )
)
UPDATE public.route_pool_coverage AS rpc
SET
  target_pool_size = desired.target_size,
  max_pool_size = GREATEST(desired.base_max_size, desired.target_size),
  candidate_buffer_limit = GREATEST(
    rpc.candidate_buffer_limit,
    72,
    desired.target_size * 4
  ),
  healthy_threshold = GREATEST(rpc.healthy_threshold, 3),
  updated_at = now()
FROM desired
WHERE rpc.id = desired.id
  AND (
    rpc.target_pool_size < desired.target_size
    OR rpc.max_pool_size < GREATEST(desired.base_max_size, desired.target_size)
    OR rpc.candidate_buffer_limit < GREATEST(72, desired.target_size * 4)
  );

UPDATE public.route_seed_jobs
SET
  max_mapbox_calls = GREATEST(
    max_mapbox_calls,
    CASE WHEN job_kind IN ('user_demand_learning', 'manual_seed') THEN 48 ELSE 36 END
  ),
  daily_attempt_budget = GREATEST(daily_attempt_budget, 240),
  monthly_attempt_budget = GREATEST(monthly_attempt_budget, 4000),
  daily_mapbox_budget = GREATEST(daily_mapbox_budget, 300),
  monthly_mapbox_budget = GREATEST(monthly_mapbox_budget, 4000),
  updated_at = now()
WHERE
  max_mapbox_calls < CASE WHEN job_kind IN ('user_demand_learning', 'manual_seed') THEN 48 ELSE 36 END
  OR daily_attempt_budget < 240
  OR monthly_attempt_budget < 4000
  OR daily_mapbox_budget < 300
  OR monthly_mapbox_budget < 4000;

UPDATE public.route_seed_jobs
SET
  status = 'queued',
  last_error = 'route_pool_capacity_increased_requeued',
  last_failure_reason = NULL,
  cooldown_until = NULL,
  next_retry_at = NULL,
  updated_at = now()
WHERE status = 'paused_budget'
  AND COALESCE(last_error, '') IN (
    'request_budget_exhausted',
    'job_budget_exhausted',
    'global_budget_exhausted',
    'budget_defaults_increased_requeued'
  );

DO $$
BEGIN
  PERFORM cron.unschedule('process_route_seed_jobs_every_2_minutes');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

SELECT cron.schedule(
  'process_route_seed_jobs_every_2_minutes',
  '* * * * *',
  $$
  SELECT
    net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'route_pool_healing_project_url'
        LIMIT 1
      ) || '/functions/v1/process-route-seed-jobs',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_pool_healing_cron_secret'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'pg_cron',
        'max_jobs_per_run', 3,
        'max_mapbox_calls_per_run', 60,
        'max_runtime_seconds', 105,
        'target_verified_per_job', 2,
        'max_verified_per_cluster_per_run', 3
      ),
      timeout_milliseconds := 115000
    ) AS request_id;
  $$
);

DO $$
BEGIN
  PERFORM cron.unschedule('process_route_search_sessions_every_minute');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

SELECT cron.schedule(
  'process_route_search_sessions_every_minute',
  '* * * * *',
  $$
  SELECT
    net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'route_pool_healing_project_url'
        LIMIT 1
      ) || '/functions/v1/process-route-search-sessions',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_search_session_cron_secret'
          LIMIT 1
        ),
        'x-cron-secret', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_search_session_cron_secret'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'pg_cron',
        'max_sessions_per_run', 2,
        'max_hydrations_per_run', 2,
        'max_runtime_seconds', 60
      ),
      timeout_milliseconds := 70000
    ) AS request_id;
  $$
);
