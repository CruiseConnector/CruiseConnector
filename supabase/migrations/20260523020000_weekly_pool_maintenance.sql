-- Weekly Pool Maintenance — autonomer Sonntag-23:59 Cron
--
-- pg_cron Job ruft jeden Sonntag um 23:59 (UTC) die 3 Lifecycle-Funktionen:
--   1. refresh_pool_route_ratings()   → User-Bewertungen aggregieren
--   2. decay_pool_rotation_scores()   → Alte ungenutzte Routes runtergewichten
--   3. Coverage-Audit-Log              → welche Slots brauchen mehr seeds
--
-- Schedule: '59 23 * * 0' = Sonntag (0) um 23:59 UTC
-- (CEST: 01:59 Montag früh — perfekt für off-peak)

-- Coverage-Audit als persistente Tabelle (statt View) für Trend-Tracking
CREATE TABLE IF NOT EXISTS public.route_pool_coverage_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  snapshot_at timestamptz NOT NULL DEFAULT now(),
  city_cluster text NOT NULL,
  country_code text NOT NULL,
  distance_bucket integer NOT NULL,
  style text NOT NULL,
  active_routes integer NOT NULL,
  avg_user_rating double precision,
  avg_quality_score double precision,
  flagged_low_coverage boolean GENERATED ALWAYS AS (active_routes < 5) STORED
);

CREATE INDEX IF NOT EXISTS idx_coverage_snapshot_time
  ON public.route_pool_coverage_snapshot(snapshot_at DESC);
CREATE INDEX IF NOT EXISTS idx_coverage_snapshot_flagged
  ON public.route_pool_coverage_snapshot(flagged_low_coverage, snapshot_at DESC)
  WHERE flagged_low_coverage = true;

CREATE OR REPLACE FUNCTION public.weekly_pool_maintenance()
RETURNS TABLE (
  updated integer, promoted integer, demoted integer,
  decayed integer, snapshots integer, low_coverage_slots integer
) LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  r record;
  v_updated integer := 0;
  v_promoted integer := 0;
  v_demoted integer := 0;
  v_decayed integer := 0;
  v_snapshots integer := 0;
  v_low_coverage integer := 0;
BEGIN
  -- 1. Aggregate ratings + promote/demote
  SELECT * INTO r FROM public.refresh_pool_route_ratings();
  v_updated := r.updated_count;
  v_promoted := r.promoted_count;
  v_demoted := r.demoted_count;

  -- 2. Decay old unused
  SELECT * INTO r FROM public.decay_pool_rotation_scores();
  v_decayed := r.decayed_count;

  -- 3. Coverage-Snapshot
  INSERT INTO public.route_pool_coverage_snapshot
    (city_cluster, country_code, distance_bucket, style,
     active_routes, avg_user_rating, avg_quality_score)
  SELECT
    city_cluster, country_code, distance_bucket, unnest(style_tags) AS style,
    COUNT(*), AVG(average_rating), AVG(quality_score)
  FROM public.route_pool
  WHERE is_active = true AND verified = true
  GROUP BY city_cluster, country_code, distance_bucket, style;
  GET DIAGNOSTICS v_snapshots = ROW_COUNT;

  SELECT COUNT(*) INTO v_low_coverage
  FROM public.route_pool_coverage_snapshot
  WHERE snapshot_at > NOW() - INTERVAL '1 minute' AND flagged_low_coverage = true;

  RETURN QUERY SELECT v_updated, v_promoted, v_demoted, v_decayed, v_snapshots, v_low_coverage;
END $$;

-- Unschedule existing if present (idempotent re-apply)
DO $$
DECLARE
  existing_jobid integer;
BEGIN
  SELECT jobid INTO existing_jobid FROM cron.job WHERE jobname = 'dach_weekly_pool_maintenance';
  IF existing_jobid IS NOT NULL THEN
    PERFORM cron.unschedule(existing_jobid);
  END IF;
END $$;

-- Schedule: Sonntag 23:59 UTC = Mo 01:59 CEST (off-peak)
SELECT cron.schedule(
  'dach_weekly_pool_maintenance',
  '59 23 * * 0',
  $$SELECT public.weekly_pool_maintenance();$$
);

COMMENT ON FUNCTION public.weekly_pool_maintenance IS
  'Wöchentlicher Pool-Lifecycle: Ratings aggregieren, promote/demote, decay, Coverage-Snapshot. Cron: Sonntag 23:59 UTC.';
