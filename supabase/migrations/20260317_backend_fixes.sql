-- ============================================================
-- Backend Fixes: Routes, Comments, RLS, Analytics
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Routes RLS fix: Edge Function speichert mit SERVICE_ROLE_KEY
--    (bypassed RLS), aber App liest mit User-JWT.
--    Wir erlauben SELECT auf eigene UND öffentliche Routen mit Rating.
-- ─────────────────────────────────────────────────────────────

-- Bestehende restriktive Policies entfernen
DROP POLICY IF EXISTS "User sieht eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User speichert eigene Routen" ON public.routes;
DROP POLICY IF EXISTS "User löscht eigene Routen" ON public.routes;

-- Neue Policies: eigene Routen + öffentlich bewertete Routen
CREATE POLICY "User sieht eigene Routen"
  ON public.routes FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Öffentliche bewertete Routen sind lesbar"
  ON public.routes FOR SELECT
  USING (rating IS NOT NULL AND rating >= 3);

CREATE POLICY "User speichert eigene Routen"
  ON public.routes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "User kann eigene Routen updaten"
  ON public.routes FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "User löscht eigene Routen"
  ON public.routes FOR DELETE
  USING (auth.uid() = user_id);


-- ─────────────────────────────────────────────────────────────
-- 2. Comments Tabelle (fehlte komplett)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz DEFAULT now(),
  post_id uuid REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  content text NOT NULL
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Comments sind öffentlich lesbar" ON comments FOR SELECT USING (true);
CREATE POLICY "User kann kommentieren" ON comments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "User kann eigene Comments löschen" ON comments FOR DELETE USING (auth.uid() = user_id);

-- FK zu profiles für PostgREST joins
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'comments_user_id_profiles_fkey' AND table_name = 'comments'
  ) THEN
    ALTER TABLE comments
      ADD CONSTRAINT comments_user_id_profiles_fkey
      FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END $$;

-- RPC: Comments count inkrementieren/dekrementieren
CREATE OR REPLACE FUNCTION increment_comments(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET comments_count = comments_count + 1 WHERE id = post_id_param;
END;
$$;

CREATE OR REPLACE FUNCTION decrement_comments(post_id_param uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = post_id_param;
END;
$$;


-- ─────────────────────────────────────────────────────────────
-- 3. Follower/Following Counts automatisch aktualisieren
--    (Trigger statt manuelle Zählung)
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_follow_counts()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE profiles SET follower_count = follower_count + 1 WHERE id = NEW.following_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE profiles SET following_count = GREATEST(following_count - 1, 0) WHERE id = OLD.follower_id;
    UPDATE profiles SET follower_count = GREATEST(follower_count - 1, 0) WHERE id = OLD.following_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS on_follow_change ON follows;
CREATE TRIGGER on_follow_change
  AFTER INSERT OR DELETE ON follows
  FOR EACH ROW EXECUTE FUNCTION update_follow_counts();


-- ─────────────────────────────────────────────────────────────
-- 4. User-Suche verbessern: Index auf username + email
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_profiles_username ON profiles USING btree (lower(username));
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles USING btree (lower(email));


-- ─────────────────────────────────────────────────────────────
-- 5. Routes: Index für schnellere User-Queries (Analytics)
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_routes_user_id ON routes (user_id);
CREATE INDEX IF NOT EXISTS idx_routes_user_created ON routes (user_id, created_at DESC);


-- ─────────────────────────────────────────────────────────────
-- 6. Posts: Indexes für Feed-Queries
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts (user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created ON posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows (follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows (following_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications (user_id, created_at DESC);
