-- Generic DACH-capable route-pool region model.
-- City clusters are data, not hardcoded application constants.

CREATE TABLE IF NOT EXISTS public.route_regions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  admin1_name text NOT NULL CHECK (length(trim(admin1_name)) > 0),
  admin2_name text,
  city_cluster text NOT NULL CHECK (length(trim(city_cluster)) > 0),
  center_lat double precision NOT NULL CHECK (center_lat BETWEEN -90 AND 90),
  center_lng double precision NOT NULL CHECK (center_lng BETWEEN -180 AND 180),
  fallback_radius_km double precision NOT NULL DEFAULT 30
    CHECK (fallback_radius_km >= 12 AND fallback_radius_km <= 45),
  population_weight integer CHECK (population_weight IS NULL OR population_weight >= 0),
  is_active boolean NOT NULL DEFAULT true
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_route_regions_unique_cluster
  ON public.route_regions (
    country_code,
    admin1_name,
    COALESCE(admin2_name, ''),
    city_cluster
  );

CREATE INDEX IF NOT EXISTS idx_route_regions_active_lookup
  ON public.route_regions (country_code, admin1_name, city_cluster)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_route_regions_active_bounds
  ON public.route_regions (center_lat, center_lng)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_route_regions_active_country_admin_bounds
  ON public.route_regions (country_code, admin1_name, center_lat, center_lng)
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS public.route_pool (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title text,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  route_region_id uuid REFERENCES public.route_regions(id) ON DELETE SET NULL,
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  admin1_name text NOT NULL CHECK (length(trim(admin1_name)) > 0),
  admin2_name text,
  city_cluster text NOT NULL CHECK (length(trim(city_cluster)) > 0),
  start_lat double precision NOT NULL CHECK (start_lat BETWEEN -90 AND 90),
  start_lng double precision NOT NULL CHECK (start_lng BETWEEN -180 AND 180),
  end_lat double precision CHECK (end_lat IS NULL OR end_lat BETWEEN -90 AND 90),
  end_lng double precision CHECK (end_lng IS NULL OR end_lng BETWEEN -180 AND 180),
  distance_km double precision NOT NULL CHECK (distance_km > 0),
  distance_bucket integer NOT NULL CHECK (distance_bucket IN (50, 75, 100)),
  route_type text NOT NULL CHECK (route_type IN ('ROUND_TRIP', 'POINT_TO_POINT')),
  style_tags text[] NOT NULL DEFAULT '{}',
  avoids_highway boolean NOT NULL DEFAULT false,
  has_highway boolean NOT NULL DEFAULT false,
  quality_score double precision NOT NULL DEFAULT 0 CHECK (
    quality_score >= 0 AND quality_score <= 100
  ),
  shape_score double precision NOT NULL DEFAULT 0 CHECK (
    shape_score >= 0 AND shape_score <= 100
  ),
  user_rating double precision CHECK (user_rating IS NULL OR (user_rating >= 0 AND user_rating <= 5)),
  usage_count integer NOT NULL DEFAULT 0 CHECK (usage_count >= 0),
  source text NOT NULL DEFAULT 'curated',
  verified boolean NOT NULL DEFAULT false,
  geometry jsonb NOT NULL,
  route_payload jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_route_pool_match_verified
  ON public.route_pool (
    country_code,
    admin1_name,
    city_cluster,
    distance_bucket,
    route_type,
    avoids_highway,
    has_highway,
    quality_score DESC
  )
  WHERE verified = true;

CREATE INDEX IF NOT EXISTS idx_route_pool_start_verified
  ON public.route_pool (country_code, admin1_name, start_lat, start_lng)
  WHERE verified = true;

CREATE INDEX IF NOT EXISTS idx_route_pool_style_tags
  ON public.route_pool USING gin (style_tags);

ALTER TABLE public.route_regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_pool ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Aktive Routenregionen sind lesbar" ON public.route_regions;
CREATE POLICY "Aktive Routenregionen sind lesbar"
  ON public.route_regions FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS "Verifizierte Routenpool-Routen sind lesbar" ON public.route_pool;
CREATE POLICY "Verifizierte Routenpool-Routen sind lesbar"
  ON public.route_pool FOR SELECT
  TO anon, authenticated
  USING (verified = true);

INSERT INTO public.route_regions (
  country_code,
  admin1_name,
  admin2_name,
  city_cluster,
  center_lat,
  center_lng,
  fallback_radius_km,
  population_weight
) VALUES
  ('AT', 'Vorarlberg', 'Bregenz', 'Bregenz', 47.5031, 9.7471, 30, 2),
  ('AT', 'Vorarlberg', 'Dornbirn', 'Dornbirn', 47.4125, 9.7414, 30, 3),
  ('AT', 'Vorarlberg', 'Feldkirch', 'Feldkirch', 47.2386, 9.5986, 30, 2),
  ('AT', 'Vorarlberg', 'Bludenz', 'Bludenz', 47.1548, 9.8220, 35, 1),
  ('AT', 'Tirol', 'Innsbruck-Stadt', 'Innsbruck', 47.2692, 11.4041, 30, 4),
  ('AT', 'Tirol', 'Kufstein', 'Kufstein', 47.5837, 12.1691, 30, 2),
  ('AT', 'Tirol', 'Landeck', 'Landeck', 47.1399, 10.5659, 40, 1),
  ('AT', 'Tirol', 'Kitzbühel', 'Kitzbühel', 47.4464, 12.3922, 35, 1),
  ('DE', 'Bayern', 'München', 'München', 48.1372, 11.5755, 30, 5),
  ('DE', 'Bayern', 'Augsburg', 'Augsburg', 48.3705, 10.8978, 30, 3),
  ('DE', 'Bayern', 'Nürnberg', 'Nürnberg', 49.4521, 11.0767, 30, 4),
  ('DE', 'Bayern', 'Regensburg', 'Regensburg', 49.0134, 12.1016, 30, 3),
  ('DE', 'Bayern', 'Rosenheim', 'Rosenheim', 47.8564, 12.1225, 30, 2),
  ('DE', 'Baden-Württemberg', 'Stuttgart', 'Stuttgart', 48.7758, 9.1829, 30, 5),
  ('DE', 'Baden-Württemberg', 'Freiburg', 'Freiburg', 47.9990, 7.8421, 30, 3),
  ('DE', 'Baden-Württemberg', 'Karlsruhe', 'Karlsruhe', 49.0069, 8.4037, 30, 3),
  ('DE', 'Baden-Württemberg', 'Ulm', 'Ulm', 48.4011, 9.9876, 30, 3),
  ('DE', 'Baden-Württemberg', 'Konstanz', 'Konstanz', 47.6779, 9.1732, 30, 2),
  ('CH', 'St. Gallen', 'St. Gallen', 'St. Gallen', 47.4245, 9.3767, 30, 3),
  ('CH', 'St. Gallen', 'See-Gaster', 'Rapperswil', 47.2267, 8.8188, 30, 2),
  ('CH', 'St. Gallen', 'Sarganserland', 'Sargans', 47.0483, 9.4410, 35, 1),
  ('CH', 'Zürich', 'Zürich', 'Zürich', 47.3769, 8.5417, 30, 5),
  ('CH', 'Zürich', 'Winterthur', 'Winterthur', 47.4999, 8.7286, 30, 3),
  ('CH', 'Zürich', 'Uster', 'Uster', 47.3480, 8.7183, 30, 2)
ON CONFLICT DO NOTHING;
