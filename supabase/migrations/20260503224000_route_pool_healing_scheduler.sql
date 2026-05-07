-- Scheduled route-pool healing worker.
-- Secrets are intentionally read from Supabase Vault at runtime; do not
-- hardcode service-role tokens in migrations.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;

ALTER TABLE public.route_seed_jobs
  ADD COLUMN IF NOT EXISTS daily_mapbox_budget integer NOT NULL DEFAULT 12
    CHECK (daily_mapbox_budget BETWEEN 0 AND 200),
  ADD COLUMN IF NOT EXISTS monthly_mapbox_budget integer NOT NULL DEFAULT 120
    CHECK (monthly_mapbox_budget BETWEEN 0 AND 2000),
  ADD COLUMN IF NOT EXISTS daily_mapbox_count integer NOT NULL DEFAULT 0
    CHECK (daily_mapbox_count >= 0),
  ADD COLUMN IF NOT EXISTS monthly_mapbox_count integer NOT NULL DEFAULT 0
    CHECK (monthly_mapbox_count >= 0),
  ADD COLUMN IF NOT EXISTS mapbox_budget_window_date date NOT NULL DEFAULT current_date,
  ADD COLUMN IF NOT EXISTS mapbox_budget_window_month date NOT NULL DEFAULT date_trunc('month', now())::date;

CREATE INDEX IF NOT EXISTS idx_route_seed_jobs_mapbox_budget_windows
  ON public.route_seed_jobs (
    mapbox_budget_window_date,
    mapbox_budget_window_month,
    status
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
        'max_mapbox_calls_per_run', 12,
        'max_runtime_seconds', 90,
        'target_verified_per_job', 1
      ),
      timeout_milliseconds := 100000
    ) AS request_id;
  $$
);
