-- Dynamic Rate-Limit für Auto-Seeder + 15min Cron statt 30min
--
-- Rate-Tier basierend auf Slot-Demand-Volume:
--   low(<10):     3 jobs/15min → 12/h   = 288/day  (~18 cities/day)
--   medium(<50): 10 jobs/15min → 40/h   = 960/day  (~60 cities/day)
--   high(<200):  20 jobs/15min → 80/h   = 1920/day (~120 cities/day)
--   critical(+): 30 jobs/15min → 120/h  = 2880/day (~180 cities/day)

DROP FUNCTION IF EXISTS public.trigger_pool_auto_seed();

CREATE OR REPLACE FUNCTION public.trigger_pool_auto_seed()
RETURNS TABLE (
  queued_count integer, scanned_count integer,
  last_priority double precision, rate_tier text, slot_demand integer
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_queued integer := 0; v_scanned integer := 0;
  v_last_prio double precision := 0; v_slot_demand integer := 0;
  v_max_jobs integer; v_tier text;
  r record;
BEGIN
  SELECT COUNT(*) INTO v_slot_demand
  FROM public.pool_demand_aggregate
  WHERE activity_score > 0.5 AND pool_routes < 5;

  IF v_slot_demand < 10 THEN
    v_max_jobs := 3;  v_tier := 'low';
  ELSIF v_slot_demand < 50 THEN
    v_max_jobs := 10; v_tier := 'medium';
  ELSIF v_slot_demand < 200 THEN
    v_max_jobs := 20; v_tier := 'high';
  ELSE
    v_max_jobs := 30; v_tier := 'critical';
  END IF;

  FOR r IN
    SELECT * FROM public.pool_demand_aggregate
    WHERE activity_score > 0.5 AND pool_routes < 5
    ORDER BY demand_priority DESC LIMIT v_max_jobs * 3
  LOOP
    v_scanned := v_scanned + 1;
    IF EXISTS (
      SELECT 1 FROM public.pool_auto_seed_jobs
      WHERE city_cluster = r.city_cluster AND distance_bucket = r.distance_bucket
        AND style = r.style AND status IN ('pending', 'running')
    ) THEN CONTINUE; END IF;
    INSERT INTO public.pool_auto_seed_jobs (city_cluster, country_code, seed_lat, seed_lng, distance_bucket, style, priority)
    SELECT r.city_cluster, r.country_code, AVG(search_lat), AVG(search_lng), r.distance_bucket, r.style, r.demand_priority
    FROM public.pool_demand_log
    WHERE search_city_cluster = r.city_cluster AND logged_at > NOW() - INTERVAL '7 days'
    GROUP BY search_city_cluster;
    v_queued := v_queued + 1;
    v_last_prio := r.demand_priority;
    EXIT WHEN v_queued >= v_max_jobs;
  END LOOP;

  RETURN QUERY SELECT v_queued, v_scanned, v_last_prio, v_tier, v_slot_demand;
END $$;

DO $$
DECLARE existing_jobid integer;
BEGIN
  SELECT jobid INTO existing_jobid FROM cron.job WHERE jobname = 'dach_pool_auto_seeder';
  IF existing_jobid IS NOT NULL THEN PERFORM cron.unschedule(existing_jobid); END IF;
END $$;

SELECT cron.schedule('dach_pool_auto_seeder', '*/15 * * * *',
  $$SELECT public.trigger_pool_auto_seed();$$);
