INSERT INTO public.route_regions (
  country_code,
  admin1_name,
  admin2_name,
  city_cluster,
  center_lat,
  center_lng,
  fallback_radius_km,
  population_weight
) VALUES (
  'AT',
  'Vorarlberg',
  'Rheintal-Sued',
  'Rheintal-Sued',
  47.3499,
  9.6584,
  12,
  2
)
ON CONFLICT DO NOTHING;
