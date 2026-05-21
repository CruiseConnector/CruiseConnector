-- Pool Lifecycle Management (vucko Task #39)
--
-- User-Vorgabe: User-Bewertungen → Pool-Update.
--   - Routen mit avg_rating ≥ 4.0 AND rating_count ≥ 3 → boost (quality_score +)
--   - Routen mit avg_rating < 3.0 AND rating_count ≥ 3 → demote (is_active=false)
--   - Routen die >90 Tage alt sind UND niemand bewertet hat → niedrige weekly_rotation_score
--
-- Funktion läuft initial manuell, später via pg_cron (täglich 03:00).

-- Function 1: Aggregate user ratings → update route_pool.average_rating/rating_count
CREATE OR REPLACE FUNCTION public.refresh_pool_route_ratings()
RETURNS TABLE (updated_count integer, promoted_count integer, demoted_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated integer := 0;
  v_promoted integer := 0;
  v_demoted integer := 0;
BEGIN
  -- Update average_rating + rating_count from route_ratings
  WITH agg AS (
    SELECT
      route_fingerprint,
      AVG(rating)::float AS avg_r,
      COUNT(*) AS cnt
    FROM public.route_ratings
    WHERE rating IS NOT NULL AND rating BETWEEN 1 AND 5
    GROUP BY route_fingerprint
  )
  UPDATE public.route_pool rp
  SET average_rating = agg.avg_r,
      rating_count = agg.cnt,
      updated_at = NOW()
  FROM agg
  WHERE rp.route_fingerprint = agg.route_fingerprint
    AND (rp.average_rating IS DISTINCT FROM agg.avg_r OR rp.rating_count IS DISTINCT FROM agg.cnt);
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- Promote: well-rated routes get quality_score boost
  UPDATE public.route_pool
  SET quality_score = LEAST(quality_score + 10, 100.0),
      weekly_rotation_score = LEAST(weekly_rotation_score + 5, 100.0),
      updated_at = NOW()
  WHERE average_rating >= 4.0
    AND rating_count >= 3
    AND quality_score < 90  -- nur wenn noch room
    AND is_active = true;
  GET DIAGNOSTICS v_promoted = ROW_COUNT;

  -- Demote: badly-rated routes → is_active=false (aus Pool-Selection raus)
  UPDATE public.route_pool
  SET is_active = false,
      deprecated_at = NOW(),
      updated_at = NOW()
  WHERE average_rating < 3.0
    AND rating_count >= 3
    AND is_active = true;
  GET DIAGNOSTICS v_demoted = ROW_COUNT;

  RETURN QUERY SELECT v_updated, v_promoted, v_demoted;
END;
$$;

-- Function 2: Decay weekly_rotation_score für alte Routen, boost für frische
CREATE OR REPLACE FUNCTION public.decay_pool_rotation_scores()
RETURNS TABLE (decayed_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_decayed integer := 0;
BEGIN
  -- Routes die >90 Tage alt sind und nie genutzt → niedrigere score
  UPDATE public.route_pool
  SET weekly_rotation_score = GREATEST(weekly_rotation_score - 5, 0.0)
  WHERE is_active = true
    AND created_at < NOW() - INTERVAL '90 days'
    AND usage_count < 3
    AND weekly_rotation_score > 20;
  GET DIAGNOSTICS v_decayed = ROW_COUNT;

  RETURN QUERY SELECT v_decayed;
END;
$$;

-- Function 3: Coverage-Audit-View — zeigt welche (City × Bucket × Style) slots
-- weniger als 5 active routes haben (dann braucht Healing-Worker mehr seeds)
CREATE OR REPLACE VIEW public.route_pool_coverage_audit AS
SELECT
  city_cluster,
  country_code,
  distance_bucket,
  unnest(style_tags) AS style,
  COUNT(*) AS active_routes,
  AVG(average_rating) AS avg_user_rating,
  AVG(quality_score) AS avg_quality_score,
  MIN(created_at) AS oldest_route_at,
  MAX(updated_at) AS most_recent_update
FROM public.route_pool
WHERE is_active = true AND verified = true
GROUP BY city_cluster, country_code, distance_bucket, style
ORDER BY city_cluster, distance_bucket, style;

COMMENT ON FUNCTION public.refresh_pool_route_ratings IS
  'Aggregiert route_ratings → route_pool.average_rating, promotet >=4.0 (+10 quality), demoted <3.0 (is_active=false). Aufruf täglich.';
COMMENT ON FUNCTION public.decay_pool_rotation_scores IS
  'Senkt weekly_rotation_score für ungenutzte alte Routes. Aufruf wöchentlich.';
COMMENT ON VIEW public.route_pool_coverage_audit IS
  'Slots mit <5 routes → Healing-Worker sollte mehr seeds einlegen.';
