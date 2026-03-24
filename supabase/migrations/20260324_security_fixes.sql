-- ============================================================
-- Security & Integrity Fixes
-- 1. ON DELETE CASCADE für routes.user_id
-- 2. RLS: Öffentliche Routen nur für authentifizierte User
-- 3. Composite Index für follows (follower_id, following_id)
-- 4. Content-Länge Constraints
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. routes.user_id → ON DELETE CASCADE hinzufügen
--    Verhindert verwaiste Routen wenn ein User gelöscht wird
-- ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- Alte FK ohne CASCADE entfernen
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'routes_user_id_fkey' AND table_name = 'routes'
  ) THEN
    ALTER TABLE routes DROP CONSTRAINT routes_user_id_fkey;
  END IF;

  -- Neue FK mit CASCADE erstellen
  ALTER TABLE routes
    ADD CONSTRAINT routes_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
END $$;


-- ─────────────────────────────────────────────────────────────
-- 2. RLS: Öffentliche bewertete Routen nur für eingeloggte User
--    Vorher: Jeder (auch unauthentifiziert) konnte alle bewerteten
--    Routen abfragen → Datenschutzrisiko
-- ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Öffentliche bewertete Routen sind lesbar" ON public.routes;
CREATE POLICY "Öffentliche bewertete Routen sind lesbar"
  ON public.routes FOR SELECT
  USING (auth.role() = 'authenticated' AND rating IS NOT NULL AND rating >= 3);


-- ─────────────────────────────────────────────────────────────
-- 3. Composite Index für schnellere Follow-Lookups
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_follows_follower_following
  ON follows (follower_id, following_id);


-- ─────────────────────────────────────────────────────────────
-- 4. Content-Länge Constraints (Schutz vor übergroßen Daten)
-- ─────────────────────────────────────────────────────────────

ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_content_length;
ALTER TABLE posts ADD CONSTRAINT posts_content_length
  CHECK (length(content) > 0 AND length(content) <= 5000);

ALTER TABLE comments DROP CONSTRAINT IF EXISTS comments_content_length;
ALTER TABLE comments ADD CONSTRAINT comments_content_length
  CHECK (length(content) > 0 AND length(content) <= 2000);

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_bio_length;
ALTER TABLE profiles ADD CONSTRAINT profiles_bio_length
  CHECK (bio IS NULL OR length(bio) <= 500);

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_username_not_empty;
ALTER TABLE profiles ADD CONSTRAINT profiles_username_not_empty
  CHECK (username IS NOT NULL AND length(username) >= 1 AND length(username) <= 50);


-- ─────────────────────────────────────────────────────────────
-- 5. routes Tabelle: Fehlende Spalten sicherstellen
--    'name' existiert im init.sql, fehlt aber in manchen Deployments
-- ─────────────────────────────────────────────────────────────

ALTER TABLE routes ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS route_type text;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS duration_seconds float;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS rating int;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS driven_km float;
