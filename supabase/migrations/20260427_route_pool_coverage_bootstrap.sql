-- Controlled regional pool coverage, bootstrap jobs, and candidate staging.
-- This keeps region clusters fixed and prevents unbounded verified pool growth.

ALTER TABLE public.route_regions
  ADD COLUMN IF NOT EXISTS cluster_kind text NOT NULL DEFAULT 'city_cluster'
    CHECK (cluster_kind IN ('city_cluster', 'metro_cluster', 'regional_cluster')),
  ADD COLUMN IF NOT EXISTS bootstrap_enabled boolean NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS public.route_pool_coverage (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  route_region_id uuid REFERENCES public.route_regions(id) ON DELETE CASCADE,
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  admin1_name text NOT NULL CHECK (length(trim(admin1_name)) > 0),
  admin2_name text,
  city_cluster text NOT NULL CHECK (length(trim(city_cluster)) > 0),
  start_lat double precision NOT NULL CHECK (start_lat BETWEEN -90 AND 90),
  start_lng double precision NOT NULL CHECK (start_lng BETWEEN -180 AND 180),
  distance_km double precision CHECK (distance_km IS NULL OR distance_km > 0),
  route_type text NOT NULL CHECK (route_type IN ('ROUND_TRIP', 'POINT_TO_POINT')),
  distance_bucket integer NOT NULL CHECK (distance_bucket IN (50, 75, 100)),
  style_key text NOT NULL CHECK (length(trim(style_key)) > 0),
  avoid_highways boolean NOT NULL DEFAULT false,
  coverage_status text NOT NULL DEFAULT 'empty'
    CHECK (coverage_status IN ('healthy', 'thin', 'empty', 'warming_up', 'cooldown')),
  target_pool_size integer NOT NULL DEFAULT 15 CHECK (target_pool_size BETWEEN 1 AND 100),
  max_pool_size integer NOT NULL DEFAULT 20 CHECK (max_pool_size BETWEEN 1 AND 100 AND max_pool_size >= target_pool_size),
  current_verified_count integer NOT NULL DEFAULT 0 CHECK (current_verified_count >= 0),
  current_candidate_count integer NOT NULL DEFAULT 0 CHECK (current_candidate_count >= 0),
  last_counted_at timestamptz,
  last_bootstrap_requested_at timestamptz,
  last_seed_completed_at timestamptz,
  bootstrap_cooldown_until timestamptz,
  last_error text
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_pool_coverage_unique
  ON public.route_pool_coverage (
    country_code,
    admin1_name,
    COALESCE(admin2_name, ''),
    city_cluster,
    route_type,
    distance_bucket,
    style_key,
    avoid_highways
  );

CREATE INDEX IF NOT EXISTS idx_route_pool_coverage_status
  ON public.route_pool_coverage (
    coverage_status,
    country_code,
    admin1_name,
    city_cluster,
    route_type,
    distance_bucket
  );

CREATE TABLE IF NOT EXISTS public.route_seed_jobs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  route_region_id uuid REFERENCES public.route_regions(id) ON DELETE CASCADE,
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  admin1_name text NOT NULL CHECK (length(trim(admin1_name)) > 0),
  admin2_name text,
  city_cluster text NOT NULL CHECK (length(trim(city_cluster)) > 0),
  route_type text NOT NULL CHECK (route_type IN ('ROUND_TRIP', 'POINT_TO_POINT')),
  distance_bucket integer NOT NULL CHECK (distance_bucket IN (50, 75, 100)),
  style_key text NOT NULL CHECK (length(trim(style_key)) > 0),
  avoid_highways boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cooldown', 'cancelled')),
  priority integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 3 CHECK (max_attempts BETWEEN 1 AND 10),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error text,
  cooldown_until timestamptz,
  last_requested_at timestamptz DEFAULT now() NOT NULL,
  started_at timestamptz,
  completed_at timestamptz,
  triggered_by_tier text CHECK (triggered_by_tier IN ('free', 'basic', 'premium'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_seed_jobs_unique_request
  ON public.route_seed_jobs (
    country_code,
    admin1_name,
    COALESCE(admin2_name, ''),
    city_cluster,
    route_type,
    distance_bucket,
    style_key,
    avoid_highways
  );

CREATE INDEX IF NOT EXISTS idx_route_seed_jobs_status
  ON public.route_seed_jobs (status, cooldown_until, priority DESC, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.route_pool_candidates (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  route_region_id uuid REFERENCES public.route_regions(id) ON DELETE SET NULL,
  route_fingerprint text NOT NULL,
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  admin1_name text NOT NULL CHECK (length(trim(admin1_name)) > 0),
  admin2_name text,
  city_cluster text NOT NULL CHECK (length(trim(city_cluster)) > 0),
  route_type text NOT NULL CHECK (route_type IN ('ROUND_TRIP', 'POINT_TO_POINT')),
  distance_bucket integer NOT NULL CHECK (distance_bucket IN (50, 75, 100)),
  style_key text NOT NULL CHECK (length(trim(style_key)) > 0),
  style_tags text[] NOT NULL DEFAULT '{}',
  avoid_highways boolean NOT NULL DEFAULT false,
  has_highway boolean NOT NULL DEFAULT false,
  quality_score double precision NOT NULL DEFAULT 0 CHECK (quality_score >= 0 AND quality_score <= 100),
  shape_score double precision NOT NULL DEFAULT 0 CHECK (shape_score >= 0 AND shape_score <= 100),
  candidate_source text NOT NULL
    CHECK (candidate_source IN ('basic_live', 'premium_live', 'bootstrap', 'imported')),
  average_rating double precision CHECK (average_rating IS NULL OR (average_rating >= 0 AND average_rating <= 5)),
  rating_count integer NOT NULL DEFAULT 0 CHECK (rating_count >= 0),
  completion_rate double precision CHECK (completion_rate IS NULL OR (completion_rate >= 0 AND completion_rate <= 1)),
  times_selected integer NOT NULL DEFAULT 0 CHECK (times_selected >= 0),
  last_selected_at timestamptz,
  promoted_to_pool_at timestamptz,
  demoted_at timestamptz,
  is_candidate boolean NOT NULL DEFAULT true,
  is_verified_pool boolean NOT NULL DEFAULT false,
  candidate_score double precision,
  geometry jsonb NOT NULL,
  route_payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_pool_candidates_fingerprint
  ON public.route_pool_candidates (route_fingerprint);

CREATE INDEX IF NOT EXISTS idx_route_pool_candidates_lookup
  ON public.route_pool_candidates (
    country_code,
    admin1_name,
    city_cluster,
    route_type,
    distance_bucket,
    style_key,
    avoid_highways,
    is_candidate
  );

ALTER TABLE public.route_pool_coverage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_seed_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_pool_candidates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Route pool coverage ist lesbar" ON public.route_pool_coverage;
CREATE POLICY "Route pool coverage ist lesbar"
  ON public.route_pool_coverage FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Route pool coverage ist schreibbar" ON public.route_pool_coverage;
CREATE POLICY "Route pool coverage ist schreibbar"
  ON public.route_pool_coverage FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Route seed jobs sind lesbar" ON public.route_seed_jobs;
CREATE POLICY "Route seed jobs sind lesbar"
  ON public.route_seed_jobs FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Route seed jobs sind schreibbar" ON public.route_seed_jobs;
CREATE POLICY "Route seed jobs sind schreibbar"
  ON public.route_seed_jobs FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Route pool candidates sind lesbar" ON public.route_pool_candidates;
CREATE POLICY "Route pool candidates sind lesbar"
  ON public.route_pool_candidates FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Route pool candidates sind schreibbar" ON public.route_pool_candidates;
CREATE POLICY "Route pool candidates sind schreibbar"
  ON public.route_pool_candidates FOR ALL
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

WITH grouped_verified AS (
  SELECT
    rr.id AS route_region_id,
    rp.country_code,
    rp.admin1_name,
    rp.admin2_name,
    rp.city_cluster,
    rp.route_type,
    rp.distance_bucket,
    regexp_replace(lower(trim(style_tag)), '[^a-z0-9]+', '_', 'g') AS style_key,
    rp.avoids_highway AS avoid_highways,
    count(*)::integer AS verified_count
  FROM public.route_pool rp
  LEFT JOIN public.route_regions rr
    ON rr.country_code = rp.country_code
   AND rr.admin1_name = rp.admin1_name
   AND COALESCE(rr.admin2_name, '') = COALESCE(rp.admin2_name, '')
   AND rr.city_cluster = rp.city_cluster
  CROSS JOIN LATERAL unnest(
    CASE
      WHEN coalesce(array_length(rp.style_tags, 1), 0) > 0 THEN rp.style_tags
      ELSE ARRAY['standard']::text[]
    END
  ) AS style_tag
  WHERE rp.verified = true
    AND rp.is_active = true
  GROUP BY
    rr.id,
    rp.country_code,
    rp.admin1_name,
    rp.admin2_name,
    rp.city_cluster,
    rp.route_type,
    rp.distance_bucket,
    regexp_replace(lower(trim(style_tag)), '[^a-z0-9]+', '_', 'g'),
    rp.avoids_highway
)
INSERT INTO public.route_pool_coverage (
  route_region_id,
  country_code,
  admin1_name,
  admin2_name,
  city_cluster,
  route_type,
  distance_bucket,
  style_key,
  avoid_highways,
  coverage_status,
  target_pool_size,
  max_pool_size,
  current_verified_count,
  current_candidate_count,
  last_counted_at
)
SELECT
  route_region_id,
  country_code,
  admin1_name,
  admin2_name,
  city_cluster,
  route_type,
  distance_bucket,
  style_key,
  avoid_highways,
  CASE
    WHEN verified_count >= 15 THEN 'healthy'
    WHEN verified_count > 0 THEN 'thin'
    ELSE 'empty'
  END,
  15,
  20,
  verified_count,
  0,
  now()
FROM grouped_verified
ON CONFLICT (
  country_code,
  admin1_name,
  COALESCE(admin2_name, ''),
  city_cluster,
  route_type,
  distance_bucket,
  style_key,
  avoid_highways
) DO UPDATE SET
  route_region_id = EXCLUDED.route_region_id,
  current_verified_count = EXCLUDED.current_verified_count,
  current_candidate_count = EXCLUDED.current_candidate_count,
  coverage_status = EXCLUDED.coverage_status,
  last_counted_at = EXCLUDED.last_counted_at,
  updated_at = now();
