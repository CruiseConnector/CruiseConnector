-- Task #35 (vucko 2026-05-21): 25 km Distanz-Bucket im Pool-Schema erlauben.
--
-- Bislang waren nur 50/75/100 km erlaubt. Mit dem neuen 25 km UI-Option in
-- cruise_setup_card.dart kann der User jetzt Feierabend-Touren wählen, die
-- aktuell direkt über Live-GraphHopper geroutet werden (kein Pool-Match).
--
-- Diese Migration erlaubt Pool-Routes auch im 25-km-Bucket, damit der
-- Healing-Worker später curated 25er Routen einlegen kann (separater Task).
--
-- Tabellen verifiziert via information_schema 2026-05-21:
--   route_pool, route_pool_candidates, route_pool_coverage,
--   route_search_sessions, route_seed_jobs
--
-- Idempotent: drop old constraint, add new with 25 included.

ALTER TABLE public.route_pool
  DROP CONSTRAINT IF EXISTS route_pool_distance_bucket_check;
ALTER TABLE public.route_pool
  ADD CONSTRAINT route_pool_distance_bucket_check
  CHECK (distance_bucket IN (25, 50, 75, 100));

ALTER TABLE public.route_pool_candidates
  DROP CONSTRAINT IF EXISTS route_pool_candidates_distance_bucket_check;
ALTER TABLE public.route_pool_candidates
  ADD CONSTRAINT route_pool_candidates_distance_bucket_check
  CHECK (distance_bucket IN (25, 50, 75, 100));

ALTER TABLE public.route_pool_coverage
  DROP CONSTRAINT IF EXISTS route_pool_coverage_distance_bucket_check;
ALTER TABLE public.route_pool_coverage
  ADD CONSTRAINT route_pool_coverage_distance_bucket_check
  CHECK (distance_bucket IN (25, 50, 75, 100));

ALTER TABLE public.route_seed_jobs
  DROP CONSTRAINT IF EXISTS route_seed_jobs_distance_bucket_check;
ALTER TABLE public.route_seed_jobs
  ADD CONSTRAINT route_seed_jobs_distance_bucket_check
  CHECK (distance_bucket IN (25, 50, 75, 100));

ALTER TABLE public.route_search_sessions
  DROP CONSTRAINT IF EXISTS route_search_sessions_distance_bucket_check;
ALTER TABLE public.route_search_sessions
  ADD CONSTRAINT route_search_sessions_distance_bucket_check
  CHECK (distance_bucket IN (25, 50, 75, 100));
