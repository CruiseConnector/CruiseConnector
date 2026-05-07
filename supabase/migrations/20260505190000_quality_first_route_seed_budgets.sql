-- Quality-first route seed budgets for live test and premium usage.
-- Keeps provider/global safety caps in the worker, but stops normal seed jobs
-- from being paused by the original 12/120 bootstrap defaults.

ALTER TABLE public.route_seed_jobs
  ALTER COLUMN max_mapbox_calls SET DEFAULT 24,
  ALTER COLUMN daily_attempt_budget SET DEFAULT 120,
  ALTER COLUMN monthly_attempt_budget SET DEFAULT 2000,
  ALTER COLUMN daily_mapbox_budget SET DEFAULT 200,
  ALTER COLUMN monthly_mapbox_budget SET DEFAULT 2000;

UPDATE public.route_seed_jobs
SET
  max_mapbox_calls = GREATEST(
    max_mapbox_calls,
    CASE WHEN job_kind = 'user_demand_learning' THEN 32 ELSE 24 END
  ),
  daily_attempt_budget = GREATEST(
    daily_attempt_budget,
    CASE WHEN job_kind = 'user_demand_learning' THEN 200 ELSE 120 END
  ),
  monthly_attempt_budget = GREATEST(monthly_attempt_budget, 2000),
  daily_mapbox_budget = GREATEST(daily_mapbox_budget, 200),
  monthly_mapbox_budget = GREATEST(monthly_mapbox_budget, 2000),
  updated_at = now()
WHERE
  max_mapbox_calls < CASE WHEN job_kind = 'user_demand_learning' THEN 32 ELSE 24 END
  OR daily_attempt_budget < CASE WHEN job_kind = 'user_demand_learning' THEN 200 ELSE 120 END
  OR monthly_attempt_budget < 2000
  OR daily_mapbox_budget < 200
  OR monthly_mapbox_budget < 2000;

UPDATE public.route_seed_jobs
SET
  status = 'queued',
  last_error = 'budget_defaults_increased_requeued',
  last_failure_reason = NULL,
  cooldown_until = NULL,
  next_retry_at = NULL,
  updated_at = now()
WHERE
  status = 'paused_budget'
  AND COALESCE(last_error, '') IN (
    'request_budget_exhausted',
    'job_budget_exhausted',
    'global_budget_exhausted'
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
  '*/2 * * * *',
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
        'max_jobs_per_run', 2,
        'max_mapbox_calls_per_run', 48,
        'max_runtime_seconds', 90,
        'target_verified_per_job', 1
      ),
      timeout_milliseconds := 100000
    ) AS request_id;
  $$
);
