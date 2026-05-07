-- Include pg_net HTTP response rows in the service-role-only diagnostics RPC.

CREATE OR REPLACE FUNCTION public.route_search_session_worker_diagnostics()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron, net, extensions
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'extensions', (
      SELECT COALESCE(jsonb_agg(extname ORDER BY extname), '[]'::jsonb)
      FROM pg_extension
      WHERE extname IN ('pg_cron', 'pg_net', 'supabase_vault')
    ),
    'jobs', (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'jobid', jobid,
            'jobname', jobname,
            'schedule', schedule,
            'active', active
          )
          ORDER BY jobid DESC
        ),
        '[]'::jsonb
      )
      FROM cron.job
      WHERE jobname IN (
        'process_route_search_sessions_every_minute',
        'process_route_seed_jobs_every_2_minutes'
      )
    ),
    'recent_runs', (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'jobid', jobid,
            'status', status,
            'return_message', left(COALESCE(return_message, ''), 500),
            'start_time', start_time,
            'end_time', end_time
          )
          ORDER BY start_time DESC
        ),
        '[]'::jsonb
      )
      FROM (
        SELECT jobid, status, return_message, start_time, end_time
        FROM cron.job_run_details
        WHERE jobid IN (
          SELECT jobid
          FROM cron.job
          WHERE jobname IN (
            'process_route_search_sessions_every_minute',
            'process_route_seed_jobs_every_2_minutes'
          )
        )
        ORDER BY start_time DESC
        LIMIT 20
      ) runs
    ),
    'http_responses', (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'status_code', status_code,
            'error_msg', left(COALESCE(error_msg, ''), 500),
            'created', created,
            'content', left(COALESCE(content, ''), 800)
          )
          ORDER BY created DESC
        ),
        '[]'::jsonb
      )
      FROM (
        SELECT id, status_code, error_msg, created, content
        FROM net._http_response
        ORDER BY created DESC
        LIMIT 20
      ) responses
    ),
    'sessions', (
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'id', id,
            'status', status,
            'progress_stage', progress_stage,
            'attempts_count', attempts_count,
            'mapbox_calls_used', mapbox_calls_used,
            'worker_last_seen_at', worker_last_seen_at,
            'has_candidate', best_candidate_payload IS NOT NULL,
            'queue_count', jsonb_array_length(COALESCE(candidate_queue_payload, '[]'::jsonb)),
            'has_route', best_route_payload IS NOT NULL,
            'last_error', last_error,
            'updated_at', updated_at
          )
          ORDER BY created_at DESC
        ),
        '[]'::jsonb
      )
      FROM (
        SELECT *
        FROM public.route_search_sessions
        ORDER BY created_at DESC
        LIMIT 20
      ) sessions
    )
  )
  INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.route_search_session_worker_diagnostics()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.route_search_session_worker_diagnostics()
  TO service_role;
