-- Reschedule search-session hydration with its dedicated cron secret.

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
        'max_hydrations_per_run', 1,
        'max_runtime_seconds', 45
      ),
      timeout_milliseconds := 60000
    ) AS request_id;
  $$
);
