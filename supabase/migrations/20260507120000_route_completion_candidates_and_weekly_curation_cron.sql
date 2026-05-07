-- Let real completed/saved/discarded user routes enter the candidate queue
-- without auto-verification. Weekly curation remains non-destructive and
-- promotes only through the trusted Edge Function.

DO $$
DECLARE
  constraint_name text;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.route_pool_candidates'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) ILIKE '%candidate_source%'
  LIMIT 1;

  IF constraint_name IS NOT NULL THEN
    EXECUTE format(
      'ALTER TABLE public.route_pool_candidates DROP CONSTRAINT %I',
      constraint_name
    );
  END IF;

  ALTER TABLE public.route_pool_candidates
    ADD CONSTRAINT route_pool_candidates_candidate_source_check
    CHECK (
      candidate_source IN (
        'basic_live',
        'premium_live',
        'bootstrap',
        'imported',
        'route_completion_candidate',
        'user_route_feedback'
      )
    );
END
$$;

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault CASCADE;

DO $$
BEGIN
  PERFORM cron.unschedule('weekly-route-pool-curation');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$$;

SELECT cron.schedule(
  'weekly-route-pool-curation',
  '59 23 * * 0',
  $$
  SELECT
    net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'route_pool_healing_project_url'
        LIMIT 1
      ) || '/functions/v1/curate-route-pool',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_pool_curation_cron_secret'
          LIMIT 1
        ),
        'x-cron-secret', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'route_pool_curation_cron_secret'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'pg_cron',
        'trigger', 'weekly_cron'
      ),
      timeout_milliseconds := 60000
    ) AS request_id;
  $$
);
