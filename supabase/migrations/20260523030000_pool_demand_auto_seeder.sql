-- Demand-Driven Pool Auto-Seeder (vucko Task #6)
--
-- Ziel: User in einer Region ohne Pool → erste Suchen sind Live, aber im
-- Hintergrund baut der Cloud-Cron einen Pool für diese Region. Nach 24-48h
-- ist der Pool gefüllt, alle Folgesuchen profitieren von Pool-First.
--
-- Architektur:
--   1. pool_demand_log: jedes "live-fallback weil kein pool" wird gelogged
--   2. pool_demand_buckets (view): aggregiert demand pro (region, bucket, style)
--      mit Activity-Score (recent searches × distinct users)
--   3. pool_auto_seed_jobs: queue mit pending seed-jobs, processed by edge worker
--   4. trigger_pool_auto_seed() function: scannt demand, queued neue jobs
--   5. pg_cron: ruft trigger_pool_auto_seed() alle 30 Min
--      → schaut Top-Demand-Regions, queued bis zu 3 jobs/run (rate-limit)

-- ========== 1. Demand-Log ==========
CREATE TABLE IF NOT EXISTS public.pool_demand_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  logged_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  -- User-Position bei der Suche
  search_lat double precision NOT NULL,
  search_lng double precision NOT NULL,
  search_city_cluster text,  -- best-match city aus geocoding (kann null sein)
  search_country_code text,

  -- Was wurde gesucht?
  distance_bucket integer NOT NULL,
  style text NOT NULL,
  avoid_highways boolean DEFAULT false,
  route_type text NOT NULL DEFAULT 'ROUND_TRIP',

  -- Was ist passiert?
  pool_attempted boolean DEFAULT true,
  pool_returned_routes integer DEFAULT 0,
  live_succeeded boolean DEFAULT false,
  live_duration_ms integer
);

CREATE INDEX IF NOT EXISTS idx_demand_log_time
  ON public.pool_demand_log(logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_demand_log_region
  ON public.pool_demand_log(search_city_cluster, distance_bucket, style)
  WHERE search_city_cluster IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_demand_log_geo
  ON public.pool_demand_log(search_lat, search_lng);

-- ========== 2. Demand-Aggregation View ==========
-- Activity-Score: log10(recent_searches) × distinct_users / 7d window
-- → kleiner Wert: wenig User, große Region kann warten
-- → hoher Wert: viele User, sollte schnell Pool kriegen
CREATE OR REPLACE VIEW public.pool_demand_aggregate AS
WITH recent AS (
  SELECT
    search_city_cluster AS city_cluster,
    search_country_code AS country_code,
    distance_bucket,
    style,
    COUNT(*) AS recent_searches,
    COUNT(DISTINCT user_id) AS distinct_users,
    AVG(pool_returned_routes) AS avg_pool_routes,
    MAX(logged_at) AS last_search_at
  FROM public.pool_demand_log
  WHERE logged_at > NOW() - INTERVAL '7 days'
    AND search_city_cluster IS NOT NULL
  GROUP BY search_city_cluster, search_country_code, distance_bucket, style
),
pool_state AS (
  SELECT
    city_cluster, country_code, distance_bucket,
    unnest(style_tags) AS style,
    COUNT(*) AS active_routes
  FROM public.route_pool
  WHERE is_active = true AND verified = true
  GROUP BY city_cluster, country_code, distance_bucket, style
)
SELECT
  r.city_cluster, r.country_code, r.distance_bucket, r.style,
  r.recent_searches, r.distinct_users, r.avg_pool_routes, r.last_search_at,
  COALESCE(ps.active_routes, 0) AS pool_routes,
  -- Activity-Score: weighted (mehr User > mehr searches)
  (LOG(GREATEST(r.recent_searches, 1)::numeric + 1)::float * r.distinct_users::float) AS activity_score,
  -- Demand-Priority: niedrige pool_routes + hohes activity = höchste prio
  (LOG(GREATEST(r.recent_searches, 1)::numeric + 1)::float * r.distinct_users::float)
    / GREATEST(COALESCE(ps.active_routes, 0) + 1, 1)::float AS demand_priority
FROM recent r
LEFT JOIN pool_state ps USING (city_cluster, country_code, distance_bucket, style)
ORDER BY demand_priority DESC;

-- ========== 3. Auto-Seed-Job-Queue ==========
CREATE TABLE IF NOT EXISTS public.pool_auto_seed_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  city_cluster text NOT NULL,
  country_code text NOT NULL,
  seed_lat double precision NOT NULL,
  seed_lng double precision NOT NULL,
  distance_bucket integer NOT NULL,
  style text NOT NULL,
  -- Status-Lifecycle
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
  priority double precision NOT NULL DEFAULT 0,
  -- Tracking
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  routes_added integer DEFAULT 0,
  error_message text,
  -- Worker-Lock damit nicht 2 worker dasselbe job gleichzeitig
  worker_id text,
  worker_lock_until timestamptz,
  UNIQUE (city_cluster, distance_bucket, style, status) DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX IF NOT EXISTS idx_auto_seed_jobs_pending
  ON public.pool_auto_seed_jobs(priority DESC, created_at ASC)
  WHERE status = 'pending';

-- ========== 4. Trigger-Function: scan demand → queue jobs ==========
-- Rate-Limits:
--   - max 3 new jobs pro trigger-call (cron-tick = alle 30 min → max 6/h = 144/day)
--   - nur Combos die: activity_score > 0.5 (mindestens 1 user multi search)
--     UND pool_routes < 5 (Slot ist unter-versorgt)
--   - Skip wenn schon pending/running job für selbe Combo existiert
CREATE OR REPLACE FUNCTION public.trigger_pool_auto_seed()
RETURNS TABLE (queued_count integer, scanned_count integer, last_priority double precision)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_queued integer := 0;
  v_scanned integer := 0;
  v_last_prio double precision := 0;
  r record;
BEGIN
  FOR r IN
    SELECT * FROM public.pool_demand_aggregate
    WHERE activity_score > 0.5
      AND pool_routes < 5
    ORDER BY demand_priority DESC
    LIMIT 20  -- scan top 20
  LOOP
    v_scanned := v_scanned + 1;
    -- Skip wenn schon pending/running job existiert
    IF EXISTS (
      SELECT 1 FROM public.pool_auto_seed_jobs
      WHERE city_cluster = r.city_cluster
        AND distance_bucket = r.distance_bucket
        AND style = r.style
        AND status IN ('pending', 'running')
    ) THEN
      CONTINUE;
    END IF;

    -- Queue
    INSERT INTO public.pool_auto_seed_jobs
      (city_cluster, country_code, seed_lat, seed_lng,
       distance_bucket, style, priority)
    SELECT
      r.city_cluster, r.country_code,
      AVG(search_lat), AVG(search_lng),  -- Centroid der user-Suchen
      r.distance_bucket, r.style, r.demand_priority
    FROM public.pool_demand_log
    WHERE search_city_cluster = r.city_cluster
      AND logged_at > NOW() - INTERVAL '7 days'
    GROUP BY search_city_cluster
    ON CONFLICT DO NOTHING;
    v_queued := v_queued + 1;
    v_last_prio := r.demand_priority;

    -- Rate-limit: max 3 new jobs pro Trigger
    EXIT WHEN v_queued >= 3;
  END LOOP;

  RETURN QUERY SELECT v_queued, v_scanned, v_last_prio;
END $$;

-- ========== 5. pg_cron Job — alle 30 Min ==========
DO $$
DECLARE
  existing_jobid integer;
BEGIN
  SELECT jobid INTO existing_jobid FROM cron.job WHERE jobname = 'dach_pool_auto_seeder';
  IF existing_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(existing_jobid);
  END IF;
END $$;

SELECT cron.schedule(
  'dach_pool_auto_seeder',
  '*/30 * * * *',  -- alle 30 Min
  $$SELECT public.trigger_pool_auto_seed();$$
);

-- ========== 6. Log-Helper für Flutter ==========
-- Aufruf vom Edge-Function/Flutter wenn live-fallback weil pool leer war
CREATE OR REPLACE FUNCTION public.log_pool_demand(
  p_user_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_city text,
  p_country text,
  p_bucket integer,
  p_style text,
  p_avoid_highways boolean,
  p_pool_routes_found integer,
  p_live_succeeded boolean,
  p_live_duration_ms integer
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.pool_demand_log
    (user_id, search_lat, search_lng, search_city_cluster, search_country_code,
     distance_bucket, style, avoid_highways,
     pool_returned_routes, live_succeeded, live_duration_ms)
  VALUES
    (p_user_id, p_lat, p_lng, p_city, p_country,
     p_bucket, p_style, p_avoid_highways,
     p_pool_routes_found, p_live_succeeded, p_live_duration_ms)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ========== RLS ==========
ALTER TABLE public.pool_demand_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "demand_log_insert_own" ON public.pool_demand_log;
CREATE POLICY "demand_log_insert_own" ON public.pool_demand_log
  FOR INSERT WITH CHECK (auth.uid() = user_id OR user_id IS NULL);
DROP POLICY IF EXISTS "demand_log_admin_select" ON public.pool_demand_log;
-- Admin-Lesen via SECURITY DEFINER functions (kein direct SELECT für users)

ALTER TABLE public.pool_auto_seed_jobs ENABLE ROW LEVEL SECURITY;
-- Nur via SECURITY DEFINER functions zugänglich

COMMENT ON TABLE public.pool_demand_log IS
  'Log aller Suchen mit Region-Context — Demand-Tracking für Auto-Seeder.';
COMMENT ON VIEW public.pool_demand_aggregate IS
  'Aggregiert Demand pro (Region × Bucket × Style) — activity_score + demand_priority.';
COMMENT ON TABLE public.pool_auto_seed_jobs IS
  'Queue: hochpriore Combos werden vom Cloud-Worker step-by-step abgearbeitet.';
COMMENT ON FUNCTION public.trigger_pool_auto_seed IS
  'pg_cron tick (alle 30 Min): scant Demand, queued max 3 neue seed-jobs/run.';
COMMENT ON FUNCTION public.log_pool_demand IS
  'Flutter-Hook: bei jeder Suche aufrufen damit Demand-Tracking läuft.';
