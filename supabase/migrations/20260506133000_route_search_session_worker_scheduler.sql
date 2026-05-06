-- Dedicated worker for persistent roundtrip search-session hydration.
-- The cron secret is read from Supabase Vault at runtime; no token is stored
-- in this migration.

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;

UPDATE public.route_search_sessions
SET
  status = 'queued',
  progress_stage = 'queued_worker_hydration',
  locked_until = NULL,
  updated_at = now()
WHERE
  status IN ('running', 'hydrating')
  AND expires_at > now();

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
          WHERE name = 'route_pool_healing_cron_secret'
          LIMIT 1
        ),
        'x-cron-secret', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_pool_healing_cron_secret'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'pg_cron',
        'max_sessions_per_run', 2,
        'max_hydrations_per_run', 2,
        'max_runtime_seconds', 45
      ),
      timeout_milliseconds := 60000
    ) AS request_id;
  $$
);
